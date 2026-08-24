-- ============================================================================
-- 14_selftest_monitoring.sql
-- Proves end-to-end change capture: creates a scratch table (auto-covered by
-- trg_mon_ddl_audit), performs INSERT / UPDATE / DELETE, drops everything,
-- then shows exactly what was captured.
-- Safe: touches only scratch objects named _mon_selftest*.
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

PRINT '=== SELFTEST on ' + DB_NAME() + ' ===';

EXEC(N'IF OBJECT_ID(''dbo._mon_selftest'') IS NOT NULL DROP TABLE dbo._mon_selftest; CREATE TABLE dbo._mon_selftest (id INT IDENTITY(1,1), val VARCHAR(50));') AS USER = 'dbo';

WAITFOR DELAY '00:00:01';
DECLARE @auto BIT = (SELECT COUNT(*) FROM sys.triggers WHERE name='trg_audit_dbo__mon_selftest');
PRINT 'auto-created audit trigger present: ' + CASE WHEN @auto=1 THEN 'YES' ELSE 'NO' END;

INSERT INTO dbo._mon_selftest (val) VALUES ('alpha'), ('beta');
UPDATE dbo._mon_selftest SET val = 'gamma' WHERE val = 'alpha';
DELETE FROM dbo._mon_selftest WHERE val = 'beta';
PRINT 'DML done: 2 inserts, 1 update, 1 delete';

WAITFOR DELAY '00:00:01';
PRINT '';
PRINT '--- captured in mon.dml_audit ---';
SELECT event_type, schema_name, table_name, row_count,
       CAST(old_values AS NVARCHAR(200)) AS old_preview,
       CAST(new_values AS NVARCHAR(200)) AS new_preview,
       changed_by, changed_at
FROM mon.dml_audit
WHERE table_name = '_mon_selftest'
ORDER BY audit_id;

PRINT '--- related DDL events (parsed view) ---';
SELECT event_type, object_name FROM mon.vw_ddl_audit_parsed
WHERE object_name LIKE '%_mon_selftest%' ORDER BY ddl_id;

EXEC(N'DROP TABLE dbo._mon_selftest;') AS USER = 'dbo';
WAITFOR DELAY '00:00:01';
DECLARE @gone BIT = (SELECT COUNT(*) FROM sys.triggers WHERE name='trg_audit_dbo__mon_selftest');
PRINT 'cleanup: audit trigger removed automatically: ' + CASE WHEN @gone=0 THEN 'YES' ELSE 'NO' END;
