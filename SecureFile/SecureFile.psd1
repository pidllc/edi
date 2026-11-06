@{
    RootModule        = 'SecureFile.psm1'
    ModuleVersion     = '1.0.0'
    Author            = 'Tarun Munjal'
    Description       = 'Hybrid RSA-OAEP + AES-256-GCM file encryption/decryption'
    FunctionsToExport = @('Protect-File', 'Unprotect-File', 'Set-EnvVars')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}   