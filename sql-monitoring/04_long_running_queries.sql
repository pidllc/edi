SELECT 
    r.session_id,
    r.total_elapsed_time / 1000 AS elapsed_seconds,
    r.cpu_time,
    r.reads,
    t.text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.total_elapsed_time > 30000
    AND r.session_id > 50
ORDER BY r.total_elapsed_time DESC;