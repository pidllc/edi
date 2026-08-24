-- 06_list_all_tables.sql
-- Get complete database schema overview
USE [wf125sR_82026];
GO

-- All user tables
SELECT 
    s.name AS schema_name,
    t.name AS table_name,
    t.create_date,
    t.modify_date,
    p.rows AS row_count
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.partitions p ON t.object_id = p.object_id AND p.index_id IN (0,1)
ORDER BY s.name, t.name;
GO

-- All columns with types
SELECT 
    s.name AS schema_name,
    t.name AS table_name,
    c.name AS column_name,
    ty.name AS data_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable,
    c.is_identity
FROM sys.columns c
INNER JOIN sys.tables t ON c.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id
ORDER BY s.name, t.name, c.column_id;
GO

-- All stored procedures
SELECT 
    s.name AS schema_name,
    p.name AS procedure_name,
    p.create_date,
    p.modify_date
FROM sys.procedures p
INNER JOIN sys.schemas s ON p.schema_id = s.schema_id
ORDER BY s.name, p.name;
GO

-- All functions
SELECT 
    s.name AS schema_name,
    o.name AS function_name,
    o.type_desc,
    o.create_date,
    o.modify_date
FROM sys.objects o
INNER JOIN sys.schemas s ON o.schema_id = s.schema_id
WHERE o.type IN ('FN', 'IF', 'TF')  -- Scalar, Inline, Table-valued
ORDER BY s.name, o.name;
GO
