param(
    [Parameter(Mandatory=$false)]
    [string]$Env="TEST"
)
try {
    $Date_Now = Get-Date -Format "yyyyMMdd_HHmmss"
    $Date_Today = Get-Date -Format "yyyyMMdd"
    $dayOfWeek = (Get-Date).DayOfWeek
    $transcript = "C:\Users\tarun\col\${Date_Now}\automation_transcript.log"
    Start-Transcript -Path $transcript -Append    
    Import-Module $PSScriptRoot\Automation -force
    Import-Module $PSScriptRoot\SecureFile -force
    Unprotect-File -Key C:\Users\Tarun\.ssh\private_encrypting.pem -InFile .\email-token.enc -EncKey .\email-token.enc.key  -OutFile emailSecret.env

    # Import once per session
    #Import-Module ./SecureFile

    ## Script Related Environment Variables
    #-----------------------------------------------------------------------------#
    if ($Env -eq "PROD") {
        $ENV:EDI_SOURCE_DIR="C:\Users\tarun\col\$Date_Now"
        $ENV:EDI_STAGING_DIR="C:\Users\tarun\col\$Date_Now\Staging"
        $ENV:EDI_PROCESSED_DIR="C:\Users\tarun\col\$Date_Now\Processed"
        $ENV:EDI_OUTPUT_DIR="C:\Users\tarun\col\$Date_Now\Output"
        $ENV:EDI_API_URL=$ENV:PROD_API_URL
        $ENV:EDI_AUTOMATION_PASS=$ENV:PROD_AUTOMATION_PASS
        $ENV:SERVER_NAME=$ENV:PROD_SERVER_NAME
        # Main quila\isoft\inbox\walmart folder as source.
        $Source = "Z:\ISOFT\inbox\walmart\*andrew*850*.in"
        # Copy the files so we can work of off the copies and preserve the originals.
        # Move the original files to the destination so they don't get reprocessed.
        $MoveDestination = "Z:\ISOFT\inbox\walmart\$Date_Today\$Date_Now"
        $CopyDestination = "C:\Users\tarun\col\$Date_Now"
    }
    else{
        ### TEST
        #$ENV:EDI_SOURCE_DIR="C:\Users\tarun\col\$Date_Now"
        #$ENV:EDI_STAGING_DIR="C:\Users\tarun\col\$Date_Now\Staging"
        #$ENV:EDI_PROCESSED_DIR="C:\Users\tarun\col\$Date_Now\Processed"
        #$ENV:EDI_OUTPUT_DIR="C:\Users\tarun\col\$Date_Now\Output"
        $ENV:EDI_SOURCE_DIR="C:\Users\Tarun\workspace\personal\Edifiles\20261105\Copy"
        $ENV:EDI_STAGING_DIR="C:\Users\Tarun\workspace\personal\Edifiles\20261105Staging"
        $ENV:EDI_PROCESSED_DIR="C:\Users\Tarun\workspace\personal\Edifiles\20261105Processed"
        $ENV:EDI_OUTPUT_DIR="C:\Users\Tarun\workspace\personal\Edifiles\20261105Output"
        $ENV:EDI_API_URL=$ENV:NON_PROD_API_URL
        $ENV:EDI_AUTOMATION_PASS=$ENV:NON_PROD_AUTOMATION_PASS
        $ENV:SERVER_NAME=$ENV:NON_PROD_SERVER_NAME
        ### TEST
        $Source = "C:\Users\Tarun\workspace\personal\Edifiles\20261105\*.in"
        ### Copy the files so we can work of off the copies and preserve the originals.
        $CopyDestination = "C:\Users\Tarun\workspace\personal\Edifiles\20261105\Copy"
        ### Move the original files to the destination so they don't get reprocessed.
        $MoveDestination = "C:\Users\Tarun\workspace\personal\Edifiles\20261105\Move"
    }    
    $ENV:EDI_AUTOMATION_USER="tarun"
    $ENV:EDI_CUSTOMER="DSVSAMSC"
    $ENV:EDI_FILE_PATTERN="*.in"
    $ENV:EDI_DSV_SENDER="925485USSM"
    $ENV:EDI_RULE_ID=1
    $ENV:EDI_MAX_QTY_PER_CARTON=25
    $ENV:EDI_WEIGHT_PER_PIECE=1
    $ENV:EDI_VERIFY_SSL=$false
    $ENV:EDI_AUTO_PICK= $true
    $ENV:EDI_PRINT_PDF= $true
    $ENV:EDI_REGISTER_REPORT= $true
    $ENV:EDI_GENERATE_997= $true
    $ENV:EDI_GENERATE_855= $true
    $ENV:PYTHONWARNINGS="ignore:Unverified HTTPS request"
    #-----------------------------------------------------------------------------#
    #confirm-login -log_user $ENV:EDI_AUTOMATION_USER -log_pass `
    #    $ENV:EDI_AUTOMATION_PASS -server $ENV:SERVER_NAME
    $check_batch_time = get-timeframe
    if ($dayOfWeek -eq "Sunday" -or $dayOfWeek -eq "Saturday") {
        Write-host "Not processing files on weekend."
        exit 0
    }
    if ($dayOfWeek -eq "Monday" -and $check_batch_time -eq "1st batch") {
        $saturdayDate=((Get-Date).AddDays(-2)).ToString("yyyy-MM-dd")
        $TodayDate=(Get-Date).ToString("yyyy-MM-dd")
        Write-Host "Setting dates for 1st batch on Monday to make sure pick tickets are generated for Saturday and Sunday as well."
        $ENV:EDI_SHIP_DATE_FROM = $saturdayDate
        $ENV:EDI_SHIP_DATE_TO = $TodayDate
    }
    Copy-MoveFiles -Source $Source -CopyDestination $CopyDestination -MoveDestination $MoveDestination 
    # Activate the Python virtual environment and run the automation script.
    C:\Users\Tarun\workspace\venv\Scripts\Activate.ps1
    python C:\Users\Tarun\workspace\personal\erp\automation\edi_automation.py
    ## Pause for 10 seconds to make sure all files are generated before sending email.
    ## There seems to be a delay in the file system and the files are not available immediately after the script runs.
    Start-sleep -Seconds 10

    $PDF_Files = Get-ChildItem -Path "C:\Users\Tarun\col\$Date_Now\Output\pdfs" -Filter "*.pdf" | select-object -ExpandProperty FullName

    if ($PDF_Files.Count -gt 0) {
        Send-EmailMessage -subject "SAMSDSV $Date_Today $check_batch_time" `
            -files $runReport.FullName `
            -body Get-SuccessBody `
            -tenantId $ENV:TENANT_ID `
            -clientSecret $ENV:CLIENT_SECRET `
            -clientId $ENV:CLIENT_ID `
            -to "tarun@pidllc.com", "anand@pidllc.com" 
        }
    else {
        Write-Host "No PDF files found to send."
    }

    $runReport = Get-ChildItem -Path "C:\Users\Tarun\col\$Date_Now\Output" -Filter "automation_report*.txt" | select-object -ExpandProperty FullName
    if ($runReport.Count -gt 0) {
        Write-Host "Found automation report file(s)."
        $checkErrors = Get-Content -Path $runReport.FullName
        if ($checkErrors -match "ERROR") {
            Write-Host "Errors found in automation report."
            Send-EmailMessage -subject "ERROR: SAMS DSV $Date_Today $check_batch_time" `
                -files $runReport.FullName `
                -body Get-ErrorBody `
                -tenantId $ENV:TENANT_ID `
                -clientSecret $ENV:CLIENT_SECRET `
                -clientId $ENV:CLIENT_ID `
                -to "tarun@pidllc.com", "anand@pidllc.com" 
        }
    }else{
        Write-Host "No automation report file found."
    }
    #>
}
catch {
        Send-EmailMessage -subject "ERROR: SAMS DSV $Date_Today $check_batch_time" `
            -files $transcript `
            -body "<p>Trasncript Attached </p>" + Get-ErrorBody `
            -tenantId $ENV:TENANT_ID `
            -clientSecret $ENV:CLIENT_SECRET `
            -clientId $ENV:CLIENT_ID `
            -to "tarun@pidllc.com"
}
finally {
    Stop-Transcript
}