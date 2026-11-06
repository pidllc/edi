Unregister-ScheduledTask -TaskName "DSVBatch1" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "DSVBatch2" -Confirm:$false -ErrorAction SilentlyContinue
$MorningTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 7:30AM
$AfterNoonTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 11:30AM
Register-ScheduledTask -TaskName "DSVBatch1" `
    -Action (New-ScheduledTaskAction -Execute "pwsh.exe" -Argument '-NoProfile -ExecutionPolicy Bypass "C:\Users\Tarun\workspace\personal\edi\Process-DSV.ps1" -Env "PROD"') `
    -Trigger ($MorningTrigger)

Register-ScheduledTask -TaskName "DSVBatch2" `
    -Action (New-ScheduledTaskAction -Execute "pwsh.exe" -Argument '-NoProfile -ExecutionPolicy Bypass "C:\Users\Tarun\workspace\personal\edi\Process-DSV.ps1" -Env "PROD"') `
    -Trigger ($AfterNoonTrigger)

