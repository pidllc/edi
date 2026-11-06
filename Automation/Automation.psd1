@{
    RootModule        = 'Automation.psm1'
    ModuleVersion     = '1.0.0'
    Author            = 'Tarun Munjal'
    Description       = 'Supporting functions for automation tasks, including email sending and file attachment handling.'
    FunctionsToExport = @('Copy-MoveFiles', 'Send-EmailMessage', 'Get-TimeFrame', 'Add-OutExtension', 'Add-attachments', 'Get-EmailSignature', 'Get-SuccessBody', 'Get-ErrorBody', 'Confirm-Login', 'Test-Login')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}   