-- 12_capture_edi_snapshots.sql
-- Capture EDI table row counts for change detection
-- Run before/after expected EDI processing to detect changes
USE [wf125sR_82026];
GO

-- Snapshot of EDI table sizes
SELECT 
    t.name AS table_name,
    p.rows AS row_count,
    CAST(GETDATE() AS DATETIME2) AS snapshot_time
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
WHERE t.name LIKE 'edi%'
ORDER BY t.name;
GO

-- Compare with previous snapshot (if #edi_baseline exists)
IF OBJECT_ID('tempdb..#edi_baseline') IS NOT NULL
BEGIN
    SELECT 
        b.table_name,
        b.row_count AS previous_count,
        curr.row_count AS current_count,
        curr.row_count - b.row_count AS row_change,
        CASE 
            WHEN curr.row_count > b.row_count THEN 'INSERTS detected'
            WHEN curr.row_count < b.row_count THEN 'DELETES detected'
            ELSE 'No change'
        END AS change_type
    FROM #edi_baseline b
    INNER JOIN (
        SELECT t.name AS table_name, p.rows AS row_count
        FROM sys.tables t
        INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
        WHERE t.name LIKE 'edi%'
    ) curr ON b.table_name = curr.table_name
    WHERE curr.row_count != b.row_count
    ORDER BY ABS(curr.row_count - b.row_count) DESC;
END
ELSE
    PRINT 'No previous baseline found. Run this query again to capture one.';
GO

-- Save current state as new baseline
IF OBJECT_ID('tempdb..#edi_baseline') IS NOT NULL
    DROP TABLE #edi_baseline;

SELECT t.name AS table_name, p.rows AS row_count, GETDATE() AS captured_at
INTO #edi_baseline
FROM sys.tables t
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
WHERE t.name LIKE 'edi%';

SELECT 'Baseline captured' AS status, COUNT(*) AS tables_tracked FROM #edi_baseline;
GO
