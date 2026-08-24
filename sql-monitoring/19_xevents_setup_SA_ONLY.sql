-- ============================================================
-- Extended Events Monitoring Setup (REQUIRES SA PERMISSIONS)
-- Run this as sysadmin on the SQL Server
-- Server: 192.168.168.106,2436 (NJWFDEVSQL)
-- ============================================================
-- This script creates two Extended Events sessions:
--   1. edi_monitoring_wfashion - captures all queries to wfashion
--   2. edi_monitoring_flask - captures all queries to flask
--
-- Targets: ring_buffer (in-memory, 100MB each)
-- Captures: SQL statements + stored procedure calls
-- Survives: Database restores (server-level object)
-- Auto-starts: On server restart
-- ============================================================

USE [master];
GO

-- ============================================================
-- PART 1: CREATE SESSIONS
-- ============================================================

--------------------------------------------------------------
-- Session 1: wfashion
--------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'edi_monitoring_wfashion')
BEGIN
    ALTER EVENT SESSION [edi_monitoring_wfashion] ON SERVER STATE = STOP;
    DROP EVENT SESSION [edi_monitoring_wfashion] ON SERVER;
    PRINT 'Dropped existing session: edi_monitoring_wfashion';
END
GO

CREATE EVENT SESSION [edi_monitoring_wfashion] ON SERVER 

-- Capture all SQL statements (SELECT, INSERT, UPDATE, DELETE, etc.)
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

-- Capture stored procedure calls (RPC events)
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

-- Target: ring_buffer (100MB in-memory)
ADD TARGET package0.ring_buffer(
    SET max_memory = 102400
)

-- Options
WITH (
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    STARTUP_STATE = ON
);
GO

PRINT 'Created session: edi_monitoring_wfashion';
GO

--------------------------------------------------------------
-- Session 2: flask
--------------------------------------------------------------
IF EXISTS (SELECT 1 FROM sys.server_event_sessions WHERE name = 'edi_monitoring_flask')
BEGIN
    ALTER EVENT SESSION [edi_monitoring_flask] ON SERVER STATE = STOP;
    DROP EVENT SESSION [edi_monitoring_flask] ON SERVER;
    PRINT 'Dropped existing session: edi_monitoring_flask';
END
GO

CREATE EVENT SESSION [edi_monitoring_flask] ON SERVER 

-- Capture all SQL statements (SELECT, INSERT, UPDATE, DELETE, etc.)
ADD EVENT sqlserver.sql_statement_completed(
    ACTION(
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.username,
        sqlserver.database_name
    )
    WHERE sqlserver.database_name = N'flask'
),

-- Capture stored procedure calls (RPC events)
ADD EVENT sqlserver.rpc_completed(
    ACTION(
        sqlserver.sql_text,
        sqlserver.client_app_name,
        sqlserver.client_hostname,
        sqlserver.username,
        sqlserver.database_name
    )
    WHERE sqlserver.database_name = N'flask'
)

-- Target: ring_buffer (100MB in-memory)
ADD TARGET package0.ring_buffer(
    SET max_memory = 102400
)

-- Options
WITH (
    EVENT_RETENTION_MODE = ALLOW_SINGLE_EVENT_LOSS,
    MAX_DISPATCH_LATENCY = 5 SECONDS,
    STARTUP_STATE = ON
);
GO

PRINT 'Created session: edi_monitoring_flask';
GO

-- ============================================================
-- PART 2: START SESSIONS
-- ============================================================

ALTER EVENT SESSION [edi_monitoring_wfashion] ON SERVER STATE = START;
GO
PRINT 'Started: edi_monitoring_wfashion';
GO

ALTER EVENT SESSION [edi_monitoring_flask] ON SERVER STATE = START;
GO
PRINT 'Started: edi_monitoring_flask';
GO

-- ============================================================
-- PART 3: VERIFY SESSIONS ARE RUNNING
-- ============================================================

SELECT 
    s.name AS session_name,
    s.create_time,
    t.target_name,
    CAST(t.target_data AS XML) AS target_data
FROM sys.dm_xe_session_targets t
JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
WHERE s.name IN ('edi_monitoring_wfashion', 'edi_monitoring_flask')
ORDER BY s.name;
GO

PRINT '============================================================';
PRINT 'Extended Events monitoring setup complete!';
PRINT 'Sessions: edi_monitoring_wfashion, edi_monitoring_flask';
PRINT 'Target: ring_buffer (100MB each)';
PRINT 'Auto-start: ON (survives server restarts)';
PRINT '============================================================';
GO
