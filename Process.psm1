function Get-CommandLine ([parameter(ValueFromPipeline)][int] $processId = $PID) {
    $cl = ( Get-Process -Id $processId ).CommandLine
    if ($null -eq $cl) {
        $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$processId").CommandLine
    }
    return $cl
}


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


Export-ModuleMember -Function *-*