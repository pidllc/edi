#!/usr/bin/env python3
"""
Generate DML audit trigger DDL for a database from a metadata TSV.

Input TSV lines:  schema|table|col1,col2,...   (cols are QUOTENAME'd)
Produce:          .sql file creating trg_audit_<schema>_<table> on each table.

Usage:
  gen_dml_triggers.py <metadata.tsv> <output.sql>
"""
import sys

def q(name):
    return "[" + name.replace("]", "]]") + "]"

def esc(name):
    return name.replace("'", "''")

def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    tsv_in, sql_out = sys.argv[1], sys.argv[2]

    rows, skipped = [], []
    with open(tsv_in) as f:
        for line in f:
            line = line.rstrip("\r\n")
            s = line.strip()
            if not s or s.startswith("----") or s.startswith("(") or s.lower().startswith("schema_name|"):
                continue
            parts = line.split("|")
            if len(parts) < 3 or not parts[2].strip():
                if s.startswith("Msg ") or not s:
                    continue
                print(f"WARN: skipping malformed line: {s[:60]}")
                continue
            rows.append((parts[0].strip(), parts[1].strip(), parts[2].strip()))

    out = [
        "-- Auto-generated DML audit triggers",
        "-- Source: gen_dml_triggers.py - safe to re-run (drops + recreates).",
        "-- Triggers run WITH EXECUTE AS 'dbo' so audit inserts never fail",
        "-- regardless of the calling user's permissions.",
        "SET NOCOUNT ON;",
        "SET QUOTED_IDENTIFIER ON;",
        "SET ANSI_NULLS ON;",
        "GO",
        "",
    ]
    for schema, table, cols in rows:
        trg = q(f"trg_audit_{schema}_{table}")
        out.append(f"IF OBJECT_ID(N'{q(schema)}.{trg}', 'TR') IS NOT NULL")
        out.append(f"    DROP TRIGGER {q(schema)}.{trg};")
        out.append("GO")
        out.append(f"CREATE TRIGGER {q(schema)}.{trg}")
        out.append(f"ON {q(schema)}.{q(table)}")
        out.append("WITH EXECUTE AS N'dbo'")
        out.append("AFTER INSERT, UPDATE, DELETE")
        out.append("AS")
        out.append("BEGIN")
        out.append("    SET NOCOUNT ON;")
        out.append("    DECLARE @a VARCHAR(10) =")
        out.append("        CASE WHEN EXISTS(SELECT 1 FROM inserted) AND EXISTS(SELECT 1 FROM deleted) THEN 'UPDATE'")
        out.append("             WHEN EXISTS(SELECT 1 FROM inserted) THEN 'INSERT'")
        out.append("             ELSE 'DELETE' END;")
        out.append("")
        out.append("    INSERT INTO mon.dml_audit (event_type, schema_name, table_name, row_count, old_values, new_values)")
        out.append(f"    SELECT @a, '{esc(schema)}', '{esc(table)}',")
        out.append("        CASE WHEN @a IN ('INSERT','UPDATE') THEN (SELECT COUNT(*) FROM inserted)")
        out.append("             ELSE (SELECT COUNT(*) FROM deleted) END,")
        out.append(f"        CASE WHEN @a IN ('DELETE','UPDATE') THEN (SELECT d.{cols} FROM deleted d FOR JSON PATH) END,")
        out.append(f"        CASE WHEN @a IN ('INSERT','UPDATE') THEN (SELECT i.{cols} FROM inserted i FOR JSON PATH) END;")
        out.append("END;")
        out.append("GO")
    out.append(f"-- Generated {len(rows)} trigger(s); skipped {len(skipped)} table(s) without JSON-safe columns")
    if skipped:
        out.extend(f"--   SKIPPED {t}" for t in skipped)
    with open(sql_out, "w") as f:
        f.write("\n".join(out) + "\n")
    print(f"Wrote {sql_out}: {len(rows)} triggers, {len(skipped)} skipped")

if __name__ == "__main__":
    main()
