-- 07_enable_cdc.sql
-- Enable Change Data Capture on database (requires sysadmin)
USE [master];
GO

-- Check if CDC is already enabled
SELECT name, is_cdc_enabled 
FROM sys.databases 
WHERE name = 'wf125sR_82026';
GO

-- Enable CDC on database (run as sysadmin)
-- EXEC sys.sp_cdc_enable_db;
-- GO

-- After DB-level CDC enabled, enable per table:
-- EXEC sys.sp_cdc_enable_table
--     @source_schema = N'dbo',
--     @source_name = N'YourTableName',
--     @role_name = N'cdc_reader',
--     @supports_net_changes = 1;
-- GO

-- Check CDC status
SELECT * FROM cdc.change_tables;
GO
SELECT * FROM cdc.dbo_cdc_events;
GO
