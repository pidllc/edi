#Import-Module $PSScriptRoot\automation.psm1 -DisableNameChecking -force
#    $PDF_Files = Get-ChildItem -Path "C:\Users\Tarun\col\20261106_073001\Output\pdfs" -Filter "*.pdf" | select-object -ExpandProperty FullName
#Write-host "PDF Files: $($PDF_Files.Count) $PDF_Files"
#send-emailmessage -subject "test attachment" -files $PDF_Files `
#    -to @("tarun@pidllc.com")


Import-Module $PSScriptRoot\Automation -force
Import-Module $PSScriptRoot\SecureFile -force

#Protect-file -Key C:\Users\Tarun\workspace\personal\erp\encrypted-files\public_encrypting.pem -InFile .\emailSecret.env -OutFile .\email-token.enc
#Unprotect-File -Key C:\Users\Tarun\.ssh\private_encrypting.pem -InFile .\email-token.enc -EncKey .\email-token.enc.key  -OutFile emailSecret.env
#
#Send-EmailMessage -subject "This is a test email" `
#    -files "C:\users\Tarun\col\20261106_073001\Output\pdfs\register_20261106_073005_1008907-1009155.pdf" `
#    -to "tarun@pidllc.com", "tarunmunjal@msn.com" -body Get-SuccessBody `
#    -tenantId $ENV:TENANT_ID `
#    -clientSecret $ENV:CLIENT_SECRET `
#    -clientId $ENV:CLIENT_ID
