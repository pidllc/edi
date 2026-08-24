-- 11_edi_change_monitor.sql
-- Monitor EDI table activity via DMVs (no trigger/CDC needed)
-- Run periodically to detect changes
USE [wf125sR_82026];
GO

-- 1. Current activity on EDI tables
SELECT 
    r.session_id,
    r.status,
    r.command,
    DB_NAME(r.database_id) AS database_name,
    OBJECT_NAME(r.object_id) AS object_name,
    r.wait_type,
    r.wait_time,
    r.cpu_time,
    r.total_elapsed_time,
    t.text AS sql_text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.database_id = DB_ID()
    AND OBJECT_NAME(r.object_id) LIKE 'edi%'
    AND r.session_id > 50
ORDER BY r.total_elapsed_time DESC;
GO

-- 2. Recent writes to EDI tables (from DMVs - only while session active)
SELECT 
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    c.client_net_address,
    s.last_request_start_time,
    s.last_request_end_time
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_connections c ON s.session_id = c.session_id
WHERE s.database_id = DB_ID()
    AND s.is_user_process = 1
ORDER BY s.last_request_start_time DESC;
GO

-- 3. Top queries touching EDI tables (plan cache)
SELECT TOP 20
    qs.execution_count,
    qs.total_elapsed_time / qs.execution_count AS avg_elapsed_ms,
    qs.total_logical_reads / qs.execution_count AS avg_reads,
    qs.total_worker_time / qs.execution_count AS avg_cpu,
    OBJECT_NAME(qt.objectid) AS object_name,
    SUBSTRING(qt.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(qt.text)
            ELSE qs.statement_end_offset
        END - qs.statement_start_offset)/2)+1) AS query_text
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
WHERE qt.dbid = DB_ID()
    AND qt.text LIKE '%edi%'
ORDER BY qs.total_elapsed_time / qs.execution_count DESC;
GO

-- 4. Index activity (recent inserts/updates/deletes estimated)
SELECT 
    OBJECT_NAME(s.object_id) AS table_name,
    i.name AS index_name,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates,
    s.last_user_seek,
    s.last_user_scan,
    s.last_user_update
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.database_id = DB_ID()
    AND OBJECT_NAME(s.object_id) LIKE 'edi%'
ORDER BY s.user_updates DESC;
GO
