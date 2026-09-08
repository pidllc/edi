#!/bin/bash
# Database comparison with baseline snapshot support
# Usage:
#   ./compare_dbs.sh --snapshot <db1> <db2>     Capture baseline snapshot
#   ./compare_dbs.sh <db1> <db2>                Compare using baseline (if exists)
#   ./compare_dbs.sh <db1> <db2> --no-baseline  Compare without baseline (counts + triggers only)
#
# Output: temp/reports/<runtime>/compare_<db1>_<db2>_<datetime>.txt (+ csv/ subdir)

set -euo pipefail

SERVER="192.168.168.106,2436"
USER="readwrite_user"
PASS='VeryStrongPassword123!'
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$REPO_ROOT/temp"

# Parse arguments
SNAPSHOT_MODE=false
NO_BASELINE=false
SUMMARY_ONLY=false
DB1=""
DB2=""

for arg in "$@"; do
  case "$arg" in
    --snapshot) SNAPSHOT_MODE=true ;;
    --no-baseline) NO_BASELINE=true ;;
    --summary-only) SUMMARY_ONLY=true ;;
    -*) echo "Unknown flag: $arg"; exit 1 ;;
    *)
      if [ -z "$DB1" ]; then DB1="$arg"
      elif [ -z "$DB2" ]; then DB2="$arg"
      fi
      ;;
  esac
done

DB1="${DB1:?Usage: $0 [--snapshot] <db1> <db2> [--no-baseline] [--summary-only]}"
DB2="${DB2:?Usage: $0 [--snapshot] <db1> <db2> [--no-baseline]}"

REPORT_DIR="$REPO_ROOT/temp/reports/${TIMESTAMP}"
mkdir -p "$REPORT_DIR"
REPORT="$REPORT_DIR/compare_${DB1}_${DB2}_${TIMESTAMP}.txt"
SNAPSHOT_DIR="$REPO_ROOT/temp"
SNAP1="$SNAPSHOT_DIR/snapshot_${DB1}.txt"
SNAP2="$SNAPSHOT_DIR/snapshot_${DB2}.txt"
CSV_DIR="$REPORT_DIR/csv"
mkdir -p "$CSV_DIR"
CSV_FILES_CREATED=()

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

log() { echo "$1" | tee -a "$REPORT"; }
run() { sqlcmd -S "$SERVER" -d "$1" -U "$USER" -P "$PASS" -C -Q "$2" -y 0 </dev/null 2>&1; }
runfile() { sqlcmd -S "$SERVER" -d "$1" -U "$USER" -P "$PASS" -C -i "$2" -y 0 </dev/null 2>&1; }

# --- CSV export helper ---
# Usage: export_csv <src_db> <query> <outfile> <header_csv>
# Tries bcp first (full NVARCHAR(MAX) support), falls back to sqlcmd.
export_csv() {
  local _src_db="$1"
  local _query="$2"
  local _outfile="$3"
  local _header="$4"
  echo "$_header" > "$_outfile"
  local _tmp="${_outfile}.tmp"
  # Try bcp (handles large columns, proper quoting via -c)
  if command -v bcp >/dev/null 2>&1; then
    if bcp "$_query" queryout "$_tmp" -S "$SERVER" -U "$USER" -P "$PASS" -c -t "," -r "\n" -C RAW >/dev/null 2>&1; then
      cat "$_tmp" >> "$_outfile"
      rm -f "$_tmp"
      CSV_FILES_CREATED+=("$_outfile")
      return 0
    fi
    rm -f "$_tmp"
  fi
  # Fallback: sqlcmd with -y 0 -s "," -h -1 (header suppressed, we already wrote it)
  sqlcmd -S "$SERVER" -d "$_src_db" -U "$USER" -P "$PASS" -C -s "," -y 0 -h -1 -Q "SET NOCOUNT ON; $_query" -o "$_tmp" 2>/dev/null || true
  # Filter sqlcmd artifacts: dashed separator lines, "rows affected", empty
  grep -v -E '^(--)' "$_tmp" 2>/dev/null | grep -v "rows affected" | grep -v "^$" | grep -v "^\s*$" >> "$_outfile" || true
  rm -f "$_tmp"
  CSV_FILES_CREATED+=("$_outfile")
}

parse_counts() {
  grep -E '^\[' | awk '{print $1, $2}'
}

parse_snapshot() {
  grep -E '^\[' | awk '{print $1, $2, $3}'
}

# Use 'dbo.' (unescaped dot matches any char, fine for this format)
dbo_count() {
  local cnt
  cnt=$(grep -c 'dbo.' "$1" 2>/dev/null) || true
  echo "${cnt:-0}"
}

# ============================================================
# SNAPSHOT MODE: capture baseline
# ============================================================
if [ "$SNAPSHOT_MODE" = true ]; then
  echo "Capturing baseline snapshots..."
  echo "  $DB1 -> $SNAP1"
  runfile "$DB1" "$SCRIPT_DIR/22_snapshot_checksums.sql" > "$SNAP1"
  echo "  $DB2 -> $SNAP2"
  runfile "$DB2" "$SCRIPT_DIR/22_snapshot_checksums.sql" > "$SNAP2"
  echo "Done. Run without --snapshot to compare against these baselines."
  exit 0
fi

# ============================================================
# COMPARE MODE
# ============================================================
log "================================================================"
log "DATABASE COMPARISON REPORT"
log "Date: $(date '+%Y-%m-%d %H:%M:%S')"
log "Databases: $DB1 vs $DB2"
log "Server: $SERVER"
log "Mode: $([ "$NO_BASELINE" = true ] && echo 'no-baseline' || echo 'baseline-aware')"
log "================================================================"
log ""

# --- Capture current state ---
runfile "$DB1" "$SCRIPT_DIR/22_snapshot_checksums.sql" > "$TMPDIR/cur1.txt"
runfile "$DB2" "$SCRIPT_DIR/22_snapshot_checksums.sql" > "$TMPDIR/cur2.txt"

# --- Load baselines if available ---
HAS_BASELINE=false
if [ "$NO_BASELINE" = false ] && [ -f "$SNAP1" ] && [ -f "$SNAP2" ]; then
  HAS_BASELINE=true
  log "--- BASELINE SNAPSHOTS ---"
  log "  $DB1 baseline: $SNAP1 ($(wc -l < "$SNAP1" | tr -d ' ') tables)"
  log "  $DB2 baseline: $SNAP2 ($(wc -l < "$SNAP2" | tr -d ' ') tables)"
  log ""
fi

# --- Table list comparison ---
log "--- TABLE LIST ---"
T1_COUNT=$(dbo_count "$TMPDIR/cur1.txt")
T2_COUNT=$(dbo_count "$TMPDIR/cur2.txt")
log "  $DB1: $T1_COUNT tables"
log "  $DB2: $T2_COUNT tables"

TABLES1=$(grep 'dbo.' "$TMPDIR/cur1.txt" | awk '{print $1}' | sort)
TABLES2=$(grep 'dbo.' "$TMPDIR/cur2.txt" | awk '{print $1}' | sort)
T_ONLY1=$(comm -23 <(echo "$TABLES1") <(echo "$TABLES2") || true)
T_ONLY2=$(comm -13 <(echo "$TABLES1") <(echo "$TABLES2") || true)
if [ -n "$T_ONLY1" ]; then
  log "  Only in $DB1:"
  echo "$T_ONLY1" | while IFS= read -r line; do log "    $line"; done
fi
if [ -n "$T_ONLY2" ]; then
  log "  Only in $DB2:"
  echo "$T_ONLY2" | while IFS= read -r line; do log "    $line"; done
fi
if [ -z "$T_ONLY1" ] && [ -z "$T_ONLY2" ]; then
  log "  Table lists: IDENTICAL"
fi
log ""

# --- Trigger list comparison ---
log "--- TRIGGER LIST ---"
run "$DB1" "SELECT name, parent_class_desc, is_disabled FROM sys.triggers WHERE is_ms_shipped=0 ORDER BY name" > "$TMPDIR/tr1.txt"
run "$DB2" "SELECT name, parent_class_desc, is_disabled FROM sys.triggers WHERE is_ms_shipped=0 ORDER BY name" > "$TMPDIR/tr2.txt"
if diff -q "$TMPDIR/tr1.txt" "$TMPDIR/tr2.txt" > /dev/null 2>&1; then
  log "  Trigger lists: IDENTICAL"
else
  log "  Trigger lists: DIFFERENT"
  diff "$TMPDIR/tr1.txt" "$TMPDIR/tr2.txt" | grep '^[<>]' | while IFS= read -r line; do log "  $line"; done
fi
log ""

# --- Load current state into temp files for processing ---
parse_snapshot < "$TMPDIR/cur1.txt" > "$TMPDIR/state1.txt"
parse_snapshot < "$TMPDIR/cur2.txt" > "$TMPDIR/state2.txt"

if [ "$HAS_BASELINE" = true ]; then
  parse_snapshot < "$SNAP1" > "$TMPDIR/base1.txt"
  parse_snapshot < "$SNAP2" > "$TMPDIR/base2.txt"
fi

# ============================================================
# CHANGE ANALYSIS
# ============================================================
log "================================================================"
log "CHANGE ANALYSIS"
log "================================================================"
log ""

CHANGES_FOUND=false

# --- New tables (exist now but not in baseline) ---
if [ "$HAS_BASELINE" = true ]; then
  NEW_IN_DB1=$(comm -23 <(awk '{print $1}' "$TMPDIR/state1.txt" | sort) <(awk '{print $1}' "$TMPDIR/base1.txt" | sort) || true)
  NEW_IN_DB2=$(comm -23 <(awk '{print $1}' "$TMPDIR/state2.txt" | sort) <(awk '{print $1}' "$TMPDIR/base2.txt" | sort) || true)
  DROPPED_FROM_DB1=$(comm -23 <(awk '{print $1}' "$TMPDIR/base1.txt" | sort) <(awk '{print $1}' "$TMPDIR/state1.txt" | sort) || true)
  DROPPED_FROM_DB2=$(comm -23 <(awk '{print $1}' "$TMPDIR/base2.txt" | sort) <(awk '{print $1}' "$TMPDIR/state2.txt" | sort) || true)

  if [ -n "$NEW_IN_DB1" ] || [ -n "$NEW_IN_DB2" ] || [ -n "$DROPPED_FROM_DB1" ] || [ -n "$DROPPED_FROM_DB2" ]; then
    CHANGES_FOUND=true
    log "--- SCHEMA CHANGES ---"
    if [ -n "$NEW_IN_DB1" ]; then
      log "  NEW tables in $DB1 (since baseline):"
      echo "$NEW_IN_DB1" | while IFS= read -r t; do log "    $t"; done
    fi
    if [ -n "$NEW_IN_DB2" ]; then
      log "  NEW tables in $DB2 (since baseline):"
      echo "$NEW_IN_DB2" | while IFS= read -r t; do log "    $t"; done
    fi
    if [ -n "$DROPPED_FROM_DB1" ]; then
      log "  DROPPED tables from $DB1 (since baseline):"
      echo "$DROPPED_FROM_DB1" | while IFS= read -r t; do log "    $t"; done
    fi
    if [ -n "$DROPPED_FROM_DB2" ]; then
      log "  DROPPED tables from $DB2 (since baseline):"
      echo "$DROPPED_FROM_DB2" | while IFS= read -r t; do log "    $t"; done
    fi
    log ""
  fi
fi

# --- Data changes per table ---
log "--- DATA CHANGES ---"

# Build lookup: for each table, compare current vs baseline (or vs other DB)
CHANGED_TABLES_FILE="$TMPDIR/changed_tables.txt"
> "$CHANGED_TABLES_FILE"

while IFS=' ' read -r tbl cnt chk; do
  [ -z "$tbl" ] && continue

  # Get current state for this table in db2
  c2_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state2.txt")
  c2_cnt=$(echo "$c2_line" | awk '{print $2}')
  c2_chk=$(echo "$c2_line" | awk '{print $3}')

  if [ "$HAS_BASELINE" = true ]; then
    # Compare db1 current vs db1 baseline
    b1_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/base1.txt")
    b1_cnt=$(echo "$b1_line" | awk '{print $2}')
    b1_chk=$(echo "$b1_line" | awk '{print $3}')

    # Compare db2 current vs db2 baseline
    b2_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/base2.txt")
    b2_cnt=$(echo "$b2_line" | awk '{print $2}')
    b2_chk=$(echo "$b2_line" | awk '{print $3}')

    DB1_CHANGED=false
    DB2_CHANGED=false

    if [ -n "$b1_chk" ] && [ "$b1_chk" != "0" ] && [ "$chk" != "$b1_chk" ]; then
      DB1_CHANGED=true
    elif [ -n "$b1_cnt" ] && [ "$cnt" != "$b1_cnt" ]; then
      DB1_CHANGED=true
    fi

    if [ -n "$b2_chk" ] && [ "$b2_chk" != "0" ] && [ "$c2_chk" != "$b2_chk" ]; then
      DB2_CHANGED=true
    elif [ -n "$b2_cnt" ] && [ "$c2_cnt" != "$b2_cnt" ]; then
      DB2_CHANGED=true
    fi

    if [ "$DB1_CHANGED" = true ] || [ "$DB2_CHANGED" = true ]; then
      CHANGES_FOUND=true
      echo "$tbl" >> "$CHANGED_TABLES_FILE"
      delta=$(( ${c2_cnt:-0} - ${cnt:-0} ))
      log ""
      log "  $tbl"
      if [ "$DB1_CHANGED" = true ]; then
        log "    $DB1: ${b1_cnt:-?} -> $cnt rows (baseline chk: ${b1_chk:-0}, current: $chk)"
      fi
      if [ "$DB2_CHANGED" = true ]; then
        log "    $DB2: ${b2_cnt:-?} -> $c2_cnt rows (baseline chk: ${b2_chk:-0}, current: $c2_chk)"
      fi
      [ "$delta" -ne 0 ] && log "    Delta ($DB1 vs $DB2): $delta"
    fi
  else
    # No baseline: just compare the two DBs directly
    if [ -n "$c2_cnt" ] && [ "$cnt" != "$c2_cnt" ]; then
      CHANGES_FOUND=true
      echo "$tbl" >> "$CHANGED_TABLES_FILE"
      delta=$((c2_cnt - cnt))
      log "  COUNT_DIFF: $tbl  $DB1=$cnt  $DB2=$c2_cnt  delta=$delta"
    elif [ -n "$c2_chk" ] && [ "$chk" != "0" ] && [ "$c2_chk" != "0" ] && [ "$chk" != "$c2_chk" ]; then
      CHANGES_FOUND=true
      echo "$tbl" >> "$CHANGED_TABLES_FILE"
      log "  CHECKSUM_DIFF: $tbl  $DB1=$chk  $DB2=$c2_chk (same row count: $cnt)"
    fi
  fi
done < "$TMPDIR/state1.txt"

if [ "$CHANGES_FOUND" = false ]; then
  log "  No changes detected."
fi
log ""

# --- Row-level detail for changed tables ---
if [ -s "$CHANGED_TABLES_FILE" ] && [ "$SUMMARY_ONLY" = false ]; then
  log "================================================================"
  log "ROW-LEVEL CHANGES (up to 100 per table - full diff in CSV if truncated)"
  log "================================================================"
  log "CSV output dir: $CSV_DIR"

  while IFS= read -r tbl; do
    [ -z "$tbl" ] && continue
    SCHEMA=$(echo "$tbl" | cut -d. -f1 | tr -d '[]')
    TNAME=$(echo "$tbl" | cut -d. -f2 | tr -d '[]')
    log ""
    log "  === $tbl ==="

    TBL_CNT=$(awk -v t="$tbl" '$1==t {print $2}' "$TMPDIR/state1.txt")
    LARGE_TABLE=false
    if [ "${TBL_CNT:-0}" -gt 500000 ]; then
      LARGE_TABLE=true
      log "  (large table: ${TBL_CNT} rows - interactive diff limited to 100, full export to CSV)"
    fi

    # Get PK columns
    PK_COLS=$(run "$DB1" "SELECT ku.COLUMN_NAME FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku ON tc.CONSTRAINT_NAME=ku.CONSTRAINT_NAME WHERE tc.TABLE_NAME='$TNAME' AND tc.TABLE_SCHEMA='$SCHEMA' AND tc.CONSTRAINT_TYPE IN ('PRIMARY KEY','UNIQUE') ORDER BY ku.ORDINAL_POSITION" | grep -v '^$' | grep -v 'COLUMN_NAME' | grep -v '^--' | grep -v 'rows affected' | grep -v '^(' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)

    if [ -z "$PK_COLS" ]; then
      log "  (no PK/UNIQUE constraint - row-level diff skipped, no CSV)"
      continue
    fi

    # Get all columns
    ALL_COLS=$(run "$DB1" "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME='$TNAME' AND TABLE_SCHEMA='$SCHEMA' ORDER BY ORDINAL_POSITION" | grep -v '^$' | grep -v 'COLUMN_NAME' | grep -v '^--' | grep -v 'rows affected' | grep -v '^(' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)

    # Build PK-only select for "only in" queries
    PKSelect=""
    while IFS= read -r col; do
      [ -z "$col" ] && continue
      if [ -n "$PKSelect" ]; then PKSelect="$PKSelect, "; fi
      PKSelect="${PKSelect}a.[$col]"
    done <<< "$PK_COLS"

    # Build full col list for CSV full-row exports (all columns)
    CSV_ALL_SELECT=""
    CSV_ALL_HEADER=""
    while IFS= read -r col; do
      [ -z "$col" ] && continue
      if [ -n "$CSV_ALL_SELECT" ]; then CSV_ALL_SELECT="$CSV_ALL_SELECT, "; CSV_ALL_HEADER="$CSV_ALL_HEADER,"; fi
      CSV_ALL_SELECT="${CSV_ALL_SELECT}a.[$col]"
      CSV_ALL_HEADER="${CSV_ALL_HEADER}$col"
    done <<< "$ALL_COLS"

    # Build full select for "column diff" queries (pairwise)
    ABCols=""
    while IFS= read -r col; do
      [ -z "$col" ] && continue
      if [ -n "$ABCols" ]; then ABCols="$ABCols, "; fi
      ABCols="${ABCols}a.[$col] AS [${col}_db1], b.[$col] AS [${col}_db2]"
    done <<< "$ALL_COLS"

    # Build PK join
    JOINCond=""
    while IFS= read -r col; do
      [ -z "$col" ] && continue
      if [ -n "$JOINCond" ]; then JOINCond="$JOINCond AND "; fi
      JOINCond="${JOINCond}a.[$col] = b.[$col]"
    done <<< "$PK_COLS"

    # Build diff condition (non-PK columns)
    DIFFCond=""
    while IFS= read -r col; do
      [ -z "$col" ] && continue
      if echo "$PK_COLS" | grep -qF "$col"; then continue; fi
      if [ -n "$DIFFCond" ]; then DIFFCond="$DIFFCond OR "; fi
      DIFFCond="${DIFFCond}ISNULL(CAST(a.[$col] AS NVARCHAR(MAX)), '') <> ISNULL(CAST(b.[$col] AS NVARCHAR(MAX)), '')"
    done <<< "$ALL_COLS"

    # Helper: sanitized table name for files
    SAFE_TBL="${SCHEMA}_${TNAME}"

    # Track counts for CSV decision
    R1_COUNT=0; R2_COUNT=0; RD_COUNT=0

    # Interactive TOP-100 is skipped for large tables (>500K) to avoid timeouts; CSV will hold full diff
    if [ "$LARGE_TABLE" = true ]; then
      log "  (large table - interactive TOP 100 skipped, CSV will contain full diff)"
      # R*_COUNT stay 0; NEED_CSV already true, counts will be derived via COUNT(*) in CSV section
    elif [ "$HAS_BASELINE" = true ]; then
      # --- Baseline-aware: show changes per DB ---

      # Rows only in current DB1 (not in DB2 by PK) - TOP 100 interactive
      R1=$(run "$DB1" "SET NOCOUNT ON; SELECT TOP 100 'NEW_IN_${DB1}' AS change_type, $PKSelect FROM [${DB1}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB2}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" || true)
      R1_COUNT=$(echo "$R1" | grep -c 'NEW_IN_' || true)
      if [ "$R1_COUNT" -gt 0 ]; then
        log "  >> New rows in $DB1 (not in $DB2, up to 100):"
        echo "$R1" | grep 'NEW_IN_' | head -100 | while IFS= read -r line; do log "    $line"; done
        [ "$R1_COUNT" -eq 100 ] && log "     (! truncated at 100 - full list in CSV)"
      fi

      # Rows only in current DB2 (not in DB1 by PK)
      R2=$(run "$DB2" "SET NOCOUNT ON; SELECT TOP 100 'NEW_IN_${DB2}' AS change_type, $PKSelect FROM [${DB2}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB1}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" || true)
      R2_COUNT=$(echo "$R2" | grep -c 'NEW_IN_' || true)
      if [ "$R2_COUNT" -gt 0 ]; then
        log "  >> New rows in $DB2 (not in $DB1, up to 100):"
        echo "$R2" | grep 'NEW_IN_' | head -100 | while IFS= read -r line; do log "    $line"; done
        [ "$R2_COUNT" -eq 100 ] && log "     (! truncated at 100 - full list in CSV)"
      fi

      # Modified rows (same PK, different data)
      if [ -n "$DIFFCond" ]; then
        RD=$(run "$DB1" "SET NOCOUNT ON; SELECT TOP 100 'MODIFIED' AS change_type, $ABCols FROM [${DB1}].[${SCHEMA}].[${TNAME}] a INNER JOIN [${DB2}].[${SCHEMA}].[${TNAME}] b ON $JOINCond WHERE $DIFFCond" || true)
        RD_COUNT=$(echo "$RD" | grep -c 'MODIFIED' || true)
        if [ "$RD_COUNT" -gt 0 ]; then
          log "  >> Modified rows (same PK, different data, up to 100):"
          echo "$RD" | grep 'MODIFIED' | head -100 | while IFS= read -r line; do log "    $line"; done
          [ "$RD_COUNT" -eq 100 ] && log "     (! truncated at 100 - full list in CSV)"
        fi
      fi
    else
      # --- No baseline: just compare DB1 vs DB2 ---

      # Rows only in db1
      R1=$(run "$DB1" "SET NOCOUNT ON; SELECT TOP 100 'ONLY_IN_${DB1}' AS change_type, $PKSelect FROM [${DB1}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB2}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" || true)
      R1_COUNT=$(echo "$R1" | grep -c 'ONLY_IN_' || true)
      if [ "$R1_COUNT" -gt 0 ]; then
        log "  >> Rows only in $DB1 (up to 100):"
        echo "$R1" | grep 'ONLY_IN_' | head -100 | while IFS= read -r line; do log "    $line"; done
        [ "$R1_COUNT" -eq 100 ] && log "     (! truncated at 100 - full list in CSV)"
      else
        log "  >> Rows only in $DB1: none"
      fi

      # Rows only in db2
      R2=$(run "$DB2" "SET NOCOUNT ON; SELECT TOP 100 'ONLY_IN_${DB2}' AS change_type, $PKSelect FROM [${DB2}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB1}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" || true)
      R2_COUNT=$(echo "$R2" | grep -c 'ONLY_IN_' || true)
      if [ "$R2_COUNT" -gt 0 ]; then
        log "  >> Rows only in $DB2 (up to 100):"
        echo "$R2" | grep 'ONLY_IN_' | head -100 | while IFS= read -r line; do log "    $line"; done
        [ "$R2_COUNT" -eq 100 ] && log "     (! truncated at 100 - full list in CSV)"
      else
        log "  >> Rows only in $DB2: none"
      fi

      # Column diffs
      if [ -n "$DIFFCond" ]; then
        RD=$(run "$DB1" "SET NOCOUNT ON; SELECT TOP 100 'MODIFIED' AS change_type, $ABCols FROM [${DB1}].[${SCHEMA}].[${TNAME}] a INNER JOIN [${DB2}].[${SCHEMA}].[${TNAME}] b ON $JOINCond WHERE $DIFFCond" || true)
        RD_COUNT=$(echo "$RD" | grep -c 'MODIFIED' || true)
        if [ "$RD_COUNT" -gt 0 ]; then
          log "  >> Modified rows (up to 100):"
          echo "$RD" | grep 'MODIFIED' | head -100 | while IFS= read -r line; do log "    $line"; done
          [ "$RD_COUNT" -eq 100 ] && log "     (! truncated at 100 - full list in CSV)"
        else
          log "  >> Modified rows: none"
        fi
      fi
    fi

    # --- CSV EXPORT (if truncated, large table, or any divergence) ---
    NEED_CSV=false
    if [ "$LARGE_TABLE" = true ]; then NEED_CSV=true; fi
    if [ "${R1_COUNT:-0}" -ge 100 ] || [ "${R2_COUNT:-0}" -ge 100 ] || [ "${RD_COUNT:-0}" -ge 100 ]; then NEED_CSV=true; fi
    # Also export if row-count divergence exceeds 100 (even if TOP 100 not hit due to sampling)
    c1_cnt=$(awk -v t="$tbl" '$1==t {print $2}' "$TMPDIR/state1.txt")
    c2_cnt=$(awk -v t="$tbl" '$1==t {print $2}' "$TMPDIR/state2.txt")
    if [ -n "$c1_cnt" ] && [ -n "$c2_cnt" ]; then
      delta_abs=$(( c1_cnt > c2_cnt ? c1_cnt - c2_cnt : c2_cnt - c1_cnt ))
      [ "$delta_abs" -gt 100 ] && NEED_CSV=true
    fi
    # If small table but has any diff, also provide CSV for completeness (user requested)
    if [ "${R1_COUNT:-0}" -gt 0 ] || [ "${R2_COUNT:-0}" -gt 0 ] || [ "${RD_COUNT:-0}" -gt 0 ]; then
      # For small tables (<500k) with <100 diffs, CSV is cheap - export anyway if there is any diff
      # This ensures edi_po (22 rows) also gets a CSV as requested for "too many" threshold is still met via LARGE check;
      # enable for all diffs to give machine-readable output
      NEED_CSV=true
    fi

    if [ "$NEED_CSV" = true ]; then
      log "  >> CSV export for $tbl -> $CSV_DIR/"

      # Build header for full-row CSV (same as ALL_COLS)
      # 1) New in DB1 - full rows
      if [ "${R1_COUNT:-0}" -gt 0 ] || [ "$LARGE_TABLE" = true ]; then
        CSV1="$CSV_DIR/${SAFE_TBL}__new_in_${DB1}.csv"
        Q1="SELECT $CSV_ALL_SELECT FROM [${DB1}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB2}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)"
        # Count actual rows for logging (fast COUNT)
        ACTUAL_R1=$(run "$DB1" "SET NOCOUNT ON; SELECT COUNT(*) AS cnt FROM [${DB1}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB2}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" | grep -E '[0-9]+' | grep -v "rows affected" | grep -v -- "--" | tr -d ' ' | head -1 || echo "?")
        log "     exporting new_in_${DB1} ($ACTUAL_R1 rows) -> $(basename "$CSV1")"
        export_csv "$DB1" "$Q1" "$CSV1" "$CSV_ALL_HEADER" || log "     CSV export failed for $CSV1"
      fi

      # 2) New in DB2 - full rows
      if [ "${R2_COUNT:-0}" -gt 0 ] || [ "$LARGE_TABLE" = true ]; then
        CSV2="$CSV_DIR/${SAFE_TBL}__new_in_${DB2}.csv"
        Q2="SELECT $CSV_ALL_SELECT FROM [${DB2}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB1}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)"
        ACTUAL_R2=$(run "$DB2" "SET NOCOUNT ON; SELECT COUNT(*) AS cnt FROM [${DB2}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB1}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" | grep -E '[0-9]+' | grep -v "rows affected" | grep -v -- "--" | tr -d ' ' | head -1 || echo "?")
        log "     exporting new_in_${DB2} ($ACTUAL_R2 rows) -> $(basename "$CSV2")"
        export_csv "$DB2" "$Q2" "$CSV2" "$CSV_ALL_HEADER" || log "     CSV export failed for $CSV2"
      fi

      # 3) Modified - full pairwise rows (if applicable)
      if [ -n "$DIFFCond" ]; then
        # Check if any modified exist at all (even if TOP100 was 0, large table may have mods)
        MOD_CHECK=$(run "$DB1" "SET NOCOUNT ON; SELECT COUNT(*) AS cnt FROM [${DB1}].[${SCHEMA}].[${TNAME}] a INNER JOIN [${DB2}].[${SCHEMA}].[${TNAME}] b ON $JOINCond WHERE $DIFFCond" | grep -E '[0-9]+' | grep -v "rows affected" | grep -v -- "--" | tr -d ' ' | head -1 || echo "0")
        # Strip non-digits
        MOD_CHECK_NUM=$(echo "$MOD_CHECK" | tr -cd '0-9')
        [ -z "$MOD_CHECK_NUM" ] && MOD_CHECK_NUM=0
        if [ "$MOD_CHECK_NUM" -gt 0 ] || [ "${RD_COUNT:-0}" -gt 0 ]; then
          CSV3="$CSV_DIR/${SAFE_TBL}__modified.csv"
          MOD_HEADER=""
          MOD_SELECT=""
          first=true
          while IFS= read -r col; do
            [ -z "$col" ] && continue
            if [ "$first" = true ]; then first=false; else MOD_HEADER="$MOD_HEADER,"; MOD_SELECT="$MOD_SELECT, "; fi
            MOD_HEADER="${MOD_HEADER}${col}_${DB1},${col}_${DB2}"
            MOD_SELECT="${MOD_SELECT}a.[$col] AS [${col}_${DB1}], b.[$col] AS [${col}_${DB2}]"
          done <<< "$ALL_COLS"
          Q3="SELECT $MOD_SELECT FROM [${DB1}].[${SCHEMA}].[${TNAME}] a INNER JOIN [${DB2}].[${SCHEMA}].[${TNAME}] b ON $JOINCond WHERE $DIFFCond"
          log "     exporting modified ($MOD_CHECK_NUM rows) -> $(basename "$CSV3")"
          export_csv "$DB1" "$Q3" "$CSV3" "$MOD_HEADER" || log "     CSV export failed for $CSV3"
        fi
      fi
    fi
  done < "$CHANGED_TABLES_FILE"
fi

# ============================================================
# SUMMARY
# ============================================================
log ""
log "================================================================"
log "SUMMARY"
log "================================================================"
log ""

# Count changed tables
CHANGED_COUNT=0
if [ -s "$CHANGED_TABLES_FILE" ]; then
  CHANGED_COUNT=$(wc -l < "$CHANGED_TABLES_FILE" | tr -d ' ')
fi

# Count tables only in each DB
ONLY_DB1_COUNT=0
ONLY_DB2_COUNT=0
if [ "$HAS_BASELINE" = true ]; then
  [ -n "$NEW_IN_DB1" ] && ONLY_DB1_COUNT=$(echo "$NEW_IN_DB1" | wc -l | tr -d ' ')
  [ -n "$NEW_IN_DB2" ] && ONLY_DB2_COUNT=$(echo "$NEW_IN_DB2" | wc -l | tr -d ' ')
  [ -n "$DROPPED_FROM_DB1" ] && ONLY_DB1_COUNT=$(( ONLY_DB1_COUNT + $(echo "$DROPPED_FROM_DB1" | wc -l | tr -d ' ') ))
  [ -n "$DROPPED_FROM_DB2" ] && ONLY_DB2_COUNT=$(( ONLY_DB2_COUNT + $(echo "$DROPPED_FROM_DB2" | wc -l | tr -d ' ') ))
else
  [ -n "$T_ONLY1" ] && ONLY_DB1_COUNT=$(echo "$T_ONLY1" | wc -l | tr -d ' ')
  [ -n "$T_ONLY2" ] && ONLY_DB2_COUNT=$(echo "$T_ONLY2" | wc -l | tr -d ' ')
fi

log "  Databases compared:     $DB1 vs $DB2"
log "  Tables in $DB1:        $T1_COUNT"
log "  Tables in $DB2:        $T2_COUNT"
log "  Tables only in $DB1:   $ONLY_DB1_COUNT"
log "  Tables only in $DB2:   $ONLY_DB2_COUNT"
log "  Tables with changes:   $CHANGED_COUNT"
log ""

# Highlight divergences (where row counts differ between DBs)
if [ "$HAS_BASELINE" = true ] && [ -s "$CHANGED_TABLES_FILE" ]; then
  DIVERGENCE_FOUND=false
  while IFS= read -r tbl; do
    [ -z "$tbl" ] && continue
    c1_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state1.txt")
    c1_cnt=$(echo "$c1_line" | awk '{print $2}')
    c2_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state2.txt")
    c2_cnt=$(echo "$c2_line" | awk '{print $2}')
    if [ -n "$c1_cnt" ] && [ -n "$c2_cnt" ] && [ "$c1_cnt" != "$c2_cnt" ]; then
      if [ "$DIVERGENCE_FOUND" = false ]; then
        log "  DIVERGENCES ($DB1 vs $DB2 row count mismatch):"
        DIVERGENCE_FOUND=true
      fi
      delta=$(( c2_cnt - c1_cnt ))
      log "    $tbl: $c1_cnt vs $c2_cnt (delta: $delta)"
    fi
  done < "$CHANGED_TABLES_FILE"
  if [ "$DIVERGENCE_FOUND" = false ]; then
    log "  Divergences: NONE (all changed tables have identical row counts)"
  fi
fi

log ""
log "================================================================"
log "REPORT SAVED: $REPORT"
if [ ${#CSV_FILES_CREATED[@]} -gt 0 ]; then
  log "CSV EXPORTS: ${#CSV_FILES_CREATED[@]} files in $CSV_DIR"
  for f in "${CSV_FILES_CREATED[@]}"; do
    log "  - $f ($(wc -l < "$f" | tr -d ' ') lines incl. header)"
  done
else
  # Clean up empty CSV dir if no exports
  rmdir "$CSV_DIR" 2>/dev/null || true
  log "CSV EXPORTS: none (no truncated/large diffs)"
fi
log "================================================================"

# ============================================================
# GENERATE MARKDOWN REPORT
# ============================================================
MDREPORT="${REPORT%.txt}.md"

{
echo "# Database Comparison Report"
echo ""
echo "**Date**: $(date '+%Y-%m-%d %H:%M:%S')  "
echo "**Databases**: \`$DB1\` vs \`$DB2\`  "
echo "**Server**: $SERVER  "
echo "**Mode**: $([ "$NO_BASELINE" = true ] && echo 'no-baseline' || echo 'baseline-aware')"
echo ""
echo "---"
echo ""
echo "## Overview"
echo ""
echo "| Metric | Value |"
echo "|--------|-------|"
echo "| Tables in \`$DB1\` | $T1_COUNT |"
echo "| Tables in \`$DB2\` | $T2_COUNT |"
echo "| Tables only in \`$DB1\` | $ONLY_DB1_COUNT |"
echo "| Tables only in \`$DB2\` | $ONLY_DB2_COUNT |"
echo "| Tables with changes | $CHANGED_COUNT |"

if [ "$HAS_BASELINE" = true ] && [ -s "$CHANGED_TABLES_FILE" ]; then
  DIVERGENCE_COUNT=0
  while IFS= read -r tbl; do
    [ -z "$tbl" ] && continue
    c1_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state1.txt")
    c1_cnt=$(echo "$c1_line" | awk '{print $2}')
    c2_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state2.txt")
    c2_cnt=$(echo "$c2_line" | awk '{print $2}')
    [ -n "$c1_cnt" ] && [ -n "$c2_cnt" ] && [ "$c1_cnt" != "$c2_cnt" ] && DIVERGENCE_COUNT=$((DIVERGENCE_COUNT + 1))
  done < "$CHANGED_TABLES_FILE"
  echo "| Divergences (row count mismatch) | $DIVERGENCE_COUNT |"
fi
echo ""

if [ -n "$T_ONLY1" ] || [ -n "$T_ONLY2" ]; then
  echo "### Schema Differences"
  echo ""
  if [ -n "$T_ONLY1" ]; then
    echo "**Tables only in \`$DB1\`**:"
    echo '```'
    echo "$T_ONLY1"
    echo '```'
    echo ""
  fi
  if [ -n "$T_ONLY2" ]; then
    echo "**Tables only in \`$DB2\`**:"
    echo '```'
    echo "$T_ONLY2"
    echo '```'
    echo ""
  fi
fi

if [ "$HAS_BASELINE" = true ] && [ -s "$CHANGED_TABLES_FILE" ]; then
  echo "## Data Changes"
  echo ""
  echo "| Table | $DB1 | $DB2 | Delta |"
  echo "|-------|------|------|-------|"
  while IFS= read -r tbl; do
    [ -z "$tbl" ] && continue
    c1_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state1.txt")
    c1_cnt=$(echo "$c1_line" | awk '{print $2}')
    c1_chk=$(echo "$c1_line" | awk '{print $3}')
    c2_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state2.txt")
    c2_cnt=$(echo "$c2_line" | awk '{print $2}')
    c2_chk=$(echo "$c2_line" | awk '{print $3}')
    b1_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/base1.txt")
    b1_cnt=$(echo "$b1_line" | awk '{print $2}')
    b2_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/base2.txt")
    b2_cnt=$(echo "$b2_line" | awk '{print $2}')
    delta=$(( ${c2_cnt:-0} - ${c1_cnt:-0} ))
    delta_str=""
    [ "$delta" -ne 0 ] && delta_str="$delta"
    echo "| \`$tbl\` | ${b1_cnt:-?}→$c1_cnt | ${b2_cnt:-?}→$c2_cnt | $delta_str |"
  done < "$CHANGED_TABLES_FILE"
  echo ""

  echo "### Divergences"
  echo ""
  DIV_FOUND=false
  while IFS= read -r tbl; do
    [ -z "$tbl" ] && continue
    c1_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state1.txt")
    c1_cnt=$(echo "$c1_line" | awk '{print $2}')
    c2_line=$(awk -v t="$tbl" '$1==t {print $0}' "$TMPDIR/state2.txt")
    c2_cnt=$(echo "$c2_line" | awk '{print $2}')
    if [ -n "$c1_cnt" ] && [ -n "$c2_cnt" ] && [ "$c1_cnt" != "$c2_cnt" ]; then
      DIV_FOUND=true
      delta=$(( c2_cnt - c1_cnt ))
      echo "- \`$tbl\`: $c1_cnt ($DB1) vs $c2_cnt ($DB2) — delta $delta"
    fi
  done < "$CHANGED_TABLES_FILE"
  if [ "$DIV_FOUND" = false ]; then
    echo "_No divergences detected._"
  fi
  echo ""
fi

if [ ${#CSV_FILES_CREATED[@]} -gt 0 ]; then
  echo "## CSV Exports"
  echo ""
  echo "Full row-level diffs exported to \`$CSV_DIR\` (one CSV per change type):"
  echo ""
  for f in "${CSV_FILES_CREATED[@]}"; do
    lines=$(wc -l < "$f" | tr -d ' ')
    data_rows=$((lines - 1))
    echo "- \`$(basename "$f")\` — $data_rows rows (+ header), \`$f\`"
  done
  echo ""
  echo "> Large tables (>500K) and truncated TOP-100 diffs are fully materialized here. Includes all columns; modified CSV has \`${DB1}\`/\`${DB2}\` column pairs."
  echo ""
fi

echo "---"
echo ""
echo "_Report generated by \`compare_dbs.sh\`_"

} > "$MDREPORT"

log "MARKDOWN REPORT SAVED: $MDREPORT"
log "================================================================"
