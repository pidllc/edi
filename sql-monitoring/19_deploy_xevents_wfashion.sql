-- ============================================================
-- Deploy Extended Events for wfashion
-- ============================================================

-- Drop if exists
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'edi_monitoring_wfashion')
BEGIN
    ALTER EVENT SESSION [edi_monitoring_wfashion] ON SERVER STATE = STOP;
    DROP EVENT SESSION [edi_monitoring_wfashion] ON SERVER;
END
GO

-- Create session
CREATE EVENT SESSION [edi_monitoring_wfashion] ON SERVER 
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.username,
        sqlserver.database_name
    )
    WHERE sqlserver.database_name = N'wfashion'
),
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.username,
        sqlserver.database_name
    )
    WHERE sqlserver.database_name = N'wfashion'
)
ADD TARGET package0.ring_buffer(
    SET max_memory = 102400
)
WITH (
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    STARTUP_STATE = ON
);
GO

-- Start
ALTER EVENT SESSION [edi_monitoring_wfashion] ON SERVER STATE = START;
GO

PRINT '=== [edi_monitoring_wfashion] session started ===';
