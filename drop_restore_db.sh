#!/usr/bin/env bash
set -euo pipefail

DB_SERVER="flask wfashion"
USERNAME="readwrite_user"
PASSWORD="VeryStrongPassword123!"
source ~/workspace/saved_pass

USERNAME=$DEV_DB_SA_USER
PASSWORD=$DEV_DB_SA_PASS
for db in $DB_SERVER; do
  echo "Deploying monitoring to $db"
    sqlcmd -S "192.168.168.106,2436" -d "master" -U "$USERNAME" -P "$PASSWORD" -C \
    -i /Users/tarun/workspace/personal/edi/droprestoredb.sql \
    -v DBNAME="$db" BACKUPFILE="F:\SQLBACKUP\82026.bak"
    sqlcmd -S "192.168.168.106,2436" -d "$db" -U "$USERNAME" -P "$PASSWORD" -C -i /Users/tarun/workspace/personal/edi/sql-monitoring/13_deploy_full_monitoring.sql -y 0
    sqlcmd -S "192.168.168.106,2436" -d "$db" -U "$USERNAME" -P "$PASSWORD" -C -i /Users/tarun/workspace/personal/edi/sql-monitoring/18_flask_dml_triggers.sql -y 0
    sqlcmd -S "192.168.168.106,2436" -d "$db" -U "$USERNAME" -P "$PASSWORD" -C -i /Users/tarun/workspace/personal/edi/sql-monitoring/16_ddl_trigger_autocover.sql -y 0
    sqlcmd -S "192.168.168.106,2436" -d "$db" -U "$USERNAME" -P "$PASSWORD" -C -Q "EXEC mon.sp_capture_snapshot"
    sqlcmd -S "192.168.168.106,2436" -d "$db" -U "$USERNAME" -P "$PASSWORD" -C -Q "
    SELECT 
        'audit_triggers' AS item, CAST(COUNT(*) AS VARCHAR) AS val FROM sys.triggers WHERE name LIKE 'trg_audit%'
    UNION ALL SELECT 'Query Store', CASE WHEN is_query_store_on = 1 THEN 'ON' ELSE 'OFF' END FROM sys.databases WHERE name = 'flask'
    UNION ALL SELECT 'trg_mon_ddl_audit', CASE WHEN EXISTS (SELECT 1 FROM sys.triggers WHERE name = 'trg_mon_ddl_audit') THEN 'OK' ELSE 'MISSING' END
    "
done
