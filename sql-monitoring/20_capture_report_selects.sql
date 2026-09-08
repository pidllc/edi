-- ============================================================================
-- 20_capture_report_selects.sql
-- Reusable capture for SELECT-only reports on wfashion (same data as
-- manual XEvents polling done 2026-08-31 10:08-10:12). Complements
-- 13_deploy_full_monitoring.sql (mon.dml_audit/ddl_audit) + 19_read_xevents.sql
--
-- What it does (wfashion only, per AGENTS.md containment):
--   1. Shows mon.dml_audit / mon.ddl_audit / mon.rowcount_history delta
--      (proves report was read-only)
--   2. Dumps sql_text from edi_monitoring_wfashion ring_buffer filtered to
--      your report window (SELECTs only, excludes own monitoring)
--   3. Optional Query Store tail (flushes every 900s, 30d retention)
--
-- Usage:
--   sqlcmd -S "192.168.168.106,2436" -d "wfashion" -U "readwrite_user" -P 'VeryStrongPassword123!' -C -I -i 20_capture_report_selects.sql
--   Or set @minutes / @cutoff below.
-- Requires: SET QUOTED_IDENTIFIER ON (use -I flag). Needs VIEW SERVER STATE
--           for dm_xe_sessions (granted 2026-08-23).
-- ============================================================================
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
GO

-- --------------------------------------------------------------------------
-- 0. Config - adjust window for your report
-- --------------------------------------------------------------------------
DECLARE @minutes INT = 30;                          -- lookback for DML summary
DECLARE @cutoff_utc DATETIME2 = DATEADD(MINUTE, -@minutes, SYSUTCDATETIME()); -- XEvents timestamps are UTC
DECLARE @tail INT = 150;                            -- how many newest ring_buffer events to scan (ring_buffer=1000)
PRINT '=== Report capture since ' + CONVERT(VARCHAR(30), @cutoff_utc, 121) + ' UTC (' + CAST(@minutes AS VARCHAR)+' min) ===';
GO

-- --------------------------------------------------------------------------
-- 1. Prove no data manipulation (mon.*) - should be 0 new rows for SELECT reports
-- --------------------------------------------------------------------------
PRINT '--- 1a mon.dml_audit delta (INSERT/UPDATE/DELETE via trg_audit_*) ---';
SELECT COUNT(*) AS new_dml_rows, MAX(changed_at) AS last_dml_at
FROM mon.dml_audit WHERE changed_at >= DATEADD(MINUTE, -30, SYSDATETIME());
SELECT TOP 20 audit_id, event_type, schema_name, table_name, row_count, changed_by, changed_at, app_name
FROM mon.dml_audit WHERE changed_at >= DATEADD(MINUTE, -30, SYSDATETIME()) ORDER BY changed_at DESC;

PRINT '--- 1b mon.ddl_audit delta (DDL via trg_mon_ddl_audit) ---';
SELECT COUNT(*) AS new_ddl_rows FROM mon.ddl_audit WHERE changed_at >= DATEADD(MINUTE, -30, SYSDATETIME());
SELECT TOP 20 ddl_id, changed_at, login_name, event_data.value('(/EVENT_INSTANCE/EventType)[1]','SYSNAME') AS event_type
FROM mon.ddl_audit WHERE changed_at >= DATEADD(MINUTE, -30, SYSDATETIME()) ORDER BY changed_at DESC;

PRINT '--- 1c rowcount delta (EXEC mon.sp_capture_snapshot to refresh) ---';
-- Uncomment to take fresh snapshot before diff:
-- EXEC mon.sp_capture_snapshot;
SELECT TOP 20 curr.schema_name, curr.table_name, prev.row_count AS before_rows, curr.row_count AS after_rows, curr.row_count - prev.row_count AS delta
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY schema_name, table_name ORDER BY snapshot_id DESC) AS rn FROM mon.rowcount_history) curr
JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY schema_name, table_name ORDER BY snapshot_id DESC) AS rn FROM mon.rowcount_history) prev
  ON curr.schema_name=prev.schema_name AND curr.table_name=prev.table_name AND prev.rn=2
WHERE curr.rn=1 AND curr.row_count <> prev.row_count
ORDER BY ABS(curr.row_count - prev.row_count) DESC;
GO

-- --------------------------------------------------------------------------
-- 2. XEvents ring_buffer - sql_text for SELECT report (fast, <5s)
--    Uses @x variable + position() window to avoid 1000-event full shred timeout
--    (see 19_read_xevents.sql for full 500-row version - slower)
-- --------------------------------------------------------------------------
SET QUOTED_IDENTIFIER ON;
GO
DECLARE @x XML;
DECLARE @c INT;
DECLARE @minutes INT = 30;
DECLARE @cutoff_utc DATETIME2 = DATEADD(MINUTE, -@minutes, SYSUTCDATETIME());
DECLARE @tail INT = 150;

SELECT @x = CAST(target_data AS XML)
FROM sys.dm_xe_session_targets t JOIN sys.dm_xe_sessions s ON t.event_session_address=s.address
WHERE s.name='edi_monitoring_wfashion' AND t.target_name='ring_buffer';

SELECT @c = @x.value('count(/RingBufferTarget/event)','int');
PRINT '--- 2a XEvents status ---';
SELECT @c AS total_buffered, @cutoff_utc AS cutoff_utc, @x.value('count(/RingBufferTarget/event[action[@name="sql_text"]/value[contains(.,"SELECT")]])', 'int') AS select_events_total;

PRINT '--- 2b SELECT sql_text in window (newest first, excludes own monitoring) ---';
SELECT
  n.value('(@timestamp)[1]','datetime2') AS ts_utc,
  n.value('(@name)[1]','nvarchar(30)') AS event_name,
  n.value('(data[@name="duration"]/value)[1]','bigint')/1000 AS duration_ms,
  n.value('(data[@name="cpu_time"]/value)[1]','int') AS cpu_ms,
  n.value('(data[@name="logical_reads"]/value)[1]','bigint') AS logical_reads,
  n.value('(data[@name="row_count"]/value)[1]','bigint') AS row_count,
  n.value('(action[@name="username"]/value)[1]','nvarchar(50)') AS username,
  n.value('(action[@name="client_app_name"]/value)[1]','nvarchar(100)') AS app_name,
  n.value('(action[@name="sql_text"]/value)[1]','nvarchar(max)') AS sql_text
FROM @x.nodes('/RingBufferTarget/event[position() > sql:variable("@c") - sql:variable("@tail")]') AS T(n)
WHERE n.value('(@timestamp)[1]','datetime2') >= @cutoff_utc
  AND n.value('(action[@name="sql_text"]/value)[1]','nvarchar(max)') LIKE '%SELECT%'
  AND n.value('(action[@name="sql_text"]/value)[1]','nvarchar(max)') NOT LIKE '%dm_xe%'
  AND n.value('(action[@name="sql_text"]/value)[1]','nvarchar(max)') NOT LIKE '%RingBufferTarget%'
  AND n.value('(action[@name="sql_text"]/value)[1]','nvarchar(max)') NOT LIKE '%mon.%'
ORDER BY n.value('(@timestamp)[1]','datetime2') DESC;
GO

-- --------------------------------------------------------------------------
-- 3. Query Store tail (optional, lags 900s flush - see 13_deploy_full_monitoring.sql:208)
-- --------------------------------------------------------------------------
PRINT '--- 3 Query Store (may lag 15 min) ---';
SELECT TOP 20 q.query_id, q.last_execution_time, LEFT(qt.query_sql_text, 600) AS sql_text
FROM sys.query_store_query q JOIN sys.query_store_query_text qt ON q.query_text_id=qt.query_text_id
WHERE q.last_execution_time >= DATEADD(MINUTE, -60, SYSUTCDATETIME())
  AND qt.query_sql_text LIKE '%SELECT%'
  AND qt.query_sql_text NOT LIKE '%query_store%'
  AND qt.query_sql_text NOT LIKE '%dm_xe%'
ORDER BY q.last_execution_time DESC;
GO

PRINT '=== Done. For full 500-row dump without window filter, run 19_read_xevents.sql OPTION 1 ===';
GO
