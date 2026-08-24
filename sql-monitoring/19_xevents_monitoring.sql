-- ============================================================
-- Extended Events Monitoring for wfashion / flask
-- Captures: all SQL statements + stored procedure calls
-- Target: ring_buffer (server-level, survives DB restores)
-- ============================================================

-- Step 1: Drop session if it exists
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'edi_monitoring')
BEGIN
    ALTER EVENT SESSION [edi_monitoring] ON SERVER STATE = STOP;
    DROP EVENT SESSION [edi_monitoring] ON SERVER;
END
GO

-- Step 2: Create the session
CREATE EVENT SESSION [edi_monitoring] ON SERVER 

-- Capture all SQL statements (SELECT, INSERT, UPDATE, DELETE)
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.username,
        sqlserver.database_name
    )
    WHERE sqlserver.database_name = N'wfashion'  -- Change to 'flask' for flask
),

-- Capture stored procedure calls (RPC)
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.username,
        sqlserver.database_name
    )
    WHERE sqlserver.database_name = N'wfashion'  -- Change to 'flask' for flask
)

-- Target: ring_buffer (100MB, in-memory, fast)
ADD TARGET package0.ring_buffer(
    SET max_memory = (102400)  -- 100MB
)

-- Options
WITH (
    MAX_MEMORY = 102400,       -- 100MB buffer
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,  -- Drop events if full
    MAX_DISPATCH_LATENCY = 5 SECONDS,  -- Flush every 5s
    STARTUP_STATE = ON         -- Auto-start on server restart
);
GO

-- Step 3: Start the session
ALTER EVENT SESSION [edi_monitoring] ON SERVER STATE = START;
GO

-- Step 4: Verify it's running
SELECT 
    s.name AS session_name,
    t.target_name,
    CAST(t.target_data AS XML) AS target_data
FROM sys.dm_xe_session_targets t
JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
WHERE s.name = 'edi_monitoring';
GO

PRINT '=== Extended Events session [edi_monitoring] created and started ===';
PRINT 'To read captured data, run: 19_read_xevents.sql';
GO
