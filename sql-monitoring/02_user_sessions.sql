SELECT 
    s.session_id,
    s.login_name,
    s.host_name,
    s.program_name,
    s.status,
    c.client_net_address,
    s.login_time,
    s.last_request_start_time
FROM sys.dm_exec_sessions s
LEFT JOIN sys.dm_exec_connections c 
    ON s.session_id = c.session_id
WHERE s.is_user_process = 1;