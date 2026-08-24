USE [wf125sR_82026];
GO

EXECUTE AS USER = 'dbo';
GO

IF OBJECT_ID('dbo.sp_audit_reconstruct_sql', 'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_audit_reconstruct_sql;
GO

CREATE PROCEDURE dbo.sp_audit_reconstruct_sql
    @audit_id INT = NULL,
    @start_id INT = NULL,
    @end_id INT = NULL,
    @table_name NVARCHAR(128) = NULL,
    @since DATETIME2 = NULL,
    @output_type VARCHAR(10) = 'RESULTS'
AS
BEGIN
    SET NOCOUNT ON;

    CREATE TABLE #reconstructed (
        audit_id INT,
        event_type VARCHAR(10),
        table_name NVARCHAR(128),
        changed_by NVARCHAR(128),
        changed_at DATETIME2,
        reconstructed_sql NVARCHAR(MAX)
    );

    DECLARE @id INT, @evt VARCHAR(10), @tbl NVARCHAR(128), @old NVARCHAR(MAX), @new NVARCHAR(MAX);
    DECLARE @sql NVARCHAR(MAX);
    DECLARE @col_list NVARCHAR(MAX);
    DECLARE @col_name NVARCHAR(128), @col_dtype NVARCHAR(128);

    DECLARE audit_cursor CURSOR FOR
        SELECT audit_id, event_type, table_name, old_values, new_values
        FROM dbo.audit_log
        WHERE (@audit_id IS NULL OR audit_id = @audit_id)
          AND (@start_id IS NULL OR audit_id >= @start_id)
          AND (@end_id IS NULL OR audit_id <= @end_id)
          AND (@table_name IS NULL OR table_name = @table_name)
          AND (@since IS NULL OR changed_at >= @since)
        ORDER BY audit_id;

    OPEN audit_cursor;
    FETCH NEXT FROM audit_cursor INTO @id, @evt, @tbl, @old, @new;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @col_list = '';
        DECLARE col_cursor CURSOR FOR
            SELECT c.name, ty.name
            FROM sys.columns c
            INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
            WHERE c.object_id = OBJECT_ID(@tbl)
              AND c.is_identity = 0
              AND ty.name NOT IN ('text', 'ntext', 'image')
            ORDER BY c.column_id;
        
        OPEN col_cursor;
        FETCH NEXT FROM col_cursor INTO @col_name, @col_dtype;
        
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @col_list = @col_list + QUOTENAME(@col_name) + ',';
            FETCH NEXT FROM col_cursor INTO @col_name, @col_dtype;
        END
        CLOSE col_cursor;
        DEALLOCATE col_cursor;
        
        SET @col_list = LEFT(@col_list, LEN(@col_list) - 1);

        IF @evt = 'INSERT'
        BEGIN
            SET @sql = 'INSERT INTO ' + QUOTENAME(@tbl) + ' (' + @col_list + ')' + CHAR(13);
            SET @sql = @sql + 'VALUES (' + dbo.fn_json_to_values(@new, @tbl) + ');';
        END
        ELSE IF @evt = 'UPDATE'
        BEGIN
            SET @sql = 'UPDATE ' + QUOTENAME(@tbl) + CHAR(13);
            SET @sql = @sql + 'SET ' + dbo.fn_json_to_set_clause(@new, @tbl) + CHAR(13);
            SET @sql = @sql + 'WHERE ' + dbo.fn_json_to_where_clause(@old, @tbl) + ';';
        END
        ELSE IF @evt = 'DELETE'
        BEGIN
            SET @sql = 'DELETE FROM ' + QUOTENAME(@tbl) + CHAR(13);
            SET @sql = @sql + 'WHERE ' + dbo.fn_json_to_where_clause(@old, @tbl) + ';';
        END

        INSERT INTO #reconstructed (audit_id, event_type, table_name, changed_by, changed_at, reconstructed_sql)
        SELECT @id, @evt, @tbl, 
               (SELECT changed_by FROM dbo.audit_log WHERE audit_id = @id),
               (SELECT changed_at FROM dbo.audit_log WHERE audit_id = @id),
               @sql;

        FETCH NEXT FROM audit_cursor INTO @id, @evt, @tbl, @old, @new;
    END

    CLOSE audit_cursor;
    DEALLOCATE audit_cursor;

    IF @output_type = 'TEXT'
    BEGIN
        DECLARE @print_sql NVARCHAR(MAX);
        DECLARE print_cursor CURSOR FOR
            SELECT reconstructed_sql FROM #reconstructed ORDER BY audit_id;
        OPEN print_cursor;
        FETCH NEXT FROM print_cursor INTO @print_sql;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            PRINT @print_sql;
            PRINT 'GO';
            FETCH NEXT FROM print_cursor INTO @print_sql;
        END
        CLOSE print_cursor;
        DEALLOCATE print_cursor;
    END
    ELSE
    BEGIN
        SELECT audit_id, event_type, table_name, changed_by, changed_at, reconstructed_sql
        FROM #reconstructed
        ORDER BY audit_id;
    END

    DROP TABLE #reconstructed;
END
GO

REVERT;
GO
