-- ============================================================
-- droprestoredb.sql - Drop and restore database
-- Usage with sqlcmd:
--   sqlcmd -S "server,port" -d "master" -U "user" -P "pass" -C \
--     -i droprestoredb.sql \
--     -v DBNAME="wfashion" BACKUPFILE="F:\SQLBACKUP\82026.bak"
-- ============================================================

-- Step 1: Declare variables from sqlcmd parameters
DECLARE @DBNAME NVARCHAR(50) = '$(DBNAME)';
DECLARE @BACKUPFILE NVARCHAR(500) = '$(BACKUPFILE)';
DECLARE @SNAPNAME NVARCHAR(50);
DECLARE @DBFILEPATH NVARCHAR(200);
DECLARE @LOGFILEPATH NVARCHAR(200);

-- Derived values
SET @SNAPNAME = @DBNAME + '_snapshot';
SET @DBFILEPATH = 'F:\SQLDATA\' + @DBNAME + '.mdf';
SET @LOGFILEPATH = 'F:\SQLDATA\' + @DBNAME + '_log.ldf';

PRINT '=== Dropping and restoring: ' + @DBNAME + ' ===';
PRINT 'Backup: ' + @BACKUPFILE;

------------------------------------------------------------------
-- Step 0: Drop any existing snapshots
------------------------------------------------------------------
DECLARE @DropSnapSQL NVARCHAR(MAX);
SET @DropSnapSQL = 'DROP DATABASE IF EXISTS [' + @SNAPNAME + '];';
EXEC sp_executesql @DropSnapSQL;
PRINT 'Step 0: Snapshots dropped';

------------------------------------------------------------------
-- Step 1: Drop the database
------------------------------------------------------------------
DECLARE @DropSQL NVARCHAR(MAX);
SET @DropSQL = 'DROP DATABASE IF EXISTS [' + @DBNAME + '];';
EXEC sp_executesql @DropSQL;
PRINT 'Step 1: Database dropped';

------------------------------------------------------------------
-- Step 2: Restore from backup
------------------------------------------------------------------
DECLARE @RestoreSQL NVARCHAR(MAX);
SET @RestoreSQL = '
RESTORE DATABASE [' + @DBNAME + ']
FROM DISK = ''' + @BACKUPFILE + '''
WITH 
    MOVE ''wfData'' TO ''' + @DBFILEPATH + ''',
    MOVE ''wf_log'' TO ''' + @LOGFILEPATH + ''',
    REPLACE,
    STATS = 10;';
EXEC sp_executesql @RestoreSQL;
PRINT 'Step 2: Database restored';

------------------------------------------------------------------
-- Step 3: Create users and set permissions
------------------------------------------------------------------
DECLARE @UserSQL NVARCHAR(MAX);
SET @UserSQL = '
USE [' + @DBNAME + '];

IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = ''readwrite_user'')
BEGIN
    CREATE USER [readwrite_user] FOR LOGIN [readwrite_user];
END
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = ''readonly_user'')
BEGIN
    CREATE USER [readonly_user] FOR LOGIN [readonly_user];
END

ALTER ROLE db_owner ADD MEMBER [readwrite_user];
ALTER ROLE db_datareader ADD MEMBER [readonly_user];

UPDATE [dbo].[wfuser] 
SET [password] = ''' + @DBNAME + ''' 
WHERE [name] = ''tarun'';';
EXEC sp_executesql @UserSQL;
PRINT 'Step 3: Users configured';

PRINT '=== Restore complete: ' + @DBNAME + ' ===';
GO
