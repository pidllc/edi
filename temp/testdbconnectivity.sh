#!/usr/bin/env bash
#sqlcmd -S "192.168.168.106,2436" -d "wfashion" -U "readwrite_user" -P 'VeryStrongPassword123!' -C -l 10 -Q "SELECT DB_NAME() as db, @@VERSION as ver; SELECT is_query_store_on, name FROM sys.databases WHERE database_id=DB_ID();" 2>&1 | head -n 80
base_dir=$(git rev-parse --show-toplevel)
sqlcmd -S "192.168.168.106,2436" -d "wfashion" -U "readwrite_user" -P 'VeryStrongPassword123!' -C -I -i ${base_dir}/sql-monitoring/20_capture_report_selects.sql > ${base_dir}/temp/testdbconnectivity.log 2>&1