/*
==============================================================================
CREATE SNAPSHOT SCRIPT
Purpose: Create full database snapshots of wfashion and flask before test changes.
         Snapshots preserve monitoring triggers and schema; only data changes
         made after snapshot time are lost on revert.

REQUIREMENT: Must run as database owner (sa) because readwrite_user has DENY
on CREATE DATABASE (public role DENY overrides db_owner).

Execute as sa:   sqlcmd -S ... -U sa -P <sa_password> -C -i create_snapshots.sql
OR use EXECUTE AS dbo if connected as sa user.

Snapshot files created on: F:\SQLDATA\ (same directory as source databases)
==============================================================================
*/

-- 1. wfashion snapshot
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'wfashion_snapshot')
BEGIN
    PRINT 'wfashion_snapshot already exists - skipping';
END
ELSE
BEGIN
    CREATE DATABASE wfashion_snapshot
    ON (NAME = wfData, FILENAME = N'F:\SQLDATA\wfashion_snapshot.smf')
    AS SNAPSHOT OF wfashion;
    PRINT 'wfashion_snapshot created OK';
END

-- 2. flask snapshot
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'flask_snapshot')
BEGIN
    PRINT 'flask_snapshot already exists - skipping';
END
ELSE
BEGIN
    CREATE DATABASE flask_snapshot
    ON (NAME = wfData, FILENAME = N'F:\SQLDATA\flask_snapshot.smf')
    AS SNAPSHOT OF flask;
    PRINT 'flask_snapshot created OK';
END

PRINT '=== Snapshot creation complete ===';

/*
==============================================================================
NEXT: Run revert_snapshots.sql to revert (preserves monitoring triggers)
==============================================================================
*/