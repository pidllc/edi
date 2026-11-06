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
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$InFile,
        [Parameter(Mandatory)][string]$OutFile
    )

    try {
        $plaintext = [System.IO.File]::ReadAllBytes($InFile)

        $aesKey = New-Object byte[] 32
        $nonce  = New-Object byte[] 12
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($aesKey)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($nonce)

        $ciphertext = New-Object byte[] $plaintext.Length
        $tag        = New-Object byte[] 16
        $aesgcm     = New-Object System.Security.Cryptography.AesGcm($aesKey, 16)
        $aesgcm.Encrypt($nonce, $plaintext, $ciphertext, $tag)

        $keyPayload = New-Object byte[] 44
        [Array]::Copy($aesKey, 0, $keyPayload, 0, 32)
        [Array]::Copy($nonce,  0, $keyPayload, 32, 12)

        $rsa = Get-RsaPublicKey $Key
        $encryptedKeyPayload = $rsa.Encrypt(
            $keyPayload,
            [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256
        )

        $combined = New-Object byte[] ($ciphertext.Length + 16)
        [Array]::Copy($ciphertext, 0, $combined, 0, $ciphertext.Length)
        [Array]::Copy($tag, 0, $combined, $ciphertext.Length, 16)

        [System.IO.File]::WriteAllBytes($OutFile, $combined)
        [System.IO.File]::WriteAllBytes("$OutFile.key", $encryptedKeyPayload)

        Write-Host "🔒 Encryption successful!"
        Write-Host " -> Encrypted Data: $OutFile"
        Write-Host " -> Encrypted Key Package: $OutFile.key"
    }
    catch {
        Write-Error "❌ Encryption failed: $_"
        exit 1
    }
}

function Unprotect-File {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$InFile,
        [Parameter(Mandatory)][string]$EncKey,
        [Parameter(Mandatory)][string]$OutFile
    )

    try {
        $combined = [System.IO.File]::ReadAllBytes($InFile)
        $encryptedKeyPayload = [System.IO.File]::ReadAllBytes($EncKey)

        $rsa = Get-RsaPrivateKey $Key
        $keyPayload = $rsa.Decrypt(
            $encryptedKeyPayload,
            [System.Security.Cryptography.RSAEncryptionPadding]::OaepSHA256
        )

        $aesKey = New-Object byte[] 32
        $nonce  = New-Object byte[] 12
        [Array]::Copy($keyPayload, 0, $aesKey, 0, 32)
        [Array]::Copy($keyPayload, 32, $nonce, 0, 12)

        $ciphertext = New-Object byte[] ($combined.Length - 16)
        $tag        = New-Object byte[] 16
        $plaintext  = New-Object byte[] $ciphertext.Length

        [Array]::Copy($combined, 0, $ciphertext, 0, $ciphertext.Length)
        [Array]::Copy($combined, $ciphertext.Length, $tag, 0, 16)

        $aesgcm = New-Object System.Security.Cryptography.AesGcm($aesKey, 16)
        $aesgcm.Decrypt($nonce, $ciphertext, $tag, $plaintext)

        [System.IO.File]::WriteAllBytes($OutFile, $plaintext)

        Write-Host "🔓 Decryption successful!"
        Write-Host " -> Original file restored to: $OutFile"
        Set-EnvVars -envFilePath $OutFile
    }
    catch {
        Write-Error "❌ Decryption failed: $_"
        exit 1
    }
}

function Set-EnvVars {
    param(
        [Parameter(Mandatory=$true)]
        [string]$envFilePath
    )
    Get-Content $envFilePath | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object {
        $name, $value = $_ -split '=', 2
        # Remove surrounding single or double quotes from the value
        $value = $value.Trim() -replace '^["'']|["'']$'
        
        [System.Environment]::SetEnvironmentVariable($name.Trim(), $value, 'Process')
    }
    Remove-Item -Path $envFilePath -Force
    Write-Host "Environment variables set from $envFilePath and file deleted."
}

Export-ModuleMember -Function Protect-File, Unprotect-File, Set-EnvVars