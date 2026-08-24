USE [wf125sR_82026];
GO

EXECUTE AS USER = 'dbo';
GO

CREATE FUNCTION dbo.fn_json_to_set_clause (@json NVARCHAR(MAX), @table NVARCHAR(128))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @result NVARCHAR(MAX) = '';
    DECLARE @sep NVARCHAR(2) = '';
    DECLARE @col NVARCHAR(128), @val NVARCHAR(MAX), @dtype NVARCHAR(128);
    IF @json IS NULL OR @json = '' RETURN '1=0';
    SET @json = REPLACE(REPLACE(@json, '[', ''), ']', '');
    
    DECLARE col_cursor CURSOR FOR
        SELECT c.name, ty.name FROM sys.columns c
        INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
        WHERE c.object_id = OBJECT_ID(@table) AND c.is_identity = 0
          AND ty.name NOT IN ('text', 'ntext', 'image')
        ORDER BY c.column_id;
    
    OPEN col_cursor;
    FETCH NEXT FROM col_cursor INTO @col, @dtype;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @val = JSON_VALUE(@json, '$.' + @col);
        IF @val IS NOT NULL SET @val = RTRIM(@val);
        
        IF @val IS NOT NULL
        BEGIN
            SET @result = @result + @sep + QUOTENAME(@col) + ' = ';
            IF @dtype IN ('int','bigint','smallint','tinyint')
                SET @result = @result + @val;
            ELSE IF @dtype IN ('decimal','numeric','money','smallmoney','float','real')
                SET @result = @result + @val;
            ELSE IF @dtype IN ('bit')
                SET @result = @result + CASE WHEN @val = 'true' THEN '1' WHEN @val = 'false' THEN '0' ELSE @val END;
            ELSE
                SET @result = @result + '''' + REPLACE(@val, '''', '''''') + '''';
            SET @sep = ', ';
        END
        FETCH NEXT FROM col_cursor INTO @col, @dtype;
    END
    CLOSE col_cursor;
    DEALLOCATE col_cursor;
    IF @result = '' SET @result = '1=1';
    RETURN @result;
END
GO

CREATE FUNCTION dbo.fn_json_to_values (@json NVARCHAR(MAX), @table NVARCHAR(128))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @result NVARCHAR(MAX) = '';
    DECLARE @sep NVARCHAR(1) = '';
    DECLARE @col NVARCHAR(128), @val NVARCHAR(MAX), @dtype NVARCHAR(128);
    IF @json IS NULL OR @json = '' RETURN 'NULL';
    SET @json = REPLACE(REPLACE(@json, '[', ''), ']', '');
    
    DECLARE col_cursor CURSOR FOR
        SELECT c.name, ty.name FROM sys.columns c
        INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
        WHERE c.object_id = OBJECT_ID(@table) AND c.is_identity = 0
          AND ty.name NOT IN ('text', 'ntext', 'image')
        ORDER BY c.column_id;
    
    OPEN col_cursor;
    FETCH NEXT FROM col_cursor INTO @col, @dtype;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @val = JSON_VALUE(@json, '$.' + @col);
        IF @val IS NOT NULL SET @val = RTRIM(@val);
        
        SET @result = @result + @sep;
        IF @val IS NULL
            SET @result = @result + 'NULL';
        ELSE IF @dtype IN ('int','bigint','smallint','tinyint')
            SET @result = @result + @val;
        ELSE IF @dtype IN ('decimal','numeric','money','smallmoney','float','real')
            SET @result = @result + @val;
        ELSE IF @dtype IN ('bit')
            SET @result = @result + CASE WHEN @val = 'true' THEN '1' WHEN @val = 'false' THEN '0' ELSE @val END;
        ELSE
            SET @result = @result + '''' + REPLACE(@val, '''', '''''') + '''';
        SET @sep = ',';
        FETCH NEXT FROM col_cursor INTO @col, @dtype;
    END
    CLOSE col_cursor;
    DEALLOCATE col_cursor;
    RETURN @result;
END
GO

CREATE FUNCTION dbo.fn_json_to_where_clause (@json NVARCHAR(MAX), @table NVARCHAR(128))
RETURNS NVARCHAR(MAX)
AS
BEGIN
    DECLARE @result NVARCHAR(MAX) = '';
    DECLARE @sep NVARCHAR(5) = '';
    DECLARE @col NVARCHAR(128), @val NVARCHAR(MAX), @dtype NVARCHAR(128);
    IF @json IS NULL OR @json = '' RETURN '1=0';
    SET @json = REPLACE(REPLACE(@json, '[', ''), ']', '');
    
    DECLARE col_cursor CURSOR FOR
        SELECT c.name, ty.name FROM sys.columns c
        INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
        WHERE c.object_id = OBJECT_ID(@table)
          AND ty.name NOT IN ('text', 'ntext', 'image')
        ORDER BY c.column_id;
    
    OPEN col_cursor;
    FETCH NEXT FROM col_cursor INTO @col, @dtype;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        SET @val = JSON_VALUE(@json, '$.' + @col);
        IF @val IS NOT NULL SET @val = RTRIM(@val);
        
        IF @val IS NOT NULL
        BEGIN
            SET @result = @result + @sep + QUOTENAME(@col) + ' = ';
            IF @dtype IN ('int','bigint','smallint','tinyint')
                SET @result = @result + @val;
            ELSE IF @dtype IN ('decimal','numeric','money','smallmoney','float','real')
                SET @result = @result + @val;
            ELSE IF @dtype IN ('bit')
                SET @result = @result + CASE WHEN @val = 'true' THEN '1' WHEN @val = 'false' THEN '0' ELSE @val END;
            ELSE
                SET @result = @result + '''' + REPLACE(@val, '''', '''''') + '''';
            SET @sep = ' AND ';
        END
        FETCH NEXT FROM col_cursor INTO @col, @dtype;
    END
    CLOSE col_cursor;
    DEALLOCATE col_cursor;
    IF @result = '' SET @result = '1=1';
    RETURN @result;
END
GO

REVERT;
GO
