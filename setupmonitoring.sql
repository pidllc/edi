-- Step 3: Enable Change Data Capture (CDC) if it was enabled previously
EXEC sp_cdc_enable_db 'wf125sR_82026';

-- Step 4: Execute the script to create audit tables and triggers
GO
EXEC ('sqlcmd -S "192.168.168.106,2436" -d "wf125sR_82026" -U "readwrite_user" -P "VeryStrongPassword123!" -i sql-monitoring\08_create_audit_tables.sql');
GO
EXEC ('sqlcmd -S "192.168.168.106,2436" -d "wf125sR_82026" -U "readwrite_user" -P "VeryStrongPassword123!" -i sql-monitoring\09_create_change_triggers.sql');
GO

-- Step 5: Execute the baseline snapshot script to capture current state
EXEC ('sqlcmd -S "192.168.168.106,2436" -d "wf125sR_82026" -U "readwrite_user" -P "VeryStrongPassword123!" -i sql-monitoring\10_baseline_snapshot.sql');
GO

-- Step 6: Run the DMV monitor script to start monitoring EDI activity
EXEC ('sqlcmd -S "192.168.168.106,2436" -d "wf125sR_82026" -U "readwrite_user" -P "VeryStrongPassword123!" -i sql-monitoring\11_edi_change_monitor.sql');
GO

-- Step 7: Run the script to capture row count snapshots
EXEC ('sqlcmd -S "192.168.168.106,2436" -d "wf125sR_82026" -U "readwrite_user" -P "VeryStrongPassword123!" -i sql-monitoring\12_capture_edi_snapshots.sql');
GO
