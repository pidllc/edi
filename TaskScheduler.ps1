Unregister-ScheduledTask -TaskName "DSVBatch1" -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName "DSVBatch2" -Confirm:$false -ErrorAction SilentlyContinue
$MorningTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 7:30 AM
$AfterNoonTrigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 11:30 AM
Register-ScheduledTask -TaskName "DSVBatch1" `
    -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass "C:\Users\Tarun\workspace\personal\edi\automation.ps1" -Env "PROD"') `
    -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 7:30AM)

Register-ScheduledTask -TaskName "DSVBatch2" `
    -Action (New-ScheduledTaskAction -Execute "powershell.exe" -Argument '-NoProfile -ExecutionPolicy Bypass "C:\Users\Tarun\workspace\personal\edi\automation.ps1" -Env "PROD"') `
    -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday,Tuesday,Wednesday,Thursday,Friday -At 11:30AM)

