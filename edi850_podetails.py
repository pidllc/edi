#!/usr/bin/env python3
"""
EDI 850 PO Detail Extractor
Extracts individual PO details from EDI 850 files.

Usage:
    python3 edi850_podetails.py <file1.in> [file2.in ...]
    python3 edi850_podetails.py *.in
    python3 edi850_podetails.py --dir /path/to/Edifiles    # analyze all files in dir
    python3 edi850_podetails.py                             # default: ./Edifiles/
"""

import sys
import os
import re
import glob as globmod
from datetime import datetime


def detect_delimiters(filepath):
    """Detect the segment terminator and data element separator from the ISA segment.

    EDI files can use different delimiters:
    - Segment terminator: ~ (tilde) or \\r (carriage return) or \\r\\n
    - Data element separator: * (asterisk) or | (pipe)

    Returns (segment_terminator_regex, data_separator, gs_functional_id).
    """
    with open(filepath, "rb") as f:
        raw = f.read(512)

    raw_str = raw.decode("ascii", errors="replace")

    # Detect data element separator: the character after "ISA" (position 3)
    if len(raw_str) > 3 and raw_str[3] in ("*", "|"):
        data_sep = raw_str[3]
    else:
        data_sep = "*"

    # Detect segment terminator: find where ISA segment ends.
    # NOTE: regex operates on text-mode data where Python normalizes \r\n -> \n,
    # so we always use \n (not \r\n) as the regex terminator for CR/LF files.
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


def discover_edi_files(directory):
    """Discover all EDI 850 files in a directory.

    Returns list of filepath strings (only GS=PO files).
    """
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
            if gs_func_id == "PO":
                results.append(filepath)
            else:
                skipped.append((entry, gs_func_id))
        except Exception as e:
            skipped.append((entry, f"ERROR: {e}"))

    if skipped:
        print(f"\nSkipped {len(skipped)} non-850 file(s):")
        for name, reason in skipped:
            print(f"  {name}  (GS={reason})")

    return results


def parse_edi_date(date_str):
    """Parse EDI date string (YYYYMMDD) to readable format."""
    if not date_str or len(date_str) < 8:
        return "N/A"
    try:
        dt = datetime.strptime(date_str[:8], "%Y%m%d")
        return dt.strftime("%Y-%m-%d")
    except ValueError:
        return date_str


def extract_po_sections(data, seg_term_re, data_sep):
    """Split EDI data into individual PO sections based on BEG segments."""
    pattern = r"BEG[" + re.escape(data_sep) + r"]([^" + seg_term_re + r"]+)" + seg_term_re
    beg_matches = list(re.finditer(pattern, data))

    if not beg_matches:
        return []

    sections = []
    for i, match in enumerate(beg_matches):
        start = match.start()
        end = beg_matches[i + 1].start() if i + 1 < len(beg_matches) else len(data)
        sections.append(data[start:end])

    return sections


def parse_po_section(section_data, global_dates, seg_term_re, data_sep):
    """Parse a single PO section and extract details."""
    result = {}

    def seg_pattern(seg_type):
        return r"" + seg_type + r"[" + re.escape(data_sep) + r"]([^" + seg_term_re + r"]+)" + seg_term_re

    # BEG segment - PO number and date
    beg_match = re.search(seg_pattern("BEG"), section_data)
    if beg_match:
        parts = beg_match.group(1).split(data_sep)
        result["po_number"] = parts[2] if len(parts) > 2 else "N/A"
        result["po_date"] = parts[4] if len(parts) > 4 else ""

    # N1*ST - Ship To
    n1_pattern = r"N1[" + re.escape(data_sep) + r"]ST[" + re.escape(data_sep) + r"]([^" + seg_term_re + r"]+)" + seg_term_re
    st_match = re.search(n1_pattern, section_data)
    if st_match:
        parts = st_match.group(1).split(data_sep)
        result["ship_to_name"] = parts[0] if len(parts) > 0 else ""
        result["ship_to_id"] = parts[2] if len(parts) > 2 else ""
    else:
        result["ship_to_name"] = ""
        result["ship_to_id"] = ""

    # N3/N4 - Ship To Address
    n3_match = re.search(seg_pattern("N3"), section_data)
    n4_match = re.search(seg_pattern("N4"), section_data)
    if n3_match and n4_match:
        n3_parts = n3_match.group(1).split(data_sep)
        n4_parts = n4_match.group(1).split(data_sep)
        result["ship_to_addr"] = n3_parts[0] if n3_parts else ""
        result["ship_to_city"] = n4_parts[0] if len(n4_parts) > 0 else ""
        result["ship_to_state"] = n4_parts[1] if len(n4_parts) > 1 else ""
        result["ship_to_zip"] = n4_parts[2] if len(n4_parts) > 2 else ""
    else:
        result["ship_to_addr"] = ""
        result["ship_to_city"] = ""
        result["ship_to_state"] = ""
        result["ship_to_zip"] = ""

    # DTM segments - dates (use section-specific if present, else global)
    dtms = re.findall(seg_pattern("DTM"), section_data)
    section_dates = {}
    for dtm in dtms:
        parts = dtm.split(data_sep)
        if len(parts) >= 2:
            section_dates[parts[0]] = parts[1]

    result["ship_date"] = section_dates.get("037", global_dates.get("037", ""))
    result["cancel_date"] = section_dates.get("038", global_dates.get("038", ""))
    result["must_arrive_by"] = section_dates.get("063", global_dates.get("063", ""))

    # PO1 segments - line items
    po1s = re.findall(seg_pattern("PO1"), section_data)
    result["line_count"] = len(po1s)
    result["total_qty"] = 0
    result["total_amount"] = 0.0

    for po1 in po1s:
        parts = po1.split(data_sep)
        if len(parts) >= 4:
            try:
                qty = int(parts[1])
            except (ValueError, IndexError):
                qty = 0
            try:
                price = float(parts[3])
            except (ValueError, IndexError):
                price = 0.0
            result["total_qty"] += qty
            result["total_amount"] += qty * price

    # SAC segments - allowances/charges for this PO
    sacs = re.findall(seg_pattern("SAC"), section_data)
    result["sac_total"] = 0.0
    for sac in sacs:
        parts = sac.split(data_sep)
        if len(parts) >= 5:
            try:
                result["sac_total"] += float(parts[4])
            except (ValueError, IndexError):
                pass

    return result


def parse_edi_850(filepath):
    """Parse an EDI 850 file and extract all PO details."""
    seg_term_re, data_sep, gs_func_id = detect_delimiters(filepath)

    with open(filepath) as f:
        data = f.read()

    def seg_pattern(seg_type):
        return r"" + seg_type + r"[" + re.escape(data_sep) + r"]([^" + seg_term_re + r"]+)" + seg_term_re

    # Get global dates from first DTM segments (before any BEG)
    first_beg = re.search(r"BEG[" + re.escape(data_sep) + r"]", data)
    header_data = data[: first_beg.start()] if first_beg else data

    global_dates = {}
    dtms = re.findall(seg_pattern("DTM"), header_data)
    for dtm in dtms:
        parts = dtm.split(data_sep)
        if len(parts) >= 2:
            global_dates[parts[0]] = parts[1]

    # Extract individual PO sections
    sections = extract_po_sections(data, seg_term_re, data_sep)

    # Parse each PO section
    pos = []
    for section in sections:
        po = parse_po_section(section, global_dates, seg_term_re, data_sep)
        pos.append(po)

    return {
        "file": filepath,
        "po_count": len(pos),
        "pos": pos,
    }


def print_po_details(results):
    """Print detailed PO information for each file."""
    for r in results:
        print(f"\n{'=' * 100}")
        print(f"FILE: {r['file']}")
        print(f"Total POs: {r['po_count']}")
        print(f"{'=' * 100}")

        # Summary table for this file
        print(f"\n{'#':>3} {'PO Number':<15} {'Ship Date':>11} {'Cancel':>11} {'MAB By':>11} {'Qty':>8} {'Amount':>14} {'Ship To'}")
        print("-" * 100)

        total_qty = 0
        total_amount = 0.0

        for i, po in enumerate(r["pos"], 1):
            ship_date = parse_edi_date(po.get("ship_date", ""))
            cancel_date = parse_edi_date(po.get("cancel_date", ""))
            mab_date = parse_edi_date(po.get("must_arrive_by", ""))

            qty = po.get("total_qty", 0)
            amt = po.get("total_amount", 0)
            ship_to = po.get("ship_to_name", "N/A")

            total_qty += qty
            total_amount += amt

            print(
                f"{i:>3} {po.get('po_number', 'N/A'):<15} {ship_date:>11} {cancel_date:>11} {mab_date:>11} "
                f"{qty:>8,} {amt:>14,.2f} {ship_to}"
            )

        print("-" * 100)
        print(f"{'TOTAL':>3} {'':15} {'':11} {'':11} {'':11} {total_qty:>8,} {total_amount:>14,.2f}")

    # Cross-file summary
    if len(results) > 1:
        print(f"\n\n{'=' * 100}")
        print("CROSS-FILE SUMMARY")
        print(f"{'=' * 100}")
        print(f"\n{'File':<25} {'POs':>5} {'Total Qty':>12} {'Total Amount':>16}")
        print("-" * 60)

        grand_total_qty = 0
        grand_total_amount = 0.0

        for r in results:
            fname = r["file"].split("/")[-1][:24]
            po_count = r["po_count"]
            file_qty = sum(po.get("total_qty", 0) for po in r["pos"])
            file_amount = sum(po.get("total_amount", 0) for po in r["pos"])

            grand_total_qty += file_qty
            grand_total_amount += file_amount

            print(f"{fname:<25} {po_count:>5} {file_qty:>12,} {file_amount:>16,.2f}")

        print("-" * 60)
        print(f"{'GRAND TOTAL':<25} {'':>5} {grand_total_qty:>12,} {grand_total_amount:>16,.2f}")


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
            print("  python3 edi850_podetails.py <file1> [file2 ...]")
            print("  python3 edi850_podetails.py --dir /path/to/Edifiles")
            print("  python3 edi850_podetails.py              # default: ./Edifiles/ next to script")
            sys.exit(0)
        else:
            filepaths.append(args[i])
            i += 1

    if edifiles_dir:
        if not os.path.isdir(edifiles_dir):
            print(f"Error: directory not found: {edifiles_dir}")
            sys.exit(1)
        filepaths = discover_edi_files(edifiles_dir)
        if not filepaths:
            print(f"No EDI 850 files found in {edifiles_dir}")
            sys.exit(1)
        print(f"Found {len(filepaths)} EDI 850 file(s) in {edifiles_dir}")
    elif filepaths:
        # Expand glob patterns (works on Windows and Unix)
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
        # Verify they are 850 files
        verified = []
        for fp in filepaths:
            try:
                _, _, gs_func_id = detect_delimiters(fp)
                if gs_func_id == "PO":
                    verified.append(fp)
            except Exception as e:
                print(f"Warning: could not read {fp}: {e}")
        filepaths = verified
        if not filepaths:
            print("No valid EDI 850 files found in the matched files.")
            sys.exit(1)
        print(f"Found {len(filepaths)} EDI 850 file(s)")
    else:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        default_dir = os.path.join(script_dir, "Edifiles")
        if os.path.isdir(default_dir):
            edifiles_dir = default_dir
            filepaths = discover_edi_files(edifiles_dir)
            if not filepaths:
                print(f"No EDI 850 files found in {edifiles_dir}")
                sys.exit(1)
            print(f"Found {len(filepaths)} EDI 850 file(s) in {edifiles_dir}")
        else:
            print("Usage: python3 edi850_podetails.py <file1> [file2 ...]")
            print("       python3 edi850_podetails.py --dir /path/to/Edifiles")
            sys.exit(1)

    results = []
    for filepath in filepaths:
        try:
            result = parse_edi_850(filepath)
            results.append(result)
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")

    if results:
        print_po_details(results)


if __name__ == "__main__":
    main()
