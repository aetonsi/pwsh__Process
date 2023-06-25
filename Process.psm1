function Get-CommandLine ([parameter(ValueFromPipeline)][int] $processId = $PID) {
    $cl = ( Get-Process -Id $processId ).CommandLine
    if ($null -eq $cl) {
        $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$processId").CommandLine
    }
    return $cl
}


function ConvertTo-EscapedCommandLine(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)][string] $Str,
    [Parameter(Mandatory, ParameterSetName = 'posh')][switch] $ForPowershell,
    [Parameter(Mandatory, ParameterSetName = 'posh2')][switch] $ForPowershell2,
    [Parameter(Mandatory, ParameterSetName = 'poshesc')][switch] $ForPowershellEncodedCommand,
    [Parameter(Mandatory, ParameterSetName = 'cmd')][switch] $ForCmd,
    [Parameter(Mandatory, ParameterSetName = 'c')][switch] $ForCLike
) {
    $enclosing = @('', '')
    if ($ForPowershell) {
        $enclosing = @('''', '''')
        $replacements = @(
            ('''', ''''''),
            ('([\\]*)"', '$1$1\"'),
            ('', '')
        )
    } elseif ($ForPowershell2) {
        $replacements = @(
            ('`', '``' ),
            ('''', '`'''),
            ('"', '`\"'),
            ('\$', '`$'),
            (',', '`,'),
            (';', '`;'),
            ('\{', '`{'),
            ('\}', '`}'),
            ('\(', '`('),
            ('\)', '`)'),
            ('&', '`&'),
            ('\|', '`|')
        )
    } elseif ($ForPowershellEncodedCommand) {
        $bytes = [System.Text.Encoding]::Unicode.GetBytes($Str)
        $encodedCommand = [Convert]::ToBase64String($bytes)
        $replacements = $encodedCommand
    } elseif ($ForCmd) {
        $replacements = @(
            ('|', '^|')
        ) # TODO complete
    } elseif ($ForCLike) {
        $replacements = @(
            ('\\', '\\'),
            ('"', '\"')
        ) # TODO complete/check
    }
    $result = $Str
    if ($replacements -is [array]) {
        # regex replacements
        foreach ($repl in $replacements) {
            $result = $result -replace $repl[0], $repl[1]
        }
    } else {
        # take it literally
        $result = $replacements
    }
    return "$($enclosing[0])${result}$($enclosing[1])"
}



function Set-EnvVariablesAndRun(
    [parameter(ValueFromRemainingArguments)]
    $VarsOrCommandLine
) {
    begin {
        $vars = @{}
        $in_command_line = $false
        $exe = $null
        $command_line = @()
        $VarsOrCommandLine | ForEach-Object {
            $s = "$_"
            if ((!$in_command_line) -and ($s -ilike '*=*')) {
                $keyAndValue = $s.split('=', 2)
                $k = $keyAndValue[0]
                $v = $keyAndValue[1]
                $vars.$k = $v
            } else {
                if (!$in_command_line) {
                    $exe = $s
                    $in_command_line = $true
                } else {
                    $command_line += $s
                }
            }
        }
    }
    process {
        foreach ($v in $vars.GetEnumerator() ) {
            # Write-Warning "setting env var $($v.Name) = $($v.Value)"
            Set-Item -Path "env:$($v.Name)" -Value $v.Value
        }
        if (!$exe) {
            throw "no executable was extrapolated from command line: $($VarsOrCommandLine -join ' ')"
        }

        # Write-Warning "runinn: $exe $($command_line -join ' ')"

        & $exe @command_line
    }
    end {
        foreach ($v in $vars.GetEnumerator() ) {
            $n = $v.Name
            # Write-Warning "removing env var $n"
            Remove-Item -Path "env:$n"
        }
    }
}
Set-Alias -Option AllScope -Scope 'Global' -Force -Name 'env' -Value Set-EnvVariablesAndRun


function Select-ProcessInfo {
    # TODO function not tested
    [CmdletBinding(DefaultParameterSetName = '__AllParameterSets')]
    param(
        [parameter(ValueFromPipeline)][System.Diagnostics.Process[]] $Process,
        [switch] $ShowArgs,
        [switch] $ShowPath,
        [switch] $HideCommandLine,
        [switch] $ForceLoadCommandLine,
        [alias('refresh')][parameter(HelpMessage = 'this is useful if process shows name "Idle"')][switch] $RefreshProcessName
    )
    process {
        # TODO this Process shit may be solution for being forced to use
        #       cmdlet -arrayparameters $x instead of $x|cmdlet
        $props = @('Id', 'Name')
        if ($ShowArgs) { $props += @{label = 'Args'; expression = { $_.StartInfo.Arguments } } }
        if ($ShowPath) { $props += 'Path' }
        if (!$HideCommandLine) { $props += 'CommandLine' }
        $result = $Process | Select-Object -Property $props

        $hasToLookupCommandLine = (!$HideCommandLine) -and ($Process.where({ !$_.CommandLine }))
        if ($RefreshProcessName -or $hasToLookupCommandLine) {
            if ($RefreshProcessName) { $query = $Process }
            else { $query = $Process.where({ !$_.CommandLine }) }
            $cimFilter = $query.Id.ForEach({ "ProcessId=$_" }) -join ' OR '
            $cimPs = @(Get-CimInstance Win32_Process -Filter $cimFilter)
            foreach ($cimP in $cimPs) {
                $rP = $result.where({ $_.Id -eq $cimP.ProcessId })[0]
                if ($RefreshProcessName) { $rP.Name = $cimP.Name }
                if ($hasToLookupCommandLine) { $rP.CommandLine = $cimP.CommandLine }
            }
        }
        return $result
    }
}


function Wait-ProcessInteractive([array] $Process) {
    # TODO add timeout param to Get-Choice and to this function and use it: https://stackoverflow.com/a/43733778
    :loop while ($running = $Process.Where{ !$_.HasExited }) {
        Write-Output "$($running.Length) process(es) still running"
        # TODO $running | Select-ProcessInfo
        $running | Select-Object id, processname, @{label = 'Args'; expression = { $_.StartInfo.Arguments } }, path | Format-Table
        $choice = Get-Choice `
            -prompt 'Make a choice:' `
            -defaultChoice 0 `
            -choices @('&Wait some more', 'Keep them &running but carry on', '&Stop them all and carry on', '&Kill (force stop) them all and carry on')
        switch ($choice) {
            0 { continue loop }
            1 { break loop }
            2 { $running | Stop-Process ; break loop }
            3 { $running | Stop-Process -Force ; break loop }
        }
    }
    return ($running = $Process.Where{ !$_.HasExited })
}


Export-ModuleMember -Function *-* -Alias *