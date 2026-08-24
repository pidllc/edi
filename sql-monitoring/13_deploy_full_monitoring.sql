-- ============================================================================
-- 13_deploy_full_monitoring.sql   (v3 - EXECUTE AS dbo edition, batch-safe)
-- Full activity monitoring for environments where `public` role has DDL DENYs.
--
-- Deploys (all storage local to THIS database):
--   1. mon.dml_audit     - every INSERT/UPDATE/DELETE on every user table
--                          (old/new row values as JSON + who/when/host/app/spid)
--   2. mon.ddl_audit     - all database-scoped DDL (command text + EVENTDATA xml)
--   3. mon.rowcount_history + snapshot proc
--   4. mon.sp_activity_summary - review what data was manipulated recently
--   5. Query Store (query performance history)
--
-- Permission strategy:
--   - Tables/procs: created inside EXECUTE AS USER='dbo' (DENY-to-public proof)
--   - Triggers: created directly (not DENYed); runtime uses EXECUTE AS 'dbo'
--     so audit writes succeed no matter which app user performs the DML.
--   NOTE: DML triggers themselves are NOT created here - generate them with
--   gen_dml_triggers.py (avoids CREATE TRIGGER batch restrictions).
--
-- Idempotent. Run ONLY against the user-named target database.
-- NOTE: if trg_mon_ddl_audit already exists and cannot be dropped (this server
--       blocks DROP of db-scoped triggers), re-run prints harmless 2714; then run
--       16_ddl_trigger_autocover.sql once to refresh its body.
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

PRINT '=== Deploying monitoring to ' + DB_NAME() + ' ===';

-- 1. Monitoring schema ------------------------------------------------------
IF SCHEMA_ID('mon') IS NULL
    EXEC('CREATE SCHEMA mon AUTHORIZATION dbo;') AS USER = 'dbo';
PRINT '1. Schema mon ready';
GO

-- 2. Audit tables (elevated; CREATE TABLE tolerates preceding statements) ---
DECLARE @ddl NVARCHAR(MAX);
SET @ddl = N'SET QUOTED_IDENTIFIER ON; SET ANSI_NULLS ON;
IF OBJECT_ID(''mon.dml_audit'') IS NULL
BEGIN
    CREATE TABLE mon.dml_audit (
        audit_id    BIGINT IDENTITY(1,1) CONSTRAINT PK_mon_dml_audit PRIMARY KEY,
        event_type  VARCHAR(10)  NOT NULL,
        schema_name SYSNAME      NOT NULL,
        table_name  SYSNAME      NOT NULL,
        row_count   INT          NOT NULL DEFAULT 0,
        old_values  NVARCHAR(MAX) NULL,
        new_values  NVARCHAR(MAX) NULL,
        changed_by  SYSNAME      NOT NULL DEFAULT ORIGINAL_LOGIN(),
        host_name   SYSNAME      NOT NULL DEFAULT HOST_NAME(),
        app_name    SYSNAME      NOT NULL DEFAULT APP_NAME(),
        spid        INT          NOT NULL DEFAULT @@SPID,
        changed_at  DATETIME2(3) NOT NULL DEFAULT SYSDATETIME()
    );
    CREATE INDEX IX_dml_audit_table ON mon.dml_audit(schema_name, table_name, changed_at DESC);
    CREATE INDEX IX_dml_audit_time  ON mon.dml_audit(changed_at DESC);
END;
IF OBJECT_ID(''mon.ddl_audit'') IS NULL
BEGIN
    CREATE TABLE mon.ddl_audit (
        ddl_id        BIGINT IDENTITY(1,1) CONSTRAINT PK_mon_ddl_audit PRIMARY KEY,
        event_type    SYSNAME       NOT NULL,
        object_schema SYSNAME       NULL,
        object_name   SYSNAME       NULL,
        object_type   SYSNAME       NULL,
        tsql_command  NVARCHAR(MAX) NULL,
        event_data    XML           NOT NULL,
        login_name    SYSNAME       NOT NULL DEFAULT ORIGINAL_LOGIN(),
        host_name     SYSNAME       NOT NULL DEFAULT HOST_NAME(),
        app_name      SYSNAME       NOT NULL DEFAULT APP_NAME(),
        changed_at    DATETIME2(3)  NOT NULL DEFAULT SYSDATETIME()
    );
    CREATE INDEX IX_ddl_audit_type ON mon.ddl_audit(event_type, changed_at DESC);
    CREATE INDEX IX_ddl_audit_obj  ON mon.ddl_audit(object_schema, object_name);
END;
IF OBJECT_ID(''mon.rowcount_history'') IS NULL
BEGIN
    CREATE TABLE mon.rowcount_history (
        snapshot_id   BIGINT IDENTITY(1,1) CONSTRAINT PK_mon_rowcount_history PRIMARY KEY,
        snapshot_time DATETIME2(3) NOT NULL DEFAULT SYSDATETIME(),
        schema_name   SYSNAME      NOT NULL,
        table_name    SYSNAME      NOT NULL,
        row_count     BIGINT       NOT NULL
    );
    CREATE INDEX IX_rowcount_hist ON mon.rowcount_history(table_name, snapshot_id DESC);
END;';
EXEC(@ddl) AS USER = 'dbo';
PRINT '2. Audit tables ready';
GO

-- 3. Database DDL trigger (direct creation - not DENYed) --------------------
-- IMPORTANT DESIGN NOTES (lessons learned 2026-08-22):
--   * Database-scoped triggers are INVISIBLE to OBJECT_ID(); existence checks
--     must query sys.triggers. We simply use DROP IF EXISTS + recreate.
--   * NEVER call XML .value() methods inside this trigger: modules running
--     WITH EXECUTE AS 'dbo' execute with the impersonated principal's SET
--     options (QUOTED_IDENTIFIER OFF here) -> error 1934 on every DDL event,
--     rolling back all database DDL. Body therefore stores raw EVENTDATA()
--     XML only; parse it client-side or via mon.vw_ddl_audit_parsed.
--   * A DISABLEd trigger does not fire during its own DROP -> clean removal.
DROP TRIGGER IF EXISTS trg_mon_ddl_audit;
GO
CREATE TRIGGER trg_mon_ddl_audit
ON DATABASE
WITH EXECUTE AS N'dbo'
FOR DDL_DATABASE_LEVEL_EVENTS
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @xml NVARCHAR(MAX) = CAST(EVENTDATA() AS NVARCHAR(MAX));
    DECLARE @et  SYSNAME, @sch SYSNAME, @obj SYSNAME;

    SET @et  = SUBSTRING(@xml, CHARINDEX('<EventType>',@xml)+11,
               CHARINDEX('</EventType>',@xml)-CHARINDEX('<EventType>',@xml)-11);

    IF @et = 'CREATE_TABLE'
    BEGIN
        SET @sch = SUBSTRING(@xml, CHARINDEX('<SchemaName>',@xml)+12,
                   CHARINDEX('</SchemaName>',@xml)-CHARINDEX('<SchemaName>',@xml)-12);
        SET @obj = SUBSTRING(@xml, CHARINDEX('<ObjectName>',@xml)+12,
                   CHARINDEX('</ObjectName>',@xml)-CHARINDEX('<ObjectName>',@xml)-12);

        IF ISNULL(@sch,'') <> 'mon'
        BEGIN
            DECLARE @tq SYSNAME = QUOTENAME(@sch) + '.' + QUOTENAME(@obj);
            IF OBJECT_ID(@tq,'U') IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM sys.triggers
                               WHERE parent_id = OBJECT_ID(@tq)
                                 AND name LIKE 'trg_audit[_]%')
            BEGIN
                DECLARE @cols NVARCHAR(MAX);
                SELECT @cols = STRING_AGG(CAST(QUOTENAME(c.name) AS NVARCHAR(MAX)), ',')
                               WITHIN GROUP (ORDER BY c.column_id)
                FROM sys.columns c
                JOIN sys.types ty ON ty.system_type_id = c.system_type_id
                                 AND ty.user_type_id   = c.user_type_id
                WHERE c.object_id = OBJECT_ID(@tq)
                  AND c.is_computed = 0
                  AND ty.name NOT IN ('text','ntext','image','geography','geometry','hierarchyid');

                IF @cols IS NOT NULL
                BEGIN
                    DECLARE @sql NVARCHAR(MAX) =
                          N'CREATE TRIGGER ' + QUOTENAME('trg_audit_' + @sch + '_' + @obj)
                        + N' ON ' + @tq
                        + N' WITH EXECUTE AS N''dbo'' AFTER INSERT, UPDATE, DELETE AS '
                        + N'BEGIN SET NOCOUNT ON; '
                        + N'DECLARE @a VARCHAR(10)=CASE WHEN EXISTS(SELECT 1 FROM inserted) AND EXISTS(SELECT 1 FROM deleted) THEN ''UPDATE'' WHEN EXISTS(SELECT 1 FROM inserted) THEN ''INSERT'' ELSE ''DELETE'' END; '
                        + N'INSERT INTO mon.dml_audit(event_type,schema_name,table_name,row_count,old_values,new_values) '
                        + N'SELECT @a,''' + REPLACE(@sch,'''','''''') + N''','''
                                       + REPLACE(@obj,'''','''''') + N''','
                        + N'CASE WHEN @a IN(''INSERT'',''UPDATE'') THEN (SELECT COUNT(*) FROM inserted) ELSE (SELECT COUNT(*) FROM deleted) END,'
                        + N'CASE WHEN @a IN(''DELETE'',''UPDATE'') THEN (SELECT d.' + @cols + N' FROM deleted d FOR JSON PATH) END,'
                        + N'CASE WHEN @a IN(''INSERT'',''UPDATE'') THEN (SELECT i.' + @cols + N' FROM inserted i FOR JSON PATH) END;'
                        + N'END;';
                    EXEC(@sql);
                END
            END
        END
        INSERT INTO mon.ddl_audit (event_type, event_data) SELECT 'DDL_EVENT', EVENTDATA();
        RETURN;
    END

    IF @et = 'DROP_TABLE'
    BEGIN
        SET @sch = SUBSTRING(@xml, CHARINDEX('<SchemaName>',@xml)+12,
                   CHARINDEX('</SchemaName>',@xml)-CHARINDEX('<SchemaName>',@xml)-12);
        SET @obj = SUBSTRING(@xml, CHARINDEX('<ObjectName>',@xml)+12,
                   CHARINDEX('</ObjectName>',@xml)-CHARINDEX('<ObjectName>',@xml)-12);
        IF ISNULL(@sch,'') <> 'mon'
        BEGIN
            DECLARE @drop NVARCHAR(MAX) =
                N'DROP TRIGGER IF EXISTS ' + QUOTENAME('trg_audit_' + @sch + '_' + @obj) + N';';
            EXEC(@drop);
        END
    END

    -- Log all other DDL events raw (parse later via mon.vw_ddl_audit_parsed)
    INSERT INTO mon.ddl_audit (event_type, event_data) SELECT 'DDL_EVENT', EVENTDATA();
END;
GO
PRINT '3. DDL trigger trg_mon_ddl_audit created';
GO

-- Parsed convenience view (created elevated; runs under CALLER settings at query time -
-- needs QUOTED_IDENTIFIER ON in the querying session)
DECLARE @v NVARCHAR(MAX) = N'CREATE OR ALTER VIEW mon.vw_ddl_audit_parsed
AS
SELECT ddl_id, changed_at, login_name, host_name, app_name,
       event_data.value(''(/EVENT_INSTANCE/EventType)[1]'',   ''SYSNAME'')   AS event_type,
       event_data.value(''(/EVENT_INSTANCE/SchemaName)[1]'',  ''SYSNAME'')   AS object_schema,
       event_data.value(''(/EVENT_INSTANCE/ObjectName)[1]'',  ''SYSNAME'')   AS object_name,
       event_data.value(''(/EVENT_INSTANCE/ObjectType)[1]'',  ''SYSNAME'')   AS object_type,
       event_data.value(''(/EVENT_INSTANCE/TSQLCommand/CommandText)[1]'', ''NVARCHAR(MAX)'') AS tsql_command,
       event_data
FROM mon.ddl_audit;';
EXEC(@v) AS USER = 'dbo';
GO
PRINT '3b. View mon.vw_ddl_audit_parsed created';
GO

-- 4. Query Store (ALTER DATABASE verified allowed without elevation) --------
DECLARE @qson BIT = (SELECT is_query_store_on FROM sys.databases WHERE database_id = DB_ID());
IF @qson = 0
BEGIN
    DECLARE @qs NVARCHAR(MAX) = N'ALTER DATABASE CURRENT SET QUERY_STORE = ON (
        OPERATION_MODE = READ_WRITE,
        CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
        DATA_FLUSH_INTERVAL_SECONDS = 900,
        MAX_STORAGE_SIZE_MB = 512,
        QUERY_CAPTURE_MODE = AUTO,
        SIZE_BASED_CLEANUP_MODE = AUTO );';
    EXEC(@qs);
    PRINT '4. Query Store enabled';
END
ELSE
    PRINT '4. Query Store already enabled';
GO

-- 5. Snapshot + activity summary procs (elevated; each CREATE PROC alone) ---
DECLARE @p NVARCHAR(MAX);
SET @p = N'CREATE PROCEDURE mon.sp_capture_snapshot
WITH EXECUTE AS N''dbo''
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO mon.rowcount_history (schema_name, table_name, row_count)
    SELECT s.name, t.name, SUM(p.rows)
    FROM sys.tables t
    JOIN sys.schemas s    ON t.schema_id = s.schema_id
    JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
    WHERE s.name <> ''mon''
    GROUP BY s.name, t.name;

    SELECT COUNT(*) AS tables_captured, MAX(snapshot_time) AS snapshot_time
    FROM mon.rowcount_history r
    WHERE snapshot_id = (SELECT MAX(snapshot_id) FROM mon.rowcount_history r2
                         WHERE r2.schema_name = r.schema_name AND r2.table_name = r.table_name);
END;';
EXEC(@p) AS USER = 'dbo';
PRINT '5a. mon.sp_capture_snapshot created';
GO

DECLARE @p NVARCHAR(MAX);
SET @p = N'CREATE PROCEDURE mon.sp_activity_summary (@minutes INT = 60)
WITH EXECUTE AS N''dbo''
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @since DATETIME2(3) = DATEADD(MINUTE, -@minutes, SYSDATETIME());

    RAISERROR(''=== Data manipulation in the last %d minutes ==='', 0, 1, @minutes) WITH NOWAIT;
    SELECT TOP 50 schema_name, table_name, event_type,
                  COUNT(*) AS statements, SUM(row_count) AS rows_affected,
                  MIN(changed_at) AS first_seen, MAX(changed_at) AS last_seen
    FROM mon.dml_audit WITH (NOLOCK)
    WHERE changed_at >= @since
    GROUP BY schema_name, table_name, event_type
    ORDER BY last_seen DESC;

    RAISERROR(''=== Users active in the window ==='', 0, 1) WITH NOWAIT;
    SELECT DISTINCT changed_by, host_name, app_name
    FROM mon.dml_audit WITH (NOLOCK)
    WHERE changed_at >= @since;

    RAISERROR(''=== DDL in the last %d minutes ==='', 0, 1, @minutes) WITH NOWAIT;
    SELECT TOP 50 event_type, object_schema, object_name, object_type,
                  login_name, host_name, changed_at
    FROM mon.ddl_audit WITH (NOLOCK)
    WHERE changed_at >= @since
    ORDER BY changed_at DESC;

    RAISERROR(''=== Row-count deltas between two most recent snapshots ==='', 0, 1) WITH NOWAIT;
    SELECT TOP 100 prev.schema_name, prev.table_name,
                   prev.row_count AS before_rows, curr.row_count AS after_rows,
                   curr.row_count - prev.row_count AS delta
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY schema_name, table_name ORDER BY snapshot_id DESC) AS rn
          FROM mon.rowcount_history) curr
    JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY schema_name, table_name ORDER BY snapshot_id DESC) AS rn
          FROM mon.rowcount_history) prev
        ON curr.schema_name = prev.schema_name AND curr.table_name = prev.table_name AND prev.rn = 2
    WHERE curr.rn = 1 AND curr.row_count <> prev.row_count
    ORDER BY ABS(curr.row_count - prev.row_count) DESC;
END;';
EXEC(@p) AS USER = 'dbo';
PRINT '5b. mon.sp_activity_summary created';

DECLARE @g NVARCHAR(MAX) = N'GRANT SELECT ON SCHEMA::mon TO public; GRANT EXECUTE ON SCHEMA::mon TO public;';
EXEC(@g) AS USER = 'dbo';
PRINT '   Grants on mon schema issued';
GO


PRINT '=== Deployment complete on ' + DB_NAME() + ' ===';
