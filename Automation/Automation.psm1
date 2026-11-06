function Copy-MoveFiles {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Source,
        [Parameter(Mandatory=$true)]
        [string]$CopyDestination,
        [Parameter(Mandatory=$true)]
        [string]$MoveDestination
    )
        if (-not (Test-Path $MoveDestination)) {
        New-Item -ItemType Directory -Path $MoveDestination -Force | Out-Null
        Write-Host "Created: $MoveDestination"
    }
    if (-not (Test-Path $CopyDestination)) {
        New-Item -ItemType Directory -Path $CopyDestination -Force | Out-Null
        Write-Host "Created: $CopyDestination"
    }
    $files = Get-ChildItem -Path $Source -File
    if (-not $files) {
        Write-Host "No files found matching: $Source"
        return
    }

    Write-Host "Found $($files.Count) file(s). Copying to $CopyDestination ..."

    ## Copy these files as is to desktop for processing using automation script
    $files | Copy-Item -Destination $CopyDestination -Force -ErrorAction Stop
    ## Move these files to the destination folder
    $files | Move-Item -Destination "$MoveDestination" -Force -ErrorAction Stop
    Write-Host "Found $($files.Count) file(s). Moved to $MoveDestination ..."
    Write-Host "Done."
}

Function Get-AttachmentType () {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FilePath
    )
    $extension = [System.IO.Path]::GetExtension($FilePath).ToLower()
    switch ($extension) {
        ".pdf" { return "application/pdf" }
        ".txt" { return "text/plain" }
        ".csv" { return "text/csv" }
        ".docx" { return "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }
        ".xlsx" { return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" }
        default { return "application/octet-stream" }
    }
}

function Add-attachments {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$files
    )
    Write-Host "Adding attachments for files: $($files -join ', ')"
    $attachments = @()
    foreach ($file in $files) {
        $bytes = [System.IO.File]::ReadAllBytes($file)
        $attchmentType = Get-AttachmentType -FilePath $file
        Write-Host "Attachment: $file, Type: $attchmentType"
        $attachment = @{
            "@odata.type"  = "#microsoft.graph.fileAttachment"
            name           = [System.IO.Path]::GetFileName($file)
            contentType    = $attchmentType
            contentBytes   = [System.Convert]::ToBase64String($bytes)
        }
        $attachments += $attachment
    }
    return $attachments
}

function Get-EmailSignature() {
    return @"
        <br/><hr/>
        <p style="font-size:12px; color:#666;">
        <strong>Tarun Munjal</strong><br/>
        PID LLC | tarun@pidllc.com | +1-917-410-0872<br/>
        </p>
"@
}

function Get-SuccessBody () {
    $signature = Get-EmailSignature
    return @"
        <p>Karen,</p>
        <p>Pick tickets and Detail attached for SAMS DSV $Date_Today $check_batch_time</p>
        $signature
"@
}

function Get-ErrorBody () {
    $signature = Get-EmailSignature
    return @"
        <p>There were errors while processing SAMS DSV $Date_Today $check_batch_time</p>
        $signature
"@
}

function Send-EmailMessage {
    param(
        [Parameter(Mandatory=$false)]
        [string]$subject,
        [Parameter(Mandatory=$false)]
        [string[]]$files,
        [Parameter(Mandatory=$false)]
        [string[]]$to,
        [Parameter(Mandatory=$false)]
        [string[]]$cc,
        [Parameter(Mandatory=$false)]
        [string]$body,
        [Parameter(Mandatory=$true)]
        [string]$tenantId,
        [Parameter(Mandatory=$true)]
        [string]$clientSecret,
        [Parameter(Mandatory=$true)]
        [string]$clientId
    )


    $recipients  = $to  | ForEach-Object { @{ emailAddress = @{ address = $_ } } }
   
    $ccrecipients = $cc | ForEach-Object { @{ emailAddress = @{ address = $_ } } }
    $senderUpn = "tarun@pidllc.com"
    if ($files) {
        $attachments = Add-attachments -files $files
    }
    $tokenBody = @{
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }

    $tokenResponse = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token" `
        -Method POST `
        -ContentType "application/x-www-form-urlencoded" `
        -Body $tokenBody
    $token = $tokenResponse.access_token
    $headers = @{
        "Authorization" = "Bearer $token"
        "Content-Type"  = "application/json"
    }
    $message = @{}
    $message.add("Subject", $subject)
    $message.add("body", @{ contentType = "HTML"; content = $body })
    $message.add("toRecipients", @($recipients))
    if ($cc) {
        $message.add("ccRecipients", @( $ccrecipients))
    }
    if ($attachments) {
        $message.add("attachments", @($attachments))
    }

    ## works
    ##$mailPayload = @{
    ##    message = @{
    ##        subject = $subject
    ##        body =  @{ contentType = "HTML"; content = $body }
    ##        toRecipients = @($recipients)
    ##    }
    ##    saveToSentItems = "true"
    ##} | ConvertTo-Json -Depth 5
    $mailPayload = @{
        message = $message
        saveToSentItems = "true"
    } | ConvertTo-Json -Depth 5
    $mailPayload | Out-File -FilePath "C:\Users\Tarun\workspace\personal\edi\email_payload_multi.json" -Encoding utf8
    Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/v1.0/users/$senderUpn/sendMail" `
    -Method POST `
    -Headers $headers `
    -Body $mailPayload
}

function Get-Timeframe {
    $now = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId(
        (Get-Date), "Eastern Standard Time"
    )

    $sevenAM  = [TimeSpan]::FromHours(7)
    $eightAM  = [TimeSpan]::FromHours(8)
    $elevenAM  = [TimeSpan]::FromHours(11)
    $onePM  = [TimeSpan]::FromHours(13) 
    if ($now.TimeOfDay -ge $sevenAM -and $now.TimeOfDay -lt $eightAM) {
        Write-Host "Between 7 and 8 AM EST."
        return "1st batch"
    }
    elseif ($now.TimeOfDay -ge $elevenAM -and $now.TimeOfDay -lt $onePM) {
        Write-Host "Not between 7 and 8 AM EST."
        return "2nd batch"
    }
    else {
        Write-Host "Not in any defined timeframe."
        return "batch outside defined timeframe"
    }
}

function Test-Login{
    param(
        [Parameter(Mandatory=$false)]
        [string]$log_user,
        [Parameter(Mandatory=$false)]
        [string]$log_pass
)
    $HEADERS = @{
        "Content-Type" = "application/json"
    }
    $LOGIN_PAYLOAD = @{
        userid = $log_user
        password = $log_pass
    } | ConvertTo-Json

    $result =Invoke-RestMethod -Uri "https://erp-prod.pidllc.com/api/auth/login" `
        -Method POST  -Body $LOGIN_PAYLOAD `
        -Headers $headers 
    return $result
}

function Confirm-Login {
        param(
        [Parameter(Mandatory=$false)]
        [string]$log_user,
        [Parameter(Mandatory=$false)]
        [string]$log_pass,
        [Parameter(Mandatory=$false)]
        [string]$server_name
    )
    $counter = 0
    while ($counter -lt 2) {
        $Response = Test-Login -userid $log_user -password $log_pass
        if ($Response.message -match "success") {
            Write-Host "Login successful"
        }
        else {
            Write-Host "Login failed"
            if ($counter -lt 2) {
                Write-Host "Stopping and restarting the docker container on $server_name. Attempt $($counter + 1) of 2."
                if ($server_name -eq "ubuntu2") {
                    ssh $server_name "cd /home/tarun/erp && ./temp/stop-docker.sh && ./run-docker.sh prod"
                }
                else {
                    ssh $server_name "cd /home/tarun/erp && ./temp/stop-docker.sh && ./run-docker.sh non-prod"
                }
            }
        }
        $counter = $counter + 1
    }
}

function Add-OutExtension {
    param(
        [Parameter(Mandatory=$true)]
        [string]$FolderPath
    )
    try {
        if (-not (Test-Path $FolderPath)) {
            Write-Error "Folder path does not exist: $FolderPath"
            return
        }
        $folders = Get-ChildItem -Path $FolderPath -Directory | Where-Object {$_.Name -in @("997", "855")}
        foreach ($folder in $folders) {
            if ($folder.Name -notin @("997", "855")) {
                Write-Host "Skipping folder: $($folder.FullName)"
                continue
            }

            $files = Get-ChildItem -Path $folder.FullName -File
            foreach ($file in $files) {
                $newFileName = "$($file.Name).out"
                $newFilePath = Join-Path -Path $file.DirectoryName -ChildPath $newFileName
                Rename-Item -Path $file.FullName -NewName $newFileName -Force
                Write-Host "Renamed: $($file.FullName) -> $newFilePath"
            }
        }
        
    }
    catch {
        Write-Error "Failed to rename file: $_"
    }
}   

Export-ModuleMember -Function Copy-MoveFiles, Send-EmailMessage, Get-TimeFrame, Add-OutExtension, Get-successBody, Get-ErrorBody, Confirm-Login, Test-Login