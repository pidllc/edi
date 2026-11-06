<#
.SYNOPSIS
    Automated File Encryption/Decryption using Hybrid RSA-OAEP + AES-256-GCM

.EXAMPLE
    .\Secure-File.ps1 encrypt -Key public.pem -Input database.csv -Output secure_backup.enc

.EXAMPLE
    .\Secure-File.ps1 decrypt -Key private.pem -Input secure_backup.enc -EncKey secure_backup.enc.key -Output restored_database.csv
#>
param(
    [Parameter(Position=0, Mandatory)]
    [ValidateSet("encrypt", "decrypt")]
    [string]$Command,

    [Parameter(Mandatory)]
    [string]$Key,

    [Parameter(Mandatory)]
    [string]$infile,

    [Parameter(Mandatory)]
    [string]$Outfile,

    [Parameter(Mandatory=$false)]
    [string]$EncKey
)
function Get-RsaPublicKey {
    param([string]$Path)
    $pem = [System.IO.File]::ReadAllText($Path)
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem($pem)
    return $rsa
}

function Get-RsaPrivateKey {
    param([string]$Path)
    $pem = [System.IO.File]::ReadAllText($Path)
    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportFromPem($pem)
    return $rsa
}   
function Protect-File {
    param([string]$PubKeyPath, [string]$InputPath, [string]$OutputPath)

    try {
        # 1. Read plaintext
        $plaintext = [System.IO.File]::ReadAllBytes($InputPath)

        # 2. Generate random 256-bit AES key and 96-bit nonce
        $aesKey = New-Object byte[] 32
        $nonce  = New-Object byte[] 12
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($aesKey)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)

        # 3. AES-GCM encrypt
        $ciphertext = New-Object byte[] $plaintext.Length
        $tag        = New-Object byte[] 16
        $aesgcm     = New-Object System.Security.Cryptography.AesGcm($aesKey, 16)
        $aesgcm.Encrypt($nonce, $plaintext, $ciphertext, $tag)

        # 4. Pack key + nonce, encrypt with RSA-OAEP (SHA-256)
        $keyPayload = New-Object byte[] 44
        [Array]::Copy($aesKey, 0, $keyPayload, 0, 32)
        [Array]::Copy($nonce,  0, $keyPayload, 32, 12)

        $rsa = Get-RsaPublicKey $PubKeyPath
        $encryptedKeyPayload = $rsa.Encrypt(
            $keyPayload,
            [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256
        )

        # 5. Write outputs
        $combined = New-Object byte[] ($ciphertext.Length + 16)
        [Array]::Copy($ciphertext, 0, $combined, 0, $ciphertext.Length)
        [Array]::Copy($tag, 0, $combined, $ciphertext.Length, 16)

        [System.IO.File]::WriteAllBytes($OutputPath, $combined)
        [System.IO.File]::WriteAllBytes("$OutputPath.key", $encryptedKeyPayload)

        Write-Host "Encryption successful!"
        Write-Host " -> Encrypted Data: $OutputPath"
        Write-Host " -> Encrypted Key Package: $OutputPath.key"
    }
    catch {
        Write-Error "Encryption failed: $_"
        exit 1
    }
}

function Unprotect-File {
    param([string]$PrivKeyPath, [string]$EncDataPath, [string]$EncKeyPath, [string]$OutputPath)

    write-host "starting decryption process..."
    if (-not (Test-Path $EncDataPath)) {
        Write-Error "Encrypted data file not found: $EncDataPath"
        exit 1
    }
    if (-not (Test-Path $EncKeyPath)) {
        Write-Error "Encrypted key file not found: $EncKeyPath"
        exit 1
    }
    if (-not (Test-Path $PrivKeyPath)) {
        Write-Error "Private key file not found: $PrivKeyPath"
        exit 1
    }
    try {
        Write-host "Decrypting $EncDataPath using private key $PrivKeyPath ..."
        # 1. Read encrypted components
        $combined = [System.IO.File]::ReadAllBytes($EncDataPath)
        $encryptedKeyPayload = [System.IO.File]::ReadAllBytes($EncKeyPath)

        Write-Host " -> Encrypted Data Size: $($combined.Length) bytes"
        # 2. Decrypt AES key + nonce with RSA private key
        $rsa = Get-RsaPrivateKey $PrivKeyPath
        $keyPayload = $rsa.Decrypt(
            $encryptedKeyPayload,
            [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256
        )

        # 3. Extract key and nonce
        $aesKey = New-Object byte[] 32
        $nonce  = New-Object byte[] 12
        [Array]::Copy($keyPayload, 0, $aesKey, 0, 32)
        [Array]::Copy($keyPayload, 32, $nonce, 0, 12)

        # 4. AES-GCM decrypt
        $ciphertext = New-Object byte[] ($combined.Length - 16)
        $tag        = New-Object byte[] 16
        $plaintext  = New-Object byte[] $ciphertext.Length

        [Array]::Copy($combined, 0, $ciphertext, 0, $ciphertext.Length)
        [Array]::Copy($combined, $ciphertext.Length, $tag, 0, 16)

        $aesgcm = New-Object System.Security.Cryptography.AesGcm($aesKey, 16)
        $aesgcm.Decrypt($nonce, $ciphertext, $tag, $plaintext)   

        # 5. Write restored file
        [System.IO.File]::WriteAllBytes($OutputPath, $plaintext)

        Write-Host "Decryption successful!"
        Write-Host " -> Original file restored to: $OutputPath"
    }
    catch {
        Write-Error "Decryption failed: $_"
        exit 1
    }
}

# --- Dispatch ---
if ($Command -eq "encrypt") {
    Protect-File -PubKeyPath $Key -InputPath $infile -OutputPath $Outfile
}
else {
    if (-not $EncKey) {
        Write-Error " --EncKey is required for decryption."
        exit 1
    }
    Write-Host "Decrypting $infile using private key $Key and encrypted key $EncKey. Out to $outfile" -ForegroundColor Yellow
    Unprotect-File -PrivKeyPath $Key -EncDataPath $infile -EncKeyPath $EncKey -OutputPath $Outfile
}   