SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
-- Fast row counts for all user tables (no checksum) - for compare current state
-- Output: tbl cnt chk (chk=0)
DECLARE @sql NVARCHAR(MAX) = N'';
DECLARE @name NVARCHAR(256);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR 
  SELECT QUOTENAME(TABLE_SCHEMA) + '.' + QUOTENAME(TABLE_NAME) 
  FROM INFORMATION_SCHEMA.TABLES 
  WHERE TABLE_TYPE='BASE TABLE' AND TABLE_SCHEMA NOT IN ('mon')
  ORDER BY TABLE_SCHEMA, TABLE_NAME;
OPEN c;
FETCH NEXT FROM c INTO @name;
WHILE @@FETCH_STATUS=0
BEGIN
  IF @sql <> N'' SET @sql = @sql + N' UNION ALL ';
  SET @sql = @sql + N'SELECT ' + QUOTENAME(@name, '''') + N' AS tbl, COUNT_BIG(*) AS cnt, 0 AS chk FROM ' + @name;
  FETCH NEXT FROM c INTO @name;
END
CLOSE c; DEALLOCATE c;
EXEC sp_executesql @sql;
