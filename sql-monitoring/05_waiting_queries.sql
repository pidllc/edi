SELECT 
    r.session_id,
    r.wait_type,
    r.wait_time,
    r.last_wait_type,
    t.text
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.wait_type IS NOT NULL
    AND r.session_id > 50
ORDER BY r.wait_time DESC;