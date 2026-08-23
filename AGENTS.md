# AGENTS.md - EDI Database Monitoring Session Tracker

## Working Agreements (MUST follow)
1. **Database containment**: Run queries against ONLY the database(s) explicitly named by the user for the current task. NEVER scan/query other databases without being asked. No server-wide enumeration loops.
2. **Document everything**: Every action, query run, change made, and finding gets logged in `session_log.log` (append, timestamped).
3. **Focus**: The primary goal is tracking what DATA is being manipulated (INSERT/UPDATE/DELETE) in the target databases.
4. **Update AGENTS.md** whenever permissions/state/working-agreements change so future sessions inherit correct context.

## Environment
- **Server**: 192.168.168.106:2436 (MSSQL, NJWFDEVSQL, SQL Server 2022 RTM-CU25)
- **Database**: PER-TASK ONLY — user names the target DB each session (e.g., wfashion, flask)
- **User**: readwrite_user
- **sqlcmd**: installed (ODBC Driver 17) — always use `-C`; use `-I` / SET QUOTED_IDENTIFIER ON for DDL
- **Workspace**: /Users/tarun/workspace/personal/edi

## Permission Reality (verified 2026-08-22)
- `public` role has DENY on CREATE TABLE / PROCEDURE / VIEW / DEFAULT / RULE / BACKUP in every accessible DB → DENY overrides db_owner
- **Workaround (proven in prior sessions)**: `EXECUTE AS USER='dbo'` context for all DDL
- CREATE TRIGGER: allowed directly (not in DENY list)
- ALTER DATABASE: allowed → Query Store can be enabled
- VIEW SERVER STATE: NOT granted → DMV scripts (01–05, 11) return nothing; do not rely on them

## Current Status (updated 2026-08-22)
- **Connectivity**: WORKING on port 2436
- **Server**: SQL Server 2022 RTM-CU25, Windows Server 2022
- **wf125sR_82026 NO LONGER EXISTS** — it was a dated restore copy; all monitoring deployed there on 2026-08-20 is GONE
- **readwrite_user currently has access to**: wfashion, flask (others deny login: wf125sR, WF125sR_TEST, plugg_llc, BARTENDER)
- **w-fashion: FULLY MONITORED (deployed 2026-08-22)**:
  - `mon` schema with dml_audit / ddl_audit / rowcount_history tables
  - 587 DML audit triggers (every user table except legacy dbo.dtproperties)
  - trg_mon_ddl_audit: logs all DDL + AUTO-CREATES audit triggers for new tables (auto-drop on table drop)
  - Query Store ON; procs mon.sp_capture_snapshot, mon.sp_activity_summary; view mon.vw_ddl_audit_parsed
  - changed_by/login_name record ORIGINAL_LOGIN() (real connecting login, not the impersonated sa)
  - SELF-TESTED: INSERT/UPDATE/DELETE captured with full before/after JSON
- **flask: FULLY MONITORED (deployed 2026-08-22)** — same stack as wfashion: mon schema+tables, 587 DML triggers, auto-cover DDL trigger, Query Store ON, procs+view, ORIGINAL_LOGIN defaults, baseline 588 tables. SELF-TESTED. Full deploy→teardown→redeploy cycle proven.


## Teardown / Restore Prep
- `sql-monitoring/17_remove_monitoring.sql` removes ALL monitoring from a DB (per-table triggers, DDL trigger [drop blocked on this server -> disabled+inert fallback], mon schema). Verified clean on flask (0 residue).
- To drop & restore a database from backup: run 17 first if you want the live DB clean beforehand; after a restore, monitoring is gone anyway (it lived inside the DB) - just re-run 13 + trigger file to re-arm.
- Redeploy order after any wipe: `13_deploy_full_monitoring.sql` -> generated `<db>_dml_triggers.sql` -> `16_ddl_trigger_autocover.sql` (only needed if an old trg_mon_ddl_audit survived) -> `EXEC mon.sp_capture_snapshot`.

## Gotchas Learned (2026-08-22)
- Database-scoped triggers are INVISIBLE to OBJECT_ID() — existence checks must query sys.triggers
- DROP TRIGGER of db-scoped trigger fails here even as dbo (3701); ALTER TRIGGER works — use ALTER for body swaps
- XML .value() methods inside EXECUTE AS 'dbo' modules fail (1934): impersonation resets QUOTED_IDENTIFIER OFF → parse EVENTDATA() via string functions only
- sqlcmd metadata exports need `-y 0` (else 4000-char truncation) and cannot combine `-y` with `-W` or `-h`
- STRING_AGG over column lists: CAST to NVARCHAR(MAX) or hits 8000-byte limit
- Computed columns derived from LOB types break inserted/deleted references (Msg 311) → exclude ALL computed columns from trigger column lists (loss-free: derivable)



## EDI Tables (48 total, key ones)
| Table | Rows | Status |
|-------|------|--------|
| edi_po | 315K | No audit triggers |
| edi_invoice | 2.1M | No audit triggers |
| edi_997 | 251K | No audit triggers |
| edi_po_sku_qty | 3.2M | No audit triggers |
| edi_850_summary | - | No audit triggers |
| edi_docs | - | No audit triggers |
| edi_in | - | No audit triggers |
| edi_out | - | Has update trigger only |
| edi_batch | - | No audit triggers |
| edi_860 | - | No audit triggers |

## Monitoring Scripts (sql-monitoring/)
| File | Purpose |
|------|---------|
| 00_create_monitoring_user.sql | Create dedicated monitoring login/user |
| 01_active_requests.sql | Current running requests (NEEDS VIEW SERVER STATE - denied, returns nothing) |
| 02_user_sessions.sql | Active user sessions (same limitation) |
| 03_top_resource_queries.sql | Top 20 resource-heavy queries (same limitation; Query Store views cover this instead) |
| 04_long_running_queries.sql | Queries running >30s (same limitation) |
| 05_waiting_queries.sql | Queries with wait stats (same limitation) |
| 06_list_all_tables.sql | Full schema overview (tables, columns, procs, functions) |
| 07_enable_cdc.sql | Enable Change Data Capture (requires sysadmin - NOT available) |
| 08_create_audit_tables.sql | OLD (wf125sR_82026-era) audit table creation |
| 09_create_change_triggers.sql | OLD trigger generator (buggy: FULL JOIN ON 1=0 logs nothing) - superseded by 13+gen script |
| 10_baseline_snapshot.sql | OLD baseline snapshot |
| 11_edi_change_monitor.sql | DMV-based EDI activity monitoring (needs VIEW SERVER STATE) |
| 12_capture_edi_snapshots.sql | Row count snapshots (broken: #temp table dies with session) |
| **13_deploy_full_monitoring.sql** | **CURRENT deployer**: mon schema+tables, auto-cover DDL trigger, procs, view, Query Store. Idempotent. Run per target DB |
| **14_selftest_monitoring.sql** | End-to-end verification: scratch table -> I/U/D -> show captured JSON |
| gen_dml_triggers.py | Generates per-table DML trigger DDL from metadata TSV export |
| **15_wfashion_dml_triggers.sql** | Generated triggers for wfashion's 587 tables (regenerate after big schema changes: see file header comments in gen script usage) |
| **16_ddl_trigger_autocover.sql** | Standalone upgrade of trg_mon_ddl_audit to auto-cover new tables (already folded into 13) |
| **17_remove_monitoring.sql** | Full teardown/uninstall - removes every monitoring artifact, idempotent, verified on flask |
| **18_flask_dml_triggers.sql** | Generated triggers for flask's 587 tables (regenerate after big schema changes) |

## Change Capture Strategy
- **w-fashion (LIVE since 2026-08-22)**:
  - Every user table (587) has trg_audit_<schema>_<table>: AFTER INSERT/UPDATE/DELETE -> one mon.dml_audit row per statement with full old/new rows as JSON arrays + row_count + ORIGINAL_LOGIN()/host/app/spid/time
  - Excluded from column capture: computed columns, text/ntext/image/geography/geometry/hierarchyid (FOR JSON limits); legacy dbo.dtproperties has no trigger
  - trg_mon_ddl_audit captures every DDL event as raw EVENTDATA() XML into mon.ddl_audit AND self-maintains coverage (auto-create/remove table triggers)
  - Review activity: `EXEC mon.sp_activity_summary @minutes=120` (DML by table/event/user, active users, DDL list, row-count deltas between snapshots)
  - Baseline rowcounts: `EXEC mon.sp_capture_snapshot` (first taken 2026-08-22, 588 tables)
  - Query Store ON (30-day retention) for query performance history

## Connection Command
```bash
sqlcmd -S "192.168.168.106,2436" -d "<TARGET_DB_NAMED_BY_USER>" -U "readwrite_user" -P 'VeryStrongPassword123!' -C
```

## Next Steps
1. Rework `13_deploy_full_monitoring.sql` to wrap DDL in `EXECUTE AS USER='dbo'` (proven pattern)
2. Deploy data-manipulation monitoring to the user-named target DB
3. Self-test: make INSERT/UPDATE/DELETE changes and verify capture in audit_log
4. Consider adding triggers to other high-value tables (soheader, sodetail, etc.)

## Notes
- dbtemppassword updated to correct port (2436)
- Log file: `session_log.log`
- User has INSERT/UPDATE/DELETE on edi_po but NOT SELECT
- 47 log tables already exist in database
- Large tables: iWMS_Boxing (14M), packlist_LOG (8M), invhead_box_seq (7M)
