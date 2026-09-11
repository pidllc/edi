# drop_restore_db.ps1 - Drop, restore, and deploy monitoring to databases
# Usage: .\drop_restore_db.ps1
param (
    [string]$Server = "192.168.168.106,2436",
    [string[]]$Databases,
    [string]$BackupFile = "F:\SQLBACKUP\82026.bak",
    [string]$MonitoringDir = "$PSScriptRoot\sql-monitoring"
)



#$Server = "192.168.168.106,2436"
#$Databases = @("flask", "wfashion")
#$BackupFile = "F:\SQLBACKUP\82026.bak"
#$RepoRoot = & git rev-parse --show-toplevel 2>&1
#if ($LASTEXITCODE -ne 0) {
#    Write-Host "Error: Not a git repository. Please run this script from within a git repository." -ForegroundColor Red
#    exit 1
#}
#$MonitoringDir = "$RepoRoot/sql-monitoring"  # Update this path

# Load credentials from saved file
$credFile = "$env:USERPROFILE\workspace\saved_pass"
$DB_Creds = get-content "$env:USERPROFILE\workspace\saved_pass" 
$DEV_DB_SA_USER =  ($DB_Creds -split '\r\n' | select -first 1).split("=") | select -last 1 | ForEach-Object { $_.Trim() }
$DEV_DB_SA_PASS = ($DB_Creds -split '\r\n' | select -last 1).split("=") | select -last 1 | ForEach-Object { $_.Trim() }
if (Test-Path $credFile) {
    $Username = $DEV_DB_SA_USER
    $Password = $DEV_DB_SA_PASS
} else {
    $Username = "readwrite_user"
    $Password = "VeryStrongPassword123!"
}
function restore-databases-with-monitoring {
    [cmdletbinding()]
param(
    [Parameter()]
    [string[]]$databases,
    [string]$BackupFile = "F:\SQLBACKUP\82026.bak",
    [string]$MonitoringDir = "$PSScriptRoot\sql-monitoring"
)

    foreach ($db in $Databases) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Processing: $db" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        # Step 1: Drop and restore
        Write-Host "Step 1: Dropping and restoring $db..." -ForegroundColor Yellow
        sqlcmd -S $Server -d "master" -U $Username -P $Password -C `
            -i "$PSScriptRoot\droprestoredb.sql" `
            -v DBNAME=$db BACKUPFILE=$BackupFile

        # Step 2: Deploy monitoring schema
        Write-Host "Step 2: Deploying monitoring schema..." -ForegroundColor Yellow
        sqlcmd -S $Server -d $db -U $Username -P $Password -C `
            -i "$MonitoringDir\13_deploy_full_monitoring.sql" -y 0

        # Step 3: Deploy DML triggers (use correct file per database)
        Write-Host "Step 3: Deploying DML triggers..." -ForegroundColor Yellow
        if ($db -eq "wfashion") {
            $triggerFile = "15_wfashion_dml_triggers.sql"
        } else {
            $triggerFile = "18_flask_dml_triggers.sql"
        }
        sqlcmd -S $Server -d $db -U $Username -P $Password -C `
            -i "$MonitoringDir\$triggerFile" -y 0

        # Step 4: Deploy DDL trigger autocover
        Write-Host "Step 4: Deploying DDL trigger autocover..." -ForegroundColor Yellow
        sqlcmd -S $Server -d $db -U $Username -P $Password -C `
            -i "$MonitoringDir\16_ddl_trigger_autocover.sql" -y 0

        # Step 5: Capture baseline snapshot
        Write-Host "Step 5: Capturing baseline snapshot..." -ForegroundColor Yellow
        sqlcmd -S $Server -d $db -U $Username -P $Password -C `
            -Q "EXEC mon.sp_capture_snapshot"

        # Step 6: Verify monitoring
        Write-Host "Step 6: Verifying monitoring..." -ForegroundColor Yellow
        sqlcmd -S $Server -d $db -U $Username -P $Password -C -Q "
            SELECT 
                'audit_triggers' AS item, CAST(COUNT(*) AS VARCHAR) AS val FROM sys.triggers WHERE name LIKE 'trg_audit%'
            UNION ALL SELECT 'Query Store', CASE WHEN is_query_store_on = 1 THEN 'ON' ELSE 'OFF' END FROM sys.databases WHERE name = '$db'
            UNION ALL SELECT 'trg_mon_ddl_audit', CASE WHEN EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_mon_ddl_audit') THEN 'OK' ELSE 'MISSING' END
        "

        Write-Host "Completed: $db" -ForegroundColor Green
        Write-Host ""
    }
}

function restore-databases {
    [cmdletbinding()]
param(
    [Parameter()]
    [string[]]$databases,
    [string]$BackupFile = "F:\SQLBACKUP\82026.bak"
    
)

    foreach ($db in $Databases) {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Processing: $db" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan

        # Step 1: Drop and restore
        Write-Host "Step 1: Dropping and restoring $db..." -ForegroundColor Yellow
        sqlcmd -S $Server -d "master" -U $Username -P $Password -C `
            -i "$PSScriptRoot\droprestoredb.sql" `
            -v DBNAME=$db BACKUPFILE=$BackupFile
    }
}
restore-databases-with-monitoring -databases $Databases

Write-Host "All databases processed successfully!" -ForegroundColor Green
