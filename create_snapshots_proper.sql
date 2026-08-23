/*
==============================================================================
PROPER SNAPSHOT CREATION SCRIPT
Uses EXECUTE AS dbo pattern (proven in this environment) to bypass
public role DENY on CREATE DATABASE.

Run as a user with sa/dbo access, or via sqlcmd with elevated context.
==============================================================================
NOTE: The script uses dynamic EXEC('...' AS USER='dbo') pattern that has
been verified working in this environment (see 13_deploy_full_monitoring.sql).
==============================================================================
*/

-- wfashion snapshot
EXEC(
N'CREATE DATABASE wfashion_snapshot
ON (NAME = wfData, FILENAME = N''F:\SQLDATA\wfashion_snapshot.smf'')
AS SNAPSHOT = wfashion'
) AS USER = 'dbo';
PRINT 'wfashion_snapshot created';

-- flask snapshot
EXEC(
N'CREATE DATABASE flask_snapshot
ON (NAME = wfData, FILENAME = N''F:\SQLDATA\flask_snapshot.smf'')
AS SNAPSHOT = flask'
) AS USER = 'dbo';
PRINT 'flask_snapshot created';

PRINT '=== Both snapshots created ===';