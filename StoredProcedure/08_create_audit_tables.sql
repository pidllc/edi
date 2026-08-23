-- 08_create_audit_tables.sql
-- Create audit trail tables for change tracking
USE [wf125sR_82026];
GO

-- Main audit log table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'audit_log')
BEGIN
    CREATE TABLE audit_log (
        audit_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        event_type VARCHAR(20) NOT NULL,  -- INSERT, UPDATE, DELETE
        table_name NVARCHAR(128) NOT NULL,
        record_id NVARCHAR(256),          -- PK value(s) as string
        old_values NVARCHAR(MAX),         -- JSON of changed columns (old)
        new_values NVARCHAR(MAX),         -- JSON of changed columns (new)
        changed_by NVARCHAR(128) DEFAULT SUSER_SNAME(),
        changed_at DATETIME2 DEFAULT SYSDATETIME(),
        app_name NVARCHAR(128) DEFAULT APP_NAME(),
        host_name NVARCHAR(128) DEFAULT HOST_NAME()
    );
    CREATE INDEX IX_audit_log_table ON audit_log(table_name, changed_at);
    CREATE INDEX IX_audit_log_time ON audit_log(changed_at);
    PRINT 'audit_log table created.';
END
ELSE
    PRINT 'audit_log table already exists.';
GO

-- EDI-specific audit (track EDI document changes)
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'edi_document_audit')
BEGIN
    CREATE TABLE edi_document_audit (
        audit_id BIGINT IDENTITY(1,1) PRIMARY KEY,
        document_type VARCHAR(10) NOT NULL,   -- 850, 855, 856, 997, etc.
        document_number NVARCHAR(50) NOT NULL,
        partner_id NVARCHAR(50),
        event_type VARCHAR(20) NOT NULL,
        old_status NVARCHAR(50),
        new_status NVARCHAR(50),
        details NVARCHAR(MAX),
        changed_at DATETIME2 DEFAULT SYSDATETIME(),
        changed_by NVARCHAR(128) DEFAULT SUSER_SNAME()
    );
    CREATE INDEX IX_edi_doc_audit_num ON edi_document_audit(document_number, document_type);
    PRINT 'edi_document_audit table created.';
END
ELSE
    PRINT 'edi_document_audit table already exists.';
GO

-- Schema snapshot table
IF NOT EXISTS (SELECT * FROM sys.tables WHERE name = 'schema_snapshot')
BEGIN
    CREATE TABLE schema_snapshot (
        snapshot_id INT IDENTITY(1,1) PRIMARY KEY,
        snapshot_date DATETIME2 DEFAULT SYSDATETIME(),
        table_count INT,
        proc_count INT,
        function_count INT,
        details NVARCHAR(MAX)  -- JSON summary
    );
    PRINT 'schema_snapshot table created.';
END
ELSE
    PRINT 'schema_snapshot table already exists.';
GO
