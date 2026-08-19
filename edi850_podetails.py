#!/usr/bin/env python3
"""
EDI 850 PO Detail Extractor
Extracts individual PO details from EDI 850 files.

Usage:
    python3 edi850_podetails.py <file1.in> [file2.in ...]
    python3 edi850_podetails.py *.in
    python3 edi850_podetails.py /path/to/*.in
"""

import sys
import re
import os
import glob
from datetime import datetime


def parse_edi_date(date_str):
    """Parse EDI date string (YYYYMMDD) to readable format."""
    if not date_str or len(date_str) < 8:
        return "N/A"
    try:
        dt = datetime.strptime(date_str[:8], "%Y%m%d")
        return dt.strftime("%Y-%m-%d")
    except ValueError:
        return date_str


def extract_po_sections(data):
    """Split EDI data into individual PO sections based on BEG segments."""
    # Find all BEG segment positions
    beg_pattern = r'BEG\*([^~]+)~'
    beg_matches = list(re.finditer(beg_pattern, data))

    if not beg_matches:
        return []

    sections = []
    for i, match in enumerate(beg_matches):
        start = match.start()
        # End at next BEG or end of file
        end = beg_matches[i + 1].start() if i + 1 < len(beg_matches) else len(data)
        sections.append(data[start:end])

    return sections


def parse_po_section(section_data, global_dates):
    """Parse a single PO section and extract details."""
    result = {}

    # BEG segment - PO number and date
    beg_match = re.search(r'BEG\*([^~]+)~', section_data)
    if beg_match:
        parts = beg_match.group(1).split('*')
        result['po_number'] = parts[2] if len(parts) > 2 else 'N/A'
        result['po_date'] = parts[4] if len(parts) > 4 else ''

    # N1*ST - Ship To
    st_match = re.search(r'N1\*ST\*([^~]+)~', section_data)
    if st_match:
        parts = st_match.group(1).split('*')
        result['ship_to_name'] = parts[0] if len(parts) > 0 else ''
        result['ship_to_id'] = parts[2] if len(parts) > 2 else ''
    else:
        result['ship_to_name'] = ''
        result['ship_to_id'] = ''

    # N3/N4 - Ship To Address
    n3_match = re.search(r'N3\*([^~]+)~', section_data)
    n4_match = re.search(r'N4\*([^~]+)~', section_data)
    if n3_match and n4_match:
        n3_parts = n3_match.group(1).split('*')
        n4_parts = n4_match.group(1).split('*')
        result['ship_to_addr'] = n3_parts[0] if n3_parts else ''
        result['ship_to_city'] = n4_parts[0] if len(n4_parts) > 0 else ''
        result['ship_to_state'] = n4_parts[1] if len(n4_parts) > 1 else ''
        result['ship_to_zip'] = n4_parts[2] if len(n4_parts) > 2 else ''
    else:
        result['ship_to_addr'] = ''
        result['ship_to_city'] = ''
        result['ship_to_state'] = ''
        result['ship_to_zip'] = ''

    # DTM segments - dates (use section-specific if present, else global)
    dtms = re.findall(r'DTM\*([^~]+)~', section_data)
    section_dates = {}
    for dtm in dtms:
        parts = dtm.split('*')
        if len(parts) >= 2:
            section_dates[parts[0]] = parts[1]

    # Use section dates, fall back to global
    result['ship_date'] = section_dates.get('037', global_dates.get('037', ''))
    result['cancel_date'] = section_dates.get('038', global_dates.get('038', ''))
    result['must_arrive_by'] = section_dates.get('063', global_dates.get('063', ''))

    # PO1 segments - line items
    po1s = re.findall(r'PO1\*([^~]+)~', section_data)
    result['line_count'] = len(po1s)
    result['total_qty'] = 0
    result['total_amount'] = 0.0

    for po1 in po1s:
        parts = po1.split('*')
        if len(parts) >= 4:
            try:
                qty = int(parts[1])
            except (ValueError, IndexError):
                qty = 0
            try:
                price = float(parts[3])
            except (ValueError, IndexError):
                price = 0.0
            result['total_qty'] += qty
            result['total_amount'] += qty * price

    # SAC segments - allowances/charges for this PO
    sacs = re.findall(r'SAC\*([^~]+)~', section_data)
    result['sac_total'] = 0.0
    for sac in sacs:
        parts = sac.split('*')
        if len(parts) >= 5:
            try:
                result['sac_total'] += float(parts[4])
            except (ValueError, IndexError):
                pass

    return result


def parse_edi_850(filepath):
    """Parse an EDI 850 file and extract all PO details."""
    with open(filepath) as f:
        data = f.read()

    # Get global dates from first DTM segments (before any BEG)
    first_beg = re.search(r'BEG\*', data)
    header_data = data[:first_beg.start()] if first_beg else data

    global_dates = {}
    dtms = re.findall(r'DTM\*([^~]+)~', header_data)
    for dtm in dtms:
        parts = dtm.split('*')
        if len(parts) >= 2:
            global_dates[parts[0]] = parts[1]

    # Extract individual PO sections
    sections = extract_po_sections(data)

    # Parse each PO section
    pos = []
    for section in sections:
        po = parse_po_section(section, global_dates)
        pos.append(po)

    return {
        'file': filepath,
        'po_count': len(pos),
        'pos': pos
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

        for i, po in enumerate(r['pos'], 1):
            ship_date = parse_edi_date(po.get('ship_date', ''))
            cancel_date = parse_edi_date(po.get('cancel_date', ''))
            mab_date = parse_edi_date(po.get('must_arrive_by', ''))

            qty = po.get('total_qty', 0)
            amt = po.get('total_amount', 0)
            ship_to = po.get('ship_to_name', 'N/A')

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
            fname = os.path.basename(r['file'])[:24]
            po_count = r['po_count']
            file_qty = sum(po.get('total_qty', 0) for po in r['pos'])
            file_amount = sum(po.get('total_amount', 0) for po in r['pos'])

            grand_total_qty += file_qty
            grand_total_amount += file_amount

            print(f"{fname:<25} {po_count:>5} {file_qty:>12,} {file_amount:>16,.2f}")

        print("-" * 60)
        print(f"{'GRAND TOTAL':<25} {'':>5} {grand_total_qty:>12,} {grand_total_amount:>16,.2f}")


def expand_args(args):
    """Expand glob patterns in arguments so it works on all platforms."""
    files = []
    for arg in args:
        expanded = glob.glob(arg)
        if expanded:
            files.extend(sorted(expanded))
        else:
            files.append(arg)
    return files


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 edi850_podetails.py <file1.in> [file2.in ...]")
        print("       python3 edi850_podetails.py *.in")
        print("       python3 edi850_podetails.py /path/to/*.in")
        sys.exit(1)

    files = expand_args(sys.argv[1:])

    results = []
    for filepath in files:
        try:
            result = parse_edi_850(filepath)
            results.append(result)
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")

    if results:
        print_po_details(results)


if __name__ == "__main__":
    main()
