#!/bin/bash
# Database comparison with baseline snapshot support
# Usage:
#   ./compare_dbs.sh --snapshot <db1> <db2>     Capture baseline snapshot
#   ./compare_dbs.sh <db1> <db2>                Compare using baseline (if exists)
#   ./compare_dbs.sh <db1> <db2> --no-baseline  Compare without baseline (counts + triggers only)
#
# Output: temp/compare_<db1>_<db2>_<datetime>.txt

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
DB1=""
DB2=""

for arg in "$@"; do
  case "$arg" in
    --snapshot) SNAPSHOT_MODE=true ;;
    --no-baseline) NO_BASELINE=true ;;
    -*) echo "Unknown flag: $arg"; exit 1 ;;
    *)
      if [ -z "$DB1" ]; then DB1="$arg"
      elif [ -z "$DB2" ]; then DB2="$arg"
      fi
      ;;
  esac
done

DB1="${DB1:?Usage: $0 [--snapshot] <db1> <db2> [--no-baseline]}"
DB2="${DB2:?Usage: $0 [--snapshot] <db1> <db2> [--no-baseline]}"

REPORT="$REPO_ROOT/temp/compare_${DB1}_${DB2}_${TIMESTAMP}.txt"
SNAPSHOT_DIR="$REPO_ROOT/temp"
SNAP1="$SNAPSHOT_DIR/snapshot_${DB1}.txt"
SNAP2="$SNAPSHOT_DIR/snapshot_${DB2}.txt"

TMPDIR=$(mktemp -d)
trap "rm -rf $TMPDIR" EXIT

log() { echo "$1" | tee -a "$REPORT"; }
run() { sqlcmd -S "$SERVER" -d "$1" -U "$USER" -P "$PASS" -C -Q "$2" -y 0 </dev/null 2>&1; }
runfile() { sqlcmd -S "$SERVER" -d "$1" -U "$USER" -P "$PASS" -C -i "$2" -y 0 </dev/null 2>&1; }

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
if [ -s "$CHANGED_TABLES_FILE" ]; then
  log "================================================================"
  log "ROW-LEVEL CHANGES (up to 100 per table)"
  log "================================================================"

  while IFS= read -r tbl; do
    [ -z "$tbl" ] && continue
    SCHEMA=$(echo "$tbl" | cut -d. -f1 | tr -d '[]')
    TNAME=$(echo "$tbl" | cut -d. -f2 | tr -d '[]')
    log ""
    log "  === $tbl ==="

    # Get PK columns
    PK_COLS=$(run "$DB1" "SELECT ku.COLUMN_NAME FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE ku ON tc.CONSTRAINT_NAME=ku.CONSTRAINT_NAME WHERE tc.TABLE_NAME='$TNAME' AND tc.TABLE_SCHEMA='$SCHEMA' AND tc.CONSTRAINT_TYPE IN ('PRIMARY KEY','UNIQUE') ORDER BY ku.ORDINAL_POSITION" | grep -v '^$' | grep -v 'COLUMN_NAME' | grep -v '^--' | grep -v 'rows affected' | grep -v '^(' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' || true)

    if [ -z "$PK_COLS" ]; then
      log "  (no PK/UNIQUE constraint - row-level diff skipped)"
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

    # Build full select for "column diff" queries
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

    if [ "$HAS_BASELINE" = true ]; then
      # --- Baseline-aware: show changes per DB ---

      # DB1: new rows (in current but not in baseline)
      R1=$(run "$DB1" "SET NOCOUNT ON; SELECT TOP 100 'NEW_IN_${DB1}' AS change_type, $PKSelect FROM [${DB1}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM OPENROWSET('Microsoft.ACE.OLEDB.12.0','Text;Database=${SNAPSHOT_DIR};HDR=YES','SELECT * FROM [snapshot_${DB1}.txt]') b WHERE 1=0)" 2>/dev/null || true)

      # Simpler approach: use BINARY_CHECKSUM to find new/changed rows
      # Rows only in current DB1 (not matchable by PK+checksum in baseline)
      R1=$(run "$DB1" "SET NOCOUNT ON; SELECT TOP 100 'NEW_IN_${DB1}' AS change_type, $PKSelect, BINARY_CHECKSUM(*) AS row_chk FROM [${DB1}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB2}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" || true)
      R1_COUNT=$(echo "$R1" | grep -c 'NEW_IN_' || true)
      if [ "$R1_COUNT" -gt 0 ]; then
        log "  >> New rows in $DB1 (not in $DB2, up to 100):"
        echo "$R1" | grep 'NEW_IN_' | head -100 | while IFS= read -r line; do log "    $line"; done
      fi

      # Rows only in current DB2 (not in DB1)
      R2=$(run "$DB2" "SET NOCOUNT ON; SELECT TOP 100 'NEW_IN_${DB2}' AS change_type, $PKSelect, BINARY_CHECKSUM(*) AS row_chk FROM [${DB2}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB1}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" || true)
      R2_COUNT=$(echo "$R2" | grep -c 'NEW_IN_' || true)
      if [ "$R2_COUNT" -gt 0 ]; then
        log "  >> New rows in $DB2 (not in $DB1, up to 100):"
        echo "$R2" | grep 'NEW_IN_' | head -100 | while IFS= read -r line; do log "    $line"; done
      fi

      # Modified rows (same PK, different data)
      if [ -n "$DIFFCond" ]; then
        RD=$(run "$DB1" "SET NOCOUNT ON; SELECT TOP 100 'MODIFIED' AS change_type, $ABCols FROM [${DB1}].[${SCHEMA}].[${TNAME}] a INNER JOIN [${DB2}].[${SCHEMA}].[${TNAME}] b ON $JOINCond WHERE $DIFFCond" || true)
        RD_COUNT=$(echo "$RD" | grep -c 'MODIFIED' || true)
        if [ "$RD_COUNT" -gt 0 ]; then
          log "  >> Modified rows (same PK, different data, up to 100):"
          echo "$RD" | grep 'MODIFIED' | head -100 | while IFS= read -r line; do log "    $line"; done
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
      else
        log "  >> Rows only in $DB1: none"
      fi

      # Rows only in db2
      R2=$(run "$DB2" "SET NOCOUNT ON; SELECT TOP 100 'ONLY_IN_${DB2}' AS change_type, $PKSelect FROM [${DB2}].[${SCHEMA}].[${TNAME}] a WHERE NOT EXISTS (SELECT 1 FROM [${DB1}].[${SCHEMA}].[${TNAME}] b WHERE $JOINCond)" || true)
      R2_COUNT=$(echo "$R2" | grep -c 'ONLY_IN_' || true)
      if [ "$R2_COUNT" -gt 0 ]; then
        log "  >> Rows only in $DB2 (up to 100):"
        echo "$R2" | grep 'ONLY_IN_' | head -100 | while IFS= read -r line; do log "    $line"; done
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
        else
          log "  >> Modified rows: none"
        fi
      fi
    fi
  done < "$CHANGED_TABLES_FILE"
fi

log ""
log "================================================================"
log "REPORT SAVED: $REPORT"
log "================================================================"
