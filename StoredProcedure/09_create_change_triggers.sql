-- 09_create_change_triggers.sql
-- Create triggers to capture all changes (alternative to CDC)
USE [wf125sR_82026];
GO

-- Generic change capture trigger template
-- Apply this to each table you want to monitor
-- Example for a table called 'orders':

/*
CREATE TRIGGER trg_orders_audit
ON orders
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @action VARCHAR(10);
    IF EXISTS (SELECT 1 FROM inserted) AND EXISTS (SELECT 1 FROM deleted)
        SET @action = 'UPDATE';
    ELSE IF EXISTS (SELECT 1 FROM inserted)
        SET @action = 'INSERT';
    ELSE
        SET @action = 'DELETE';
    
    -- Log INSERT/UPDATE (new values)
    IF @action IN ('INSERT', 'UPDATE')
    BEGIN
        INSERT INTO audit_log (event_type, table_name, record_id, new_values)
        SELECT 
            @action,
            'orders',
            CAST(i.id AS NVARCHAR(256)),
            (SELECT i.* FOR JSON AUTO)
        FROM inserted i;
    END
    
    -- Log UPDATE/DELETE (old values)
    IF @action IN ('UPDATE', 'DELETE')
    BEGIN
        INSERT INTO audit_log (event_type, table_name, record_id, old_values)
        SELECT 
            @action,
            'orders',
            CAST(d.id AS NVARCHAR(256)),
            (SELECT d.* FOR JSON AUTO)
        FROM deleted d;
    END
END;
GO
*/

-- Quick script to generate triggers for all user tables
-- Run this and it generates trigger creation scripts
DECLARE @sql NVARCHAR(MAX) = '';
DECLARE @table_name NVARCHAR(128);
DECLARE @schema_name NVARCHAR(128);

DECLARE table_cursor CURSOR FOR
    SELECT s.name, t.name
    FROM sys.tables t
    INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name NOT IN ('audit_log', 'edi_document_audit', 'schema_snapshot')
    ORDER BY s.name, t.name;

OPEN table_cursor;
FETCH NEXT FROM table_cursor INTO @schema_name, @table_name;

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = @sql + '-- Trigger for ' + @schema_name + '.' + @table_name + CHAR(13);
    SET @sql = @sql + 'IF OBJECT_ID(''trg_' + @table_name + '_audit'', ''TR'') IS NULL' + CHAR(13);
    SET @sql = @sql + 'BEGIN' + CHAR(13);
    SET @sql = @sql + '    EXEC(''CREATE TRIGGER trg_' + @table_name + '_audit' + CHAR(13);
    SET @sql = @sql + '    ON ' + @schema_name + '.' + @table_name + CHAR(13);
    SET @sql = @sql + '    AFTER INSERT, UPDATE, DELETE AS BEGIN' + CHAR(13);
    SET @sql = @sql + '        SET NOCOUNT ON;' + CHAR(13);
    SET @sql = @sql + '        DECLARE @a VARCHAR(10);' + CHAR(13);
    SET @sql = @sql + '        IF EXISTS(SELECT 1 FROM inserted) AND EXISTS(SELECT 1 FROM deleted) SET @a = ''UPDATE'';' + CHAR(13);
    SET @sql = @sql + '        ELSE IF EXISTS(SELECT 1 FROM inserted) SET @a = ''INSERT'';' + CHAR(13);
    SET @sql = @sql + '        ELSE SET @a = ''DELETE'';' + CHAR(13);
    SET @sql = @sql + '        INSERT INTO audit_log(event_type, table_name, record_id, old_values, new_values)' + CHAR(13);
    SET @sql = @sql + '        SELECT @a, ''' + @table_name + ''','''', ' + CHAR(13);
    SET @sql = @sql + '            (SELECT d.* FOR JSON AUTO), (SELECT i.* FOR JSON AUTO)' + CHAR(13);
    SET @sql = @sql + '        FROM inserted i FULL JOIN deleted d ON 1=0;' + CHAR(13);
    SET @sql = @sql + '    END'');' + CHAR(13);
    SET @sql = @sql + '    PRINT ''Created trg_' + @table_name + '_audit'';' + CHAR(13);
    SET @sql = @sql + 'END' + CHAR(13) + 'GO' + CHAR(13) + CHAR(13);
    
    FETCH NEXT FROM table_cursor INTO @schema_name, @table_name;
END

CLOSE table_cursor;
DEALLOCATE table_cursor;

PRINT @sql;
GO
