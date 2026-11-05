Import-Module $PSScriptRoot\automation.psm1 -DisableNameChecking
    $PDF_Files = Get-ChildItem -Path "C:\Users\Tarun\col\20261105_113001\Output\pdfs" -Filter "*.pdf" | select-object -ExpandProperty FullName
Write-host "PDF Files: $($PDF_Files.Count) $PDF_Files"
send-emailmessage -subject "test attachment" -files $PDF_Files `
    -to @("tarun@pidllc.com")