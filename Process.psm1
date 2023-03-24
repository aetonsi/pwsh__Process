function Get-CommandLine ([parameter(ValueFromPipeline)][int] $processId = $PID) {
    $cl = ( Get-Process -Id $processId ).CommandLine
    if ($null -eq $cl) {
        $cl = (Get-CimInstance Win32_Process -Filter "ProcessId=$processId").CommandLine
    }
    return $cl
}

function Wait-ProcessInteractive([array] $Process) {
    :loop while ($running = $Process | Where-Object { !$_.HasExited }) {
        if ($running.Length -gt 0) {
            Write-Output "$($running.Length) process(es) still running"
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
    }
    return ($running = $Process | Where-Object { !$_.HasExited })
}


Export-ModuleMember -Function *-*