-- ============================================================================
-- 17_remove_monitoring.sql
-- TEARDOWN: removes every artifact deployed by 13/15/16/18 from THIS database.
-- Run BEFORE dropping/restoring a database if you want it back to its
-- pre-monitoring state, or simply to uninstall monitoring.
--
-- Removes:
--   1. Every per-table audit trigger (trg_audit_<schema>_<table>)
--   2. Database DDL trigger trg_mon_ddl_audit
--      NOTE: this server blocks DROP of database-scoped triggers even as dbo;
--      fallback = DISABLE + replace body with an inert stub (report says which).
--   3. mon.vw_ddl_audit_parsed, mon.sp_capture_snapshot, mon.sp_activity_summary,
--      mon.dml_audit / mon.ddl_audit / mon.rowcount_history, then schema mon.
--   4. Query Store stays ON by default (history is harmless); flip @qs_off to
--      turn it off too.
-- Touches nothing else. Idempotent: safe on partially/never-monitored DBs.
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @qs_off BIT = 0;   -- set to 1 to also switch Query Store OFF
DECLARE @dropped INT = 0, @failed INT = 0, @msg VARCHAR(200);

PRINT '=== Removing monitoring from ' + DB_NAME() + ' ===';

-- 1. Per-table audit triggers ------------------------------------------------
DECLARE @s SYSNAME, @t SYSNAME, @sql NVARCHAR(MAX);
DECLARE trg_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT QUOTENAME(OBJECT_SCHEMA_NAME(object_id)) AS s, QUOTENAME(name) AS t
    FROM sys.triggers
    WHERE name LIKE 'trg_audit[_]%' AND parent_class = 1;
OPEN trg_cur;
FETCH NEXT FROM trg_cur INTO @s, @t;
WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        SET @sql = N'DROP TRIGGER ' + @s + '.' + @t + N';';
        EXEC(@sql) AS USER='dbo';
        SET @dropped += 1;
    END TRY
    BEGIN CATCH
        SET @failed += 1;
        PRINT 'FAILED drop trigger ' + @s + '.' + @t + ': ' + ERROR_MESSAGE();
    END CATCH;
    FETCH NEXT FROM trg_cur INTO @s, @t;
END
CLOSE trg_cur; DEALLOCATE trg_cur;
PRINT '1. Audit triggers dropped: ' + CAST(@dropped AS VARCHAR(10)) +
     CASE WHEN @failed > 0 THEN ', FAILED: ' + CAST(@failed AS VARCHAR(10)) ELSE '' END;

-- 2. Database DDL trigger ----------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name='trg_mon_ddl_audit' AND parent_class_desc='DATABASE')
BEGIN
    DECLARE @gone BIT = 0;
    BEGIN TRY
        EXEC(N'DISABLE TRIGGER trg_mon_ddl_audit ON DATABASE;') AS USER='dbo';
        EXEC(N'DROP TRIGGER trg_mon_ddl_audit;') AS USER='dbo';
        SET @gone = CASE WHEN NOT EXISTS (SELECT 1 FROM sys.triggers WHERE name='trg_mon_ddl_audit') THEN 1 ELSE 0 END;
    END TRY BEGIN CATCH SET @gone = 0; END CATCH;

    IF @gone = 1
        PRINT '2. trg_mon_ddl_audit dropped';
    ELSE
    BEGIN
        -- Server blocks DROP here: neutralize instead (disabled + empty body)
        BEGIN TRY
            EXEC(N'ALTER TRIGGER trg_mon_ddl_audit ON DATABASE FOR DDL_DATABASE_LEVEL_EVENTS AS BEGIN SET NOCOUNT ON; RETURN; END;') AS USER='dbo';
            PRINT '2. trg_mon_ddl_audit could NOT be dropped (server limitation) -> DISABLED + inert body. DBA can drop it later.';
        END TRY
        BEGIN CATCH
            EXEC(N'DISABLE TRIGGER trg_mon_ddl_audit ON DATABASE;');
            PRINT '2. trg_mon_ddl_audit DISABLED only: ' + ERROR_MESSAGE();
        END CATCH;
    END
END
ELSE
    PRINT '2. trg_mon_ddl_audit not present';

-- 3. mon schema contents, then the schema ------------------------------------
DECLARE @d NVARCHAR(MAX) = N'
IF OBJECT_ID(''mon.vw_ddl_audit_parsed'')  IS NOT NULL DROP VIEW  mon.vw_ddl_audit_parsed;
IF OBJECT_ID(''mon.sp_capture_snapshot'')  IS NOT NULL DROP PROC  mon.sp_capture_snapshot;
IF OBJECT_ID(''mon.sp_activity_summary'')  IS NOT NULL DROP PROC  mon.sp_activity_summary;
IF OBJECT_ID(''mon.dml_audit'')            IS NOT NULL DROP TABLE mon.dml_audit;
IF OBJECT_ID(''mon.ddl_audit'')            IS NOT NULL DROP TABLE mon.ddl_audit;
IF OBJECT_ID(''mon.rowcount_history'')     IS NOT NULL DROP TABLE mon.rowcount_history;';
BEGIN TRY
    EXEC(@d) AS USER='dbo';
    PRINT '3. mon objects dropped';
END TRY
BEGIN CATCH
    PRINT '3. FAIL dropping mon objects: ' + ERROR_MESSAGE();
END CATCH;

IF SCHEMA_ID('mon') IS NOT NULL
BEGIN
    DECLARE @sch NVARCHAR(MAX) =
        N'IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE schema_id=SCHEMA_ID(''mon''))
              AND NOT EXISTS (SELECT 1 FROM sys.columns c JOIN sys.tables t ON t.object_id=c.object_id WHERE t.schema_id=SCHEMA_ID(''mon''))
          DROP SCHEMA mon;';
    BEGIN TRY EXEC(@sch) AS USER='dbo'; PRINT '   schema mon dropped'; END TRY
    BEGIN CATCH PRINT '   schema mon kept (still has objects): ' + ERROR_MESSAGE(); END CATCH;
END

-- 4. Optional Query Store off -------------------------------------------------
IF @qs_off = 1
BEGIN
    DECLARE @q NVARCHAR(MAX) = N'ALTER DATABASE CURRENT SET QUERY_STORE = OFF;';
    EXEC(@q);
    PRINT '4. Query Store OFF';
END
ELSE
    PRINT '4. Query Store left ON';

-- Summary ---------------------------------------------------------------------
SELECT (SELECT COUNT(*) FROM sys.triggers WHERE name LIKE 'trg_audit[_]%')                          AS audit_triggers_left,
       (SELECT COUNT(*) FROM sys.triggers WHERE name='trg_mon_ddl_audit' AND is_disabled=0)         AS ddl_trigger_active_left,
       CASE WHEN SCHEMA_ID('mon') IS NULL THEN 0
            ELSE (SELECT COUNT(*) FROM sys.objects WHERE schema_id=SCHEMA_ID('mon')) END           AS mon_objects_left;
PRINT '=== Removal complete on ' + DB_NAME() + ' ===';
