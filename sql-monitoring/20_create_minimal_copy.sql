-- ============================================================================
-- 20_create_minimal_copy.sql  (flask -> flask_minimal, preserve items+customers)
-- Creates minimal copy via BACKUP/RESTORE + purges transactional tables.
--
-- REQUIREMENTS: Must be run as SA (readwrite_user cannot CREATE DATABASE).
--   SA creds: ~/workspace/saved_pass  (sa / Andrewplugg07606dev)
--
-- USAGE:
--   Step A - Backup & Restore (run in master as SA):
--     sqlcmd -S "192.168.168.106,2436" -d "master" -U "sa" -P 'Andrewplugg07606dev' -C -i sql-monitoring/20_create_minimal_copy.sql
--
--   Step B is auto-included: after restore, script switches to flask_minimal
--   and purges. If you prefer two-step, use 20b_purge_minimal_only.sql with -d flask_minimal.
--
-- Preserve list: items + customer masters (EDIT SECTION 6 to tune).
-- Purges: EDI, SO/PO, pick, invoice, packlist, logs, etc. (all except #preserve, mon, dtproperties)
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

PRINT '=== 20_create_minimal_copy: flask -> flask_minimal ===';
PRINT 'Server: ' + @@SERVERNAME + '  Login: ' + SUSER_SNAME() + '  DB: ' + DB_NAME();
GO

-- ============================================================
-- PART A: BACKUP flask + RESTORE as flask_minimal (SA, master)
-- ============================================================
-- Must be in master for RESTORE. If not, switch.
IF DB_NAME() <> 'master'
    PRINT 'WARNING: Part A expects -d master. Current DB=' + DB_NAME() + ' - attempting anyway...';
GO

DECLARE @bak NVARCHAR(260) = N'E:\MSSQL\Data\flask_minimal.bak';

PRINT 'A1: Backing up flask to ' + @bak + ' ...';
BACKUP DATABASE [flask] TO DISK = @bak WITH INIT, COMPRESSION, STATS=10;
PRINT 'A1: Backup complete';
GO

-- Drop flask_minimal if exists
IF DB_ID('flask_minimal') IS NOT NULL
BEGIN
    PRINT 'A2: Dropping existing flask_minimal (killing sessions)...';
    DECLARE @kill NVARCHAR(MAX) = N'';
    SELECT @kill += N'KILL ' + CAST(session_id AS NVARCHAR(10)) + N';'
    FROM sys.dm_exec_sessions WHERE database_id = DB_ID('flask_minimal') AND session_id <> @@SPID;
    IF LEN(@kill) > 0 EXEC(@kill);
    ALTER DATABASE [flask_minimal] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [flask_minimal];
    PRINT 'A2: Old flask_minimal dropped';
END
GO

PRINT 'A3: Restoring flask_minimal from backup...';
RESTORE DATABASE [flask_minimal] FROM DISK = N'E:\MSSQL\Data\flask_minimal.bak' WITH
    MOVE 'wfData' TO 'F:\SQLDATA\flask_minimal.mdf',
    MOVE 'wf_log' TO 'F:\SQLDATA\flask_minimal_log.ldf',
    REPLACE, RECOVERY, STATS=10;
PRINT 'A3: Restore complete';
GO

ALTER DATABASE [flask_minimal] SET RECOVERY SIMPLE;
PRINT 'A4: flask_minimal set to SIMPLE recovery';
GO

PRINT '=== PART A complete. Switching to flask_minimal for purge ===';
GO

-- ============================================================
-- PART B: PURGE transactional data in flask_minimal
-- ============================================================
-- Switch context to flask_minimal for remainder
USE [flask_minimal];
GO
PRINT 'B5: Removing monitoring (if present)...';
GO
DECLARE @dropped INT = 0, @failed INT = 0;
DECLARE @s SYSNAME, @t SYSNAME, @sql NVARCHAR(MAX);
DECLARE trg_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT QUOTENAME(OBJECT_SCHEMA_NAME(object_id)), QUOTENAME(name)
    FROM sys.triggers WHERE name LIKE 'trg_audit[_]%' AND parent_class = 1;
OPEN trg_cur;
FETCH NEXT FROM trg_cur INTO @s, @t;
WHILE @@FETCH_STATUS=0
BEGIN
    BEGIN TRY
        SET @sql = N'DROP TRIGGER ' + @s + N'.' + @t;
        EXEC(@sql);
        SET @dropped+=1;
    END TRY
    BEGIN CATCH
        SET @failed+=1;
        PRINT 'FAILED drop ' + @s + '.' + @t + ': ' + ERROR_MESSAGE();
    END CATCH;
    FETCH NEXT FROM trg_cur INTO @s, @t;
END
CLOSE trg_cur; DEALLOCATE trg_cur;
PRINT 'B5: Audit triggers dropped: ' + CAST(@dropped AS VARCHAR(10)) + CASE WHEN @failed>0 THEN ' failed:'+CAST(@failed AS VARCHAR(10)) ELSE '' END;
GO
-- DDL trigger + mon objects (separate batch to avoid GO issues)
IF EXISTS (SELECT 1 FROM sys.triggers WHERE name='trg_mon_ddl_audit' AND parent_class_desc='DATABASE')
BEGIN
    BEGIN TRY
        DISABLE TRIGGER trg_mon_ddl_audit ON DATABASE;
        DROP TRIGGER trg_mon_ddl_audit ON DATABASE;
        PRINT 'B5: DDL trigger dropped';
    END TRY
    BEGIN CATCH
        BEGIN TRY
            EXEC(N'ALTER TRIGGER trg_mon_ddl_audit ON DATABASE FOR DDL_DATABASE_LEVEL_EVENTS AS BEGIN SET NOCOUNT ON; RETURN; END;');
            DISABLE TRIGGER trg_mon_ddl_audit ON DATABASE;
            PRINT 'B5: DDL trigger neutralized+disabled (DROP blocked)';
        END TRY
        BEGIN CATCH
            PRINT 'B5: DDL trigger disable failed: '+ERROR_MESSAGE();
        END CATCH
    END CATCH
END
GO
IF OBJECT_ID('mon.vw_ddl_audit_parsed') IS NOT NULL DROP VIEW mon.vw_ddl_audit_parsed;
IF OBJECT_ID('mon.sp_capture_snapshot') IS NOT NULL DROP PROC mon.sp_capture_snapshot;
IF OBJECT_ID('mon.sp_activity_summary') IS NOT NULL DROP PROC mon.sp_activity_summary;
IF OBJECT_ID('mon.dml_audit') IS NOT NULL DROP TABLE mon.dml_audit;
IF OBJECT_ID('mon.ddl_audit') IS NOT NULL DROP TABLE mon.ddl_audit;
IF OBJECT_ID('mon.rowcount_history') IS NOT NULL DROP TABLE mon.rowcount_history;
GO
DECLARE @hasMon BIT = CASE WHEN SCHEMA_ID('mon') IS NOT NULL THEN 1 ELSE 0 END;
IF @hasMon = 1
BEGIN
    BEGIN TRY
        DROP SCHEMA mon;
        PRINT 'B5: mon schema dropped';
    END TRY
    BEGIN CATCH
        PRINT 'mon schema kept: '+ERROR_MESSAGE();
    END CATCH
END
PRINT 'B5: Monitoring teardown done';
GO

-- B6: Define preserve list: items + customer masters (EDIT HERE)
IF OBJECT_ID('tempdb..#preserve') IS NOT NULL DROP TABLE #preserve;
CREATE TABLE #preserve (table_name SYSNAME PRIMARY KEY);
INSERT INTO #preserve VALUES
('customer'),('customer_edi'),('customer_status'),('customer_docs'),('customer_contract'),
('customer_shipping_label'),('customer_edi_log'),('customer_log'),
('billto'),('store'),('salesrep'),('shipvia'),('terms'),('currency'),('contact'),('contacts'),
('ivtf'),('ivtf_wh'),('ivtf_wh_prepack'),('ivtf_lot'),('ivtf_lot_bartender'),('ivtf_prepack'),
('ivtf_vendor'),('ivtf_vendor_cost'),('ivtf_image'),('ivtf_image_file'),('ivtf_attribute'),
('ivtf_cost'),('ivtf_patterncard'),('ivtf_techpage_status'),('ivtf_delivery_dates'),('ivtf_flags'),
('ivtf_docs'),('ivtf_sample'),('ivtf_sample_docs'),('ivtf_user_selection'),
('ivtr'),('ivtr_lot'),('ivtr_image'),
('code_sku'),('code_sku_alx'),('code_sku_inactive'),
('color'),('color_chart'),('color_palette'),('color_nrf'),('color_size_nrf'),('colors'),
('category'),('division'),('div'),('dept'),('season'),('uom'),('manufacturer'),
('care_list'),('carelabel'),
('WAREHOUSE'),('location'),('boxrule'),('charge_code'),('glchart');
GO
DECLARE @cnt INT; SELECT @cnt = COUNT(*) FROM #preserve;
PRINT 'B6: Preserve list: ' + CAST(@cnt AS VARCHAR(10)) + ' tables';
SELECT table_name FROM #preserve ORDER BY table_name;
GO

-- B7: Disable FK constraints and any remaining triggers
PRINT 'B7: Disabling FK constraints...';
GO
DECLARE @dis NVARCHAR(MAX) = N'';
SELECT @dis += N'ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N' NOCHECK CONSTRAINT ALL;' + CHAR(10)
FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name <> 'mon';
EXEC(@dis);
PRINT 'B7: FK constraints disabled';
GO
DECLARE @trigd NVARCHAR(MAX) = N'';
SELECT @trigd += N'DISABLE TRIGGER ' + QUOTENAME(tr.name) + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N';' + CHAR(10)
FROM sys.triggers tr JOIN sys.tables t ON tr.parent_id=t.object_id JOIN sys.schemas s ON t.schema_id=s.schema_id;
IF LEN(@trigd) > 0 EXEC(@trigd);
PRINT 'B7: Triggers disabled';
GO

-- B8: Purge loop: TRUNCATE else DELETE
PRINT 'B8: Purging non-preserved tables (TRUNCATE else DELETE)...';
GO
DECLARE @purge TABLE (schema_name SYSNAME, table_name SYSNAME, rows_before BIGINT, action_taken NVARCHAR(20), rows_after BIGINT, err NVARCHAR(4000));
DECLARE @sch SYSNAME, @tbl SYSNAME, @fq NVARCHAR(300);
DECLARE @before BIGINT, @after BIGINT, @action NVARCHAR(20), @err NVARCHAR(4000);
DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT s.name, t.name
    FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id
    LEFT JOIN #preserve p ON p.table_name = t.name COLLATE DATABASE_DEFAULT
    WHERE p.table_name IS NULL AND s.name <> 'mon' AND t.name NOT IN ('dtproperties','sysdiagrams') AND t.is_ms_shipped=0
    ORDER BY s.name, t.name;
OPEN cur;
FETCH NEXT FROM cur INTO @sch, @tbl;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @fq = QUOTENAME(@sch) + N'.' + QUOTENAME(@tbl);
    SET @before = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id=OBJECT_ID(@fq) AND p.index_id IN (0,1));
    SET @action = N''; SET @err = N'';
    BEGIN TRY
        EXEC(N'TRUNCATE TABLE ' + @fq);
        SET @action=N'TRUNCATE';
    END TRY
    BEGIN CATCH
        BEGIN TRY
            EXEC(N'DELETE FROM ' + @fq);
            SET @action=N'DELETE';
            SET @err=ERROR_MESSAGE();
        END TRY
        BEGIN CATCH
            SET @action=N'FAILED';
            SET @err=ERROR_MESSAGE();
        END CATCH
    END CATCH
    SET @after = (SELECT SUM(p.rows) FROM sys.partitions p WHERE p.object_id=OBJECT_ID(@fq) AND p.index_id IN (0,1));
    INSERT INTO @purge VALUES (@sch, @tbl, @before, @action, @after, @err);
    PRINT @action + N' ' + @fq + N' (' + ISNULL(CAST(@before AS VARCHAR(20)),'?') + N'->' + ISNULL(CAST(@after AS VARCHAR(20)),'?') + N') ' + @err;
    FETCH NEXT FROM cur INTO @sch, @tbl;
END
CLOSE cur; DEALLOCATE cur;
SELECT schema_name, table_name, rows_before, action_taken, rows_after, err FROM @purge ORDER BY rows_before DESC;
DECLARE @purged INT, @failed2 INT;
SELECT @purged = COUNT(*) FROM @purge WHERE action_taken IN ('TRUNCATE','DELETE');
SELECT @failed2 = COUNT(*) FROM @purge WHERE action_taken='FAILED';
PRINT 'B8: Purged=' + CAST(@purged AS VARCHAR(10)) + ' Failed=' + CAST(@failed2 AS VARCHAR(10));
GO

-- B9: Reseed identities
PRINT 'B9: Reseeding identities...';
GO
DECLARE @seed NVARCHAR(MAX)=N'';
SELECT @seed += N'DBCC CHECKIDENT (''' + s.name + N'.' + t.name + N''', RESEED, 0);' + CHAR(10)
FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id JOIN sys.columns c ON c.object_id=t.object_id AND c.is_identity=1
LEFT JOIN #preserve p ON p.table_name=t.name COLLATE DATABASE_DEFAULT
WHERE p.table_name IS NULL AND s.name<>'mon';
IF LEN(@seed)>0 EXEC(@seed);
PRINT 'B9: Done';
GO

-- B10: Re-enable FK constraints WITH NOCHECK
PRINT 'B10: Re-enabling constraints WITH NOCHECK...';
GO
DECLARE @en NVARCHAR(MAX)=N'';
SELECT @en += N'ALTER TABLE ' + QUOTENAME(s.name) + N'.' + QUOTENAME(t.name) + N' WITH NOCHECK CHECK CONSTRAINT ALL;' + CHAR(10)
FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id WHERE s.name<>'mon';
EXEC(@en);
PRINT 'B10: Done';
GO

-- B11: Verify
PRINT 'B11: Preserved tables (should still have rows):';
SELECT s.name AS schema_name, t.name AS table_name, SUM(p.rows) AS rows_now
FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
WHERE t.name IN (SELECT table_name FROM #preserve) GROUP BY s.name, t.name ORDER BY rows_now DESC;
GO
PRINT 'B11: Non-preserved tables still >0 rows (should be 0):';
SELECT s.name, t.name, SUM(p.rows) AS rows_now
FROM sys.tables t JOIN sys.schemas s ON t.schema_id=s.schema_id JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
LEFT JOIN #preserve px ON px.table_name=t.name COLLATE DATABASE_DEFAULT
WHERE px.table_name IS NULL AND s.name<>'mon' AND t.name<>'dtproperties' GROUP BY s.name, t.name HAVING SUM(p.rows)>0 ORDER BY SUM(p.rows) DESC;
GO

PRINT '=== Minimal copy flask_minimal purge complete ===';
GO
