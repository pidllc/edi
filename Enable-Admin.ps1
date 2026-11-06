# ==============================================================================
# CONFIGURATION - CUSTOMIZE THESE VALUES
# ==============================================================================
$AdminUsername = "PidAdmin"
$AdminPassword = "Pid@dmin!250" # Must meet your systems' complexity requirements
$PublicKey     = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCwPVgUf9lvlhICu5Fyzy5dpSxGvE+Igb9edNU6mpuVJuuygzpueQpUvgMkkNRF2GEFlbhOkvgDaJPeZWojYgVSEKgzBLb+DUZEkiBVUn8IKGAE981q6byw53ZVCWLRu32QcodLTUjfY/z4Aaae5igxJGdTT3gYs/8nzZ7hsU+siPk9nTRTBeG4Q7kC1gSIIeLzYaPJTLEgSLXkbkOTbuwRD2wrV+iR6uI5GB/x/TN57LU0+bnntHiPW56CCeW4jZHMpLDOP8iozGok2RPVZiZXzMwvH+q2rL+R37leLqr/2PSLjgFwodjtbA58Bjr2KY6CwxAT3x7nKEDF9JHKS9kRTPLduXmlc5o1eTN97k1cU2e6UXDIzDKDP2xGxtxlSVJMj4LWGZh0zO5j3wcm1hmpoumb+L846Iusk8kJ3pyL96Edtg47Hlv+SZUFLD/Qfr8mxeK2ud+b1/xuT5w4Z11yI2OvSNEvmVtmyInNunHIvTHLTmxx2KNujgMGdhUmNFE="
# ==============================================================================

# 1. Create Local User and Add to Administrators Group
Write-Host "Checking for local user: $AdminUsername..." -ForegroundColor Cyan
$UserExists = Get-LocalUser -Name $AdminUsername -ErrorAction SilentlyContinue

if (-not $UserExists) {
    Write-Host "Creating local user account..." -ForegroundColor Cyan
    $SecurePassword = ConvertTo-SecureString $AdminPassword -AsPlainText -Force
    New-LocalUser -Name $AdminUsername -Password $SecurePassword -Description "Admin account created via Action1 for SSH access" -PasswordNeverExpires $true | Out-Null
    
    Write-Host "Adding $AdminUsername to the local Administrators group..." -ForegroundColor Cyan
    Add-LocalGroupMember -Group "Administrators" -Member $AdminUsername
    Write-Host "User created and elevated successfully." -ForegroundColor Green
} else {
    Write-Host "User $AdminUsername already exists. Skipping creation." -ForegroundColor Yellow
}

# 2. Install OpenSSH Server if not already present
$SshServer = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($SshServer.State -ne 'Installed') {
    Write-Host "Installing OpenSSH Server..." -ForegroundColor Cyan
    Add-WindowsCapability -Online -Name $SshServer.Name | Out-Null
} else {
    Write-Host "OpenSSH Server is already installed." -ForegroundColor Green
}

# 3. Start SSH Service and set to Automatic
Write-Host "Configuring OpenSSH Service..." -ForegroundColor Cyan
Start-Service sshd -ErrorAction SilentlyContinue
Set-Service -Name sshd -StartupType 'Automatic'

# 4. Handle Global Administrators SSH Key File
$ProgramDataDir = "C:\ProgramData\ssh"
$AdminKeysPath  = "$ProgramDataDir\administrators_authorized_keys"

if (-not (Test-Path $ProgramDataDir)) {
    New-Item -ItemType Directory -Path $ProgramDataDir -Force | Out-Null
}

if (Test-Path $AdminKeysPath) {
    $ExistingKeys = Get-Content $AdminKeysPath
    if ($ExistingKeys -notcontains $PublicKey) {
        Add-Content -Path $AdminKeysPath -Value $PublicKey
        Write-Host "Public key appended to system administrators file." -ForegroundColor Green
    } else {
        Write-Host "Public key already exists in system administrators file." -ForegroundColor Yellow
    }
} else {
    Set-Content -Path $AdminKeysPath -Value $PublicKey
    Write-Host "Created administrators_authorized_keys and added public key." -ForegroundColor Green
}

# 5. Enforce Strict ACL Permissions Required by OpenSSH
Write-Host "Applying strict permissions to administrators file..." -ForegroundColor Cyan
$Acl = Get-Acl $AdminKeysPath
$Acl.SetAccessRuleProtection($true, $false) # Disables inheritance and clears inherited rules

$AdministratorsSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
$SystemSid         = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)

$ArpAdmin  = New-Object System.Security.AccessControl.FileSystemAccessRule($AdministratorsSid, "FullControl", "Allow")
$ArpSystem = New-Object System.Security.AccessControl.FileSystemAccessRule($SystemSid, "FullControl", "Allow")

$Acl.AddAccessRule($ArpAdmin)
$Acl.AddAccessRule($ArpSystem)
Set-Acl $AdminKeysPath $Acl

# 6. Ensure Windows Firewall is Open
Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue | Enable-NetFirewallRule

# 7. Restart service to apply everything cleanly
Restart-Service sshd
Write-Host "Deployment completed successfully!" -ForegroundColor Green
