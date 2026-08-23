-- 10_baseline_snapshot.sql
-- Capture current state as baseline for comparison
USE [wf125sR_82026];
GO

-- Table row counts
SELECT 
    s.name AS schema_name,
    t.name AS table_name,
    p.rows AS row_count
INTO #baseline_counts
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
ORDER BY s.name, t.name;

SELECT * FROM #baseline_counts;
GO

-- Record snapshot
INSERT INTO schema_snapshot (table_count, proc_count, function_count, details)
SELECT
    (SELECT COUNT(*) FROM sys.tables WHERE is_ms_shipped = 0),
    (SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0),
    (SELECT COUNT(*) FROM sys.objects WHERE type IN ('FN','IF','TF') AND is_ms_shipped = 0),
    (SELECT * FROM #baseline_counts FOR JSON AUTO);
GO

-- Recent activity summary
SELECT TOP 100
    event_type,
    table_name,
    COUNT(*) AS change_count,
    MIN(changed_at) AS first_change,
    MAX(changed_at) AS last_change
FROM audit_log
GROUP BY event_type, table_name
ORDER BY change_count DESC;
GO
