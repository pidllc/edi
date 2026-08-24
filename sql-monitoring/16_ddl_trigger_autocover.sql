-- ============================================================================
-- 16_ddl_trigger_autocover.sql
-- Upgrades trg_mon_ddl_audit so NEW tables get audit triggers automatically:
--   * CREATE TABLE -> builds trg_audit_<schema>_<table> immediately
--     (columns resolved at runtime; computed + LOB-type columns excluded)
--   * DROP TABLE   -> drops the matching audit trigger
-- Uses pure string parsing of EVENTDATA() (NO XML .value() calls - those fail
-- under EXECUTE AS 'dbo' because impersonation resets QUOTED_IDENTIFIER).
-- Safe to re-run (ALTER). For FRESH databases, 13 creates the same body.
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO
ALTER TRIGGER trg_mon_ddl_audit
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
PRINT 'trg_mon_ddl_audit upgraded with auto-cover';

-- Ensure active after body refresh (teardown may have left it disabled)
EXEC(N'ENABLE TRIGGER trg_mon_ddl_audit ON DATABASE;') AS USER='dbo';
SELECT name, is_disabled FROM sys.triggers WHERE name='trg_mon_ddl_audit';
