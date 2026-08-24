-- ============================================================
-- Read Extended Events Captured Data
-- Run this to see all SQL queries captured by the monitoring
-- ============================================================

-- ============================================================
-- OPTION 1: All captured events (most recent 500)
-- ============================================================
SELECT TOP 500
    event_data.value('(event/@timestamp)[1]', 'datetime2') AS [timestamp],
    event_data.value('(event/@name)[1]', 'nvarchar(50)') AS event_type,
    event_data.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_ms,
    event_data.value('(event/data[@name="cpu_time"]/value)[1]', 'int') AS cpu_ms,
    event_data.value('(event/data[@name="logical_reads"]/value)[1]', 'bigint') AS logical_reads,
    event_data.value('(event/data[@name="writes"]/value)[1]', 'bigint') AS writes,
    event_data.value('(event/data[@name="row_count"]/value)[1]', 'bigint') AS row_count,
    event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text,
    event_data.value('(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(max)') AS app_name,
    event_data.value('(event/action[@name="client_hostname"]/value)[1]', 'nvarchar(max)') AS hostname,
    event_data.value('(event/action[@name="username"]/value)[1]', 'nvarchar(max)') AS username,
    event_data.value('(event/action[@name="database_name"]/value)[1]', 'nvarchar(max)') AS database_name
FROM (
    SELECT CAST(target_data AS xml) AS target_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
    WHERE s.name = 'edi_monitoring_wfashion' AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('RingBufferTarget/event') AS XEvent(event_data)
ORDER BY event_data.value('(event/@timestamp)[1]', 'datetime2') DESC;
GO

-- ============================================================
-- OPTION 2: wfashion events only
-- ============================================================
SELECT TOP 500
    event_data.value('(event/@timestamp)[1]', 'datetime2') AS [timestamp],
    event_data.value('(event/@name)[1]', 'nvarchar(50)') AS event_type,
    event_data.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_ms,
    event_data.value('(event/data[@name="row_count"]/value)[1]', 'bigint') AS row_count,
    event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text,
    event_data.value('(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(max)') AS app_name,
    event_data.value('(event/action[@name="username"]/value)[1]', 'nvarchar(max)') AS username
FROM (
    SELECT CAST(target_data AS xml) AS target_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
    WHERE s.name = 'edi_monitoring_wfashion' AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('RingBufferTarget/event') AS XEvent(event_data)
ORDER BY event_data.value('(event/@timestamp)[1]', 'datetime2') DESC;
GO

-- ============================================================
-- OPTION 3: flask events only
-- ============================================================
SELECT TOP 500
    event_data.value('(event/@timestamp)[1]', 'datetime2') AS [timestamp],
    event_data.value('(event/@name)[1]', 'nvarchar(50)') AS event_type,
    event_data.value('(event/data[@name="duration"]/value)[1]', 'bigint') / 1000 AS duration_ms,
    event_data.value('(event/data[@name="row_count"]/value)[1]', 'bigint') AS row_count,
    event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text,
    event_data.value('(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(max)') AS app_name,
    event_data.value('(event/action[@name="username"]/value)[1]', 'nvarchar(max)') AS username
FROM (
    SELECT CAST(target_data AS xml) AS target_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
    WHERE s.name = 'edi_monitoring_flask' AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('RingBufferTarget/event') AS XEvent(event_data)
ORDER BY event_data.value('(event/@timestamp)[1]', 'datetime2') DESC;
GO

-- ============================================================
-- OPTION 4: Data modifications only (INSERT/UPDATE/DELETE)
-- ============================================================
SELECT TOP 500
    event_data.value('(event/@timestamp)[1]', 'datetime2') AS [timestamp],
    event_data.value('(event/@name)[1]', 'nvarchar(50)') AS event_type,
    event_data.value('(event/data[@name="row_count"]/value)[1]', 'bigint') AS row_count,
    event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') AS sql_text,
    event_data.value('(event/action[@name="client_app_name"]/value)[1]', 'nvarchar(max)') AS app_name,
    event_data.value('(event/action[@name="username"]/value)[1]', 'nvarchar(max)') AS username,
    event_data.value('(event/action[@name="database_name"]/value)[1]', 'nvarchar(max)') AS database_name
FROM (
    SELECT CAST(target_data AS xml) AS target_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
    WHERE s.name IN ('edi_monitoring_wfashion', 'edi_monitoring_flask') 
      AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('RingBufferTarget/event') AS XEvent(event_data)
WHERE event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') LIKE '%INSERT%'
   OR event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') LIKE '%UPDATE%'
   OR event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)') LIKE '%DELETE%'
ORDER BY event_data.value('(event/@timestamp)[1]', 'datetime2') DESC;
GO

-- ============================================================
-- OPTION 5: Summary by table (which tables are being accessed)
-- ============================================================
SELECT 
    event_data.value('(event/action[@name="database_name"]/value)[1]', 'nvarchar(max)') AS database_name,
    event_data.value('(event/@name)[1]', 'nvarchar(50)') AS event_type,
    SUBSTRING(
        event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)'),
        1, 200
    ) AS sql_preview,
    COUNT(*) AS event_count,
    SUM(event_data.value('(event/data[@name="logical_reads"]/value)[1]', 'bigint')) AS total_reads,
    SUM(event_data.value('(event/data[@name="row_count"]/value)[1]', 'bigint')) AS total_rows
FROM (
    SELECT CAST(target_data AS xml) AS target_data
    FROM sys.dm_xe_session_targets t
    JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
    WHERE s.name IN ('edi_monitoring_wfashion', 'edi_monitoring_flask') 
      AND t.target_name = 'ring_buffer'
) AS data
CROSS APPLY target_data.nodes('RingBufferTarget/event') AS XEvent(event_data)
GROUP BY 
    event_data.value('(event/action[@name="database_name"]/value)[1]', 'nvarchar(max)'),
    event_data.value('(event/@name)[1]', 'nvarchar(50)'),
    SUBSTRING(event_data.value('(event/action[@name="sql_text"]/value)[1]', 'nvarchar(max)'), 1, 200)
ORDER BY total_reads DESC;
GO

-- ============================================================
-- OPTION 6: Check session status
-- ============================================================
SELECT 
    s.name AS session_name,
    s.create_time,
    t.target_name,
    CAST(t.target_data AS XML).value('RingBufferTarget/@processed', 'bigint') AS events_processed,
    CAST(t.target_data AS XML).value('RingBufferTarget/@droppedCount', 'bigint') AS events_dropped
FROM sys.dm_xe_session_targets t
JOIN sys.dm_xe_sessions s ON t.event_session_address = s.address
WHERE s.name IN ('edi_monitoring_wfashion', 'edi_monitoring_flask')
ORDER BY s.name;
GO
