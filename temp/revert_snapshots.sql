/*
==============================================================================
REVERT SNAPSHOT SCRIPT
Purpose: Revert wfashion and flask databases to their snapshots,
         undoing all data changes made after snapshot time.
         Monitoring triggers and schema are PRESERVED (they were created
         before the snapshot and persist in the database structure).

REQUIREMENT: Must run as database owner (sa) because readwrite_user has DENY
on database-level operations.

Execute as sa:   sqlcmd -S ... -U sa -P <sa_password> -C -i revert_snapshots.sql

==============================================================================
*/

-- 1. Revert wfashion from snapshot
RESTORE DATABASE wfashion
FROM DATABASE_SNAPSHOT = 'wfashion_snapshot';
PRINT 'wfashion reverted. Monitoring triggers preserved.';
GO

-- 2. Revert flask from snapshot
RESTORE DATABASE flask
FROM DATABASE_SNAPSHOT = 'flask_snapshot';
PRINT 'flask reverted. Monitoring triggers preserved.';
GO

PRINT '=== Snapshot reversion complete ===';

/*
==============================================================================
VERIFICATION QUERIES (run after revert):
==============================================================================
-- Confirm triggers still exist:
SELECT name, is_disabled
FROM sys.triggers
WHERE name LIKE 'trg_audit%';

-- Confirm mon schema exists:
SELECT SCHEMA_ID('mon');

-- Confirm Query Store status:
SELECT name, is_query_store_on
FROM sys.databases
WHERE name IN ('wfashion', 'flask');
==============================================================================
*/