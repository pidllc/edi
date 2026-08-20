#!/usr/bin/env python3
"""
EDI 997 (Functional Acknowledgment) Checker
Parses 997 files and validates that all transactions were accepted.

Usage:
    python3 edi997_check.py <file1.in> [file2.in ...]
    python3 edi997_check.py --dir /path/to/folder
    python3 edi997_check.py  # default: ./Edifiles/
"""

import sys
import os
import re
import glob as globmod
from datetime import datetime


def detect_delimiters(filepath):
    """Detect the segment terminator and data element separator from the ISA segment."""
    with open(filepath, "rb") as f:
        raw = f.read(512)

    raw_str = raw.decode("ascii", errors="replace")

    # Detect data element separator: the character after "ISA" (position 3)
    if len(raw_str) > 3 and raw_str[3] in ("*", "|"):
        data_sep = raw_str[3]
    else:
        data_sep = "*"

    # Detect segment terminator
    if b"\r\n" in raw:
        idx = raw.find(b"\r\n", 105)
        if idx != -1 and idx < 200:
            seg_term_re = r"\n"
        else:
            seg_term_re = r"~"
    elif b"~" in raw[:200]:
        seg_term_re = r"~"
    else:
        seg_term_re = r"\n"

    # Detect GS functional ID
    gs_match = re.search(r"GS[" + re.escape(data_sep) + r"]([A-Z]+)", raw_str)
    gs_func_id = gs_match.group(1) if gs_match else ""

    return seg_term_re, data_sep, gs_func_id


def parse_997(filepath):
    """Parse an EDI 997 file and extract acknowledgment details."""
    seg_term_re, data_sep, gs_func_id = detect_delimiters(filepath)

    with open(filepath) as f:
        data = f.read()

    def seg_pattern(seg_type):
        return r"" + seg_type + r"[" + re.escape(data_sep) + r"]([^" + seg_term_re + r"]+)" + seg_term_re

    result = {
        "file": filepath,
        "filename": os.path.basename(filepath),
        "gs_functional_id": gs_func_id,
        "transactions": [],
        "overall_status": None,
        "accepted_count": 0,
        "rejected_count": 0,
        "error_count": 0,
    }

    # ISA segment info
    isa_match = re.search(seg_pattern("ISA"), data)
    if isa_match:
        parts = isa_match.group(1).split(data_sep)
        result["isa_sender"] = parts[7].strip() if len(parts) > 7 else ""
        result["isa_receiver"] = parts[5].strip() if len(parts) > 5 else ""
        result["isa_control"] = parts[12] if len(parts) > 12 else ""

    # AK1 segment - functional group header
    ak1_match = re.search(seg_pattern("AK1"), data)
    if ak1_match:
        parts = ak1_match.group(1).split(data_sep)
        result["ack_group_id"] = parts[0] if len(parts) > 0 else ""
        result["ack_group_control"] = parts[1] if len(parts) > 1 else ""
        result["total_transactions"] = parts[2] if len(parts) > 2 else ""

    # AK2+AK5 pairs - individual transaction acknowledgments
    ak2s = list(re.finditer(seg_pattern("AK2"), data))
    ak5s = list(re.finditer(seg_pattern("AK5"), data))

    for i, ak2_match in enumerate(ak2s):
        ak2_parts = ak2_match.group(1).split(data_sep)
        tx = {
            "transaction_id": ak2_parts[0] if len(ak2_parts) > 0 else "",
            "control_number": ak2_parts[1] if len(ak2_parts) > 1 else "",
        }

        # Find corresponding AK5 (should be right after AK2)
        if i < len(ak5s):
            ak5_parts = ak5s[i].group(1).split(data_sep)
            tx["status_code"] = ak5_parts[0] if len(ak5_parts) > 0 else ""
            tx["error_codes"] = ak5_parts[1:] if len(ak5_parts) > 1 else []

            if tx["status_code"] == "A":
                result["accepted_count"] += 1
            elif tx["status_code"] == "E":
                result["error_count"] += 1
            elif tx["status_code"] in ("R", "W", "X", "I", "P"):
                result["rejected_count"] += 1
            else:
                result["error_count"] += 1

        result["transactions"].append(tx)

    # AK9 segment - functional group acknowledgment
    ak9_match = re.search(seg_pattern("AK9"), data)
    if ak9_match:
        parts = ak9_match.group(1).split(data_sep)
        result["group_status"] = parts[0] if len(parts) > 0 else ""
        result["received_count"] = parts[1] if len(parts) > 1 else ""
        result["accepted_count_group"] = parts[2] if len(parts) > 2 else ""
        result["acknowledged_count"] = parts[3] if len(parts) > 3 else ""

    # Determine overall status
    if result.get("group_status") == "A":
        result["overall_status"] = "ACCEPTED"
    elif result.get("group_status") == "E":
        result["overall_status"] = "ACCEPTED WITH ERRORS"
    elif result.get("group_status") == "R":
        result["overall_status"] = "REJECTED"
    else:
        result["overall_status"] = f"UNKNOWN ({result.get('group_status', 'N/A')})"

    return result


def discover_997_files(directory):
    """Discover all 997 EDI files in a directory."""
    results = []
    skipped = []

    for entry in sorted(os.listdir(directory)):
        if entry.startswith(".") or entry == "__pycache__":
            continue
        filepath = os.path.join(directory, entry)
        if not os.path.isfile(filepath):
            continue

        try:
            _, _, gs_func_id = detect_delimiters(filepath)
            if gs_func_id == "FA":
                results.append(filepath)
            else:
                skipped.append((entry, gs_func_id))
        except Exception as e:
            skipped.append((entry, f"ERROR: {e}"))

    if skipped:
        print(f"\nSkipped {len(skipped)} non-997 file(s):")
        for name, reason in skipped:
            print(f"  {name}  (GS={reason})")

    return results


def print_report(results):
    """Print 997 analysis report."""
    print("\n" + "=" * 100)
    print("EDI 997 (FUNCTIONAL ACKNOWLEDGMENT) REPORT")
    print("=" * 100)

    total_files = len(results)
    total_accepted = 0
    total_rejected = 0
    total_errors = 0
    total_transactions = 0
    issues = []

    for r in results:
        status_icon = "✓" if r["overall_status"] == "ACCEPTED" else "✗" if "REJECTED" in r["overall_status"] else "!"
        print(f"\n{status_icon} {r['filename']}")
        print(f"  Status:       {r['overall_status']}")
        print(f"  Transactions: {len(r['transactions'])} received, {r['accepted_count_group']} accepted")

        if r['rejected_count'] > 0:
            issues.append((r['filename'], "REJECTED", f"{r['rejected_count']} transaction(s) rejected"))
        if r['error_count'] > 0:
            issues.append((r['filename'], "ERRORS", f"{r['error_count']} transaction(s) with errors"))

        total_accepted += r['accepted_count']
        total_rejected += r['rejected_count']
        total_errors += r['error_count']
        total_transactions += len(r['transactions'])

    print(f"\n{'=' * 100}")
    print("SUMMARY")
    print(f"{'=' * 100}")
    print(f"Total 997 files:      {total_files}")
    print(f"Total transactions:   {total_transactions}")
    print(f"Accepted:             {total_accepted}")
    print(f"Rejected:             {total_rejected}")
    print(f"Errors:               {total_errors}")

    if issues:
        print(f"\n{'=' * 100}")
        print("ISSUES FOUND")
        print(f"{'=' * 100}")
        for filename, status, detail in issues:
            print(f"  {filename}: {status} - {detail}")
    else:
        print("\n✓ ALL 997 ACKNOWLEDGMENTS ACCEPTED SUCCESSFULLY")

    print()
    return total_rejected == 0 and total_errors == 0


def main():
    edifiles_dir = None
    filepaths = []

    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == "--dir" and i + 1 < len(args):
            edifiles_dir = args[i + 1]
            i += 2
        elif args[i] == "--help" or args[i] == "-h":
            print("Usage:")
            print("  python3 edi997_check.py <file1> [file2 ...]")
            print("  python3 edi997_check.py --dir /path/to/folder")
            print("  python3 edi997_check.py '/path/to/folder/*997*'")
            sys.exit(0)
        else:
            filepaths.append(args[i])
            i += 1

    if edifiles_dir:
        if not os.path.isdir(edifiles_dir):
            print(f"Error: directory not found: {edifiles_dir}")
            sys.exit(1)
        filepaths = discover_997_files(edifiles_dir)
        if not filepaths:
            print(f"No EDI 997 files found in {edifiles_dir}")
            sys.exit(1)
        print(f"Found {len(filepaths)} EDI 997 file(s) in {edifiles_dir}")
    elif filepaths:
        # Expand glob patterns
        expanded = []
        for pattern in filepaths:
            matches = globmod.glob(pattern)
            if matches:
                expanded.extend(matches)
            else:
                print(f"Warning: no files matched pattern: {pattern}")
        filepaths = [f for f in expanded if os.path.isfile(f)]
        if not filepaths:
            print("No matching files found.")
            sys.exit(1)
        # Verify they are 997 files
        verified = []
        for fp in filepaths:
            try:
                _, _, gs_func_id = detect_delimiters(fp)
                if gs_func_id == "FA":
                    verified.append(fp)
            except Exception as e:
                print(f"Warning: could not read {fp}: {e}")
        filepaths = verified
        if not filepaths:
            print("No valid EDI 997 files found in the matched files.")
            sys.exit(1)
        print(f"Found {len(filepaths)} EDI 997 file(s)")
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        default_dir = os.path.join(script_dir, "Edifiles")
        if os.path.isdir(default_dir):
            edifiles_dir = default_dir
            filepaths = discover_997_files(edifiles_dir)
            if not filepaths:
                print(f"No EDI 997 files found in {edifiles_dir}")
                sys.exit(1)
            print(f"Found {len(filepaths)} EDI 997 file(s) in {edifiles_dir}")
        else:
            print("Usage: python3 edi997_check.py <file1> [file2 ...]")
            print("       python3 edi997_check.py --dir /path/to/folder")
            print("       python3 edi997_check.py '/path/to/folder/*997*'")
            sys.exit(1)

    results = []
    for filepath in filepaths:
        try:
            result = parse_997(filepath)
            results.append(result)
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")

    if results:
        success = print_report(results)
        sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
