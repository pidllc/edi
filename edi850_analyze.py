#!/usr/bin/env python3
"""
EDI 850 (Purchase Order) Analyzer
Parses and displays key information from EDI 850 files.

Usage:
    python3 edi850_analyze.py <file1.in> [file2.in ...]
    python3 edi850_analyze.py *.in
    python3 edi850_analyze.py --dir /path/to/Edifiles    # analyze all files in dir
    python3 edi850_analyze.py                             # default: ./Edifiles/
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
        raw = f.read(512)  # ISA is always at the start, first 106+ bytes

    # Find ISA segment boundaries — ISA starts at byte 0, ends at the 3rd character
    # after ISA+16th data element. The ISA segment always ends with the segment
    # terminator. We look for common patterns after "ISA*..." or "ISA|..."
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


def parse_edi_file(filepath):
    """Parse an EDI 850 file and extract all key fields."""
    seg_term_re, data_sep, gs_func_id = detect_delimiters(filepath)

    with open(filepath) as f:
        data = f.read()

    result = {
        "file": filepath,
        "raw_length": len(data),
        "gs_functional_id": gs_func_id,
        "data_sep": data_sep,
    }

    # Helper to build regex for a segment type
    def seg_pattern(seg_type):
        return r"" + seg_type + r"[" + re.escape(data_sep) + r"]([^" + seg_term_re + r"]+)" + seg_term_re

    # --- ISA Segment (Interchange Header) ---
    isa_match = re.search(seg_pattern("ISA"), data)
    if isa_match:
        parts = isa_match.group(1).split(data_sep)
        result["isa_sender_id"] = parts[7].strip() if len(parts) > 7 else ""
        result["isa_receiver_id"] = parts[5].strip() if len(parts) > 5 else ""
        result["isa_date"] = parts[8] if len(parts) > 8 else ""
        result["isa_time"] = parts[9] if len(parts) > 9 else ""
        result["isa_control"] = parts[12] if len(parts) > 12 else ""
        result["isa_version"] = parts[11] if len(parts) > 11 else ""

    # --- ST Segment (Transaction Set Header) ---
    st_match = re.search(seg_pattern("ST"), data)
    if st_match:
        parts = st_match.group(1).split(data_sep)
        result["transaction_id"] = parts[0] if len(parts) > 0 else ""
        result["transaction_control"] = parts[1] if len(parts) > 1 else ""

    # --- BEG Segment (Beginning of Purchase Order) ---
    beg_match = re.search(seg_pattern("BEG"), data)
    if beg_match:
        parts = beg_match.group(1).split(data_sep)
        result["po_purpose"] = parts[0] if len(parts) > 0 else ""
        result["po_type"] = parts[1] if len(parts) > 1 else ""
        result["po_number"] = parts[2] if len(parts) > 2 else ""
        result["po_id_referenced"] = parts[3] if len(parts) > 3 else ""
        result["po_date"] = parts[4] if len(parts) > 4 else ""

    # --- CUR Segment (Currency) ---
    cur_match = re.search(seg_pattern("CUR"), data)
    if cur_match:
        parts = cur_match.group(1).split(data_sep)
        result["currency_entity"] = parts[0] if len(parts) > 0 else ""
        result["currency_code"] = parts[1] if len(parts) > 1 else ""

    # --- REF Segments (Reference Identifiers) ---
    refs = re.findall(seg_pattern("REF"), data)
    result["refs"] = {}
    for ref in refs:
        parts = ref.split(data_sep)
        if len(parts) >= 2:
            result["refs"][parts[0]] = parts[1]

    # --- FOB Segment ---
    fob_match = re.search(seg_pattern("FOB"), data)
    if fob_match:
        result["fob"] = fob_match.group(1)

    # --- ITD Segment (Terms of Sale) ---
    itd_match = re.search(seg_pattern("ITD"), data)
    if itd_match:
        parts = itd_match.group(1).split(data_sep)
        result["terms_code"] = parts[0] if len(parts) > 0 else ""
        result["terms_basis"] = parts[1] if len(parts) > 1 else ""
        result["terms_discount_pct"] = parts[2] if len(parts) > 2 else ""
        result["terms_net_days"] = parts[4] if len(parts) > 4 else ""

    # --- DTM Segments (Date/Time References) ---
    dtms = re.findall(seg_pattern("DTM"), data)
    result["dates"] = {}
    for dtm in dtms:
        parts = dtm.split(data_sep)
        if len(parts) >= 2:
            qualifier = parts[0]
            date_val = parts[1]
            result["dates"][qualifier] = date_val

    # --- N1 Segments (Names/Locations) ---
    n1s = re.findall(seg_pattern("N1"), data)
    result["names"] = []
    for n1 in n1s:
        parts = n1.split(data_sep)
        if len(parts) >= 2:
            entry = {
                "qualifier": parts[0],
                "name": parts[1],
                "id_qual": parts[2] if len(parts) > 2 else "",
                "id": parts[3] if len(parts) > 3 else "",
            }
            result["names"].append(entry)

    # --- N3/N4 Segments (Address details) ---
    n3s = re.findall(seg_pattern("N3"), data)
    n4s = re.findall(seg_pattern("N4"), data)
    result["addresses"] = []
    for i in range(max(len(n3s), len(n4s))):
        addr = {}
        if i < len(n3s):
            parts = n3s[i].split(data_sep)
            addr["addr1"] = parts[0] if len(parts) > 0 else ""
            addr["addr2"] = parts[1] if len(parts) > 1 else ""
        if i < len(n4s):
            parts = n4s[i].split(data_sep)
            addr["city"] = parts[0] if len(parts) > 0 else ""
            addr["state"] = parts[1] if len(parts) > 1 else ""
            addr["zip"] = parts[2] if len(parts) > 2 else ""
            addr["country"] = parts[3] if len(parts) > 3 else ""
        result["addresses"].append(addr)

    # --- PO1 Segments (Line Items) ---
    po1s = re.findall(seg_pattern("PO1"), data)
    result["line_items"] = []
    result["total_line_qty"] = 0
    result["total_line_amount"] = 0.0
    for po1 in po1s:
        parts = po1.split(data_sep)
        if len(parts) >= 5:
            try:
                qty = int(parts[1])
            except (ValueError, IndexError):
                qty = 0
            try:
                price = float(parts[3])
            except (ValueError, IndexError):
                price = 0.0

            item = {
                "line": parts[0],
                "qty_ordered": qty,
                "uom": parts[2],
                "unit_price": price,
                "price_qual": parts[4] if len(parts) > 4 else "",
                "buyer_item": parts[7] if len(parts) > 7 else "",
                "upc": parts[9] if len(parts) > 9 else "",
                "vendor_style": parts[11] if len(parts) > 11 else "",
                "size": parts[17] if len(parts) > 17 else "",
            }
            result["line_items"].append(item)
            result["total_line_qty"] += qty
            result["total_line_amount"] += qty * price

    # --- SAC Segments (Allowances/Charges) ---
    sacs = re.findall(seg_pattern("SAC"), data)
    result["sac"] = []
    for sac in sacs:
        parts = sac.split(data_sep)
        if len(parts) >= 5:
            try:
                amount = float(parts[4])
            except (ValueError, IndexError):
                amount = 0.0
            result["sac"].append({
                "allow_charge": parts[0],
                "qualifier": parts[1],
                "description": parts[2] if len(parts) > 2 else "",
                "amount": amount,
                "basis": parts[5] if len(parts) > 5 else "",
            })

    # --- MTX Segments (Notes/Special Instructions) ---
    mtxs = re.findall(seg_pattern("MTX"), data)
    result["notes"] = []
    for mtx in mtxs:
        parts = mtx.split(data_sep)
        for p in parts:
            if p and p.strip():
                result["notes"].append(p.strip())

    # --- TD5 Segments (Carrier Info) ---
    td5s = re.findall(seg_pattern("TD5"), data)
    result["carrier"] = []
    for td5 in td5s:
        result["carrier"].append(td5)

    # --- CTT Segment (Transaction Totals) ---
    ctt_match = re.search(seg_pattern("CTT"), data)
    if ctt_match:
        parts = ctt_match.group(1).split(data_sep)
        result["ctt_line_count"] = parts[0] if len(parts) > 0 else ""

    # --- AMT Segment (Total Amount) ---
    amt_match = re.search(seg_pattern("AMT") + r"?\*1\*([^" + seg_term_re + r"]+)", data)
    if not amt_match:
        # Fallback: search without segment boundary
        amt_match = re.search(r"AMT" + re.escape(data_sep) + r"1" + re.escape(data_sep) + r"([^" + seg_term_re + r"]+)", data)
    if amt_match:
        try:
            result["total_amount"] = float(amt_match.group(1))
        except ValueError:
            result["total_amount"] = 0.0

    return result


def discover_edi_files(directory):
    """Discover all EDI files in a directory.

    Returns list of (filepath, gs_functional_id) tuples.
    Non-850 files are skipped with a warning.
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
    """Parse EDI date string (YYYYMMDD) to datetime."""
    if not date_str or len(date_str) < 8:
        return None
    try:
        return datetime.strptime(date_str[:8], "%Y%m%d")
    except ValueError:
        return None


def format_date(date_str):
    """Format EDI date to readable string."""
    dt = parse_edi_date(date_str)
    if dt:
        return dt.strftime("%Y-%m-%d")
    return date_str if date_str else "N/A"


def determine_file_type(result):
    """Determine the type of EDI 850 based on content."""
    refs = result.get("refs", {})
    ref_pd = refs.get("PD", "").upper()
    ref_kk = refs.get("KK", "").upper()
    line_count = len(result.get("line_items", []))
    ship_tos = [n for n in result.get("names", []) if n["qualifier"] == "ST"]

    # Check for DSV / Home Delivery
    if ref_kk == "HOME DELIVERY" or "DSV" in result.get("carrier", [""])[0:1]:
        return "DSV HOME DELIVERY"

    # Check for Replenishment
    if "POS REPLEN" in ref_pd or "REPLEN" in ref_pd:
        return "POS REPLENISHMENT"

    # Check for Rollout
    if "NEW" in ref_pd or "ROLL" in ref_pd or "LAYDOWN" in ref_pd:
        return "ROLLOUT / LAYDOWN"

    # Check by ship-to count
    if len(ship_tos) > 10:
        return "POS REPLENISHMENT (multi-DC)"

    if line_count <= 2:
        return "DROPSHIP / SINGLE ITEM"

    return "STANDARD PO"


def print_analysis(results):
    """Print comparison analysis of multiple EDI files."""
    print("\n" + "=" * 80)
    print("EDI 850 ANALYSIS REPORT")
    print("=" * 80)

    for r in results:
        print(f"\n{'─' * 80}")
        print(f"FILE: {r['file']}")
        print(f"{'─' * 80}")

        # File Info
        print(f"\n  File Size:        {r['raw_length']:,} bytes")

        # Transaction Info
        print(f"\n  ISA Sender ID:    {r.get('isa_sender_id', 'N/A')}")
        print(f"  GS Sender:        {r.get('gs_sender', 'N/A')}")
        print(f"  Transaction:      {r.get('transaction_id', 'N/A')}")

        # PO Info
        print(f"\n  PO Number:        {r.get('po_number', 'N/A')}")
        print(f"  PO Date:          {format_date(r.get('po_date', ''))}")
        print(f"  File Type:        {determine_file_type(r)}")

        # Currency
        print(f"  Currency:         {r.get('currency_code', 'USD')}")

        # Reference IDs
        refs = r.get("refs", {})
        if refs:
            print(f"\n  Reference IDs:")
            ref_labels = {
                "DP": "Department",
                "MR": "Version/Release",
                "PD": "Purpose/Type",
                "IA": "Vendor ID",
                "AN": "Account Number",
                "CO": "Contract",
                "EVI": "Source",
                "4U": "Alias",
                "KK": "Ship Method",
            }
            for k, v in sorted(refs.items()):
                label = ref_labels.get(k, k)
                print(f"    {k} ({label}): {v}")

        # Dates
        dates = r.get("dates", {})
        if dates:
            print(f"\n  Dates:")
            date_labels = {
                "001": "Delivery Requested",
                "002": "Ship Not Before",
                "004": "Order Date",
                "037": "Ship Date (Must Arrive By)",
                "038": "Cancel Date",
                "063": "Deliver By Date",
                "010": "Requested Ship",
            }
            for k, v in sorted(dates.items()):
                label = date_labels.get(k, k)
                print(f"    {label}: {format_date(v)} ({v})")

        # Payment Terms
        print(f"\n  Payment Terms:    {r.get('terms_code', 'N/A')} / {r.get('terms_basis', 'N/A')} days")
        if r.get("terms_discount_pct"):
            print(f"  Discount:         {r.get('terms_discount_pct')}%")

        # FOB
        print(f"  FOB:              {r.get('fob', 'N/A')}")

        # Carrier
        carriers = r.get("carrier", [])
        if carriers:
            print(f"  Carrier:          {carriers[0]}")

        # Names/Locations
        names = r.get("names", [])
        if names:
            print(f"\n  Locations:")
            qual_labels = {
                "ST": "Ship To",
                "BT": "Bill To",
                "SU": "Supplier",
                "BY": "Buyer",
                "SN": "Ship From",
            }
            for n in names:
                q = qual_labels.get(n["qualifier"], n["qualifier"])
                name_str = n["name"] or "(unnamed)"
                id_str = f" ({n['id']})" if n["id"] else ""
                print(f"    {q}: {name_str}{id_str}")

        # Addresses
        addrs = r.get("addresses", [])
        if addrs and addrs[0]:
            print(f"\n  Ship To Address:")
            a = addrs[0]
            print(f"    {a.get('addr1', '')} {a.get('addr2', '')}")
            print(f"    {a.get('city', '')}, {a.get('state', '')} {a.get('zip', '')} {a.get('country', '')}")

        # Allowances/Charges
        sac = r.get("sac", [])
        if sac:
            print(f"\n  Allowances/Charges:")
            for s in sac:
                type_label = "Allowance" if s["allow_charge"] == "A" else "Charge"
                qual_labels = {
                    "I410": "Off-Invoice",
                    "F910": "Freight",
                    "H000": "Handling",
                }
                qual = qual_labels.get(s["qualifier"], s["qualifier"])
                print(f"    {type_label} {qual}: ${s['amount']:,.2f}")

        # Line Items Summary
        line_items = r.get("line_items", [])
        print(f"\n  Line Items:       {len(line_items)}")
        print(f"  Total Quantity:   {r.get('total_line_qty', 0):,}")
        print(f"  Total Amount:     ${r.get('total_line_amount', 0):,.2f}")

        if r.get("total_amount"):
            print(f"  Invoice Total:    ${r['total_amount']:,.2f}")

        # Notes
        notes = r.get("notes", [])
        if notes:
            print(f"\n  Special Instructions:")
            seen = set()
            for n in notes:
                if n not in seen and n not in ("", "=" * len(n)):
                    seen.add(n)
                    print(f"    - {n}")

        # CTT
        if r.get("ctt_line_count"):
            print(f"\n  CTT Line Count:   {r['ctt_line_count']}")

    # Summary comparison table
    print(f"\n{'=' * 100}")
    print("SUMMARY TABLE")
    print(f"{'=' * 100}")
    print(
        f"{'File':<24} {'Type':<14} {'Qty':>8} {'POs':>5} {'Amount':>14} "
        f"{'Ship Date':>11} {'Cancel':>11} {'MAB By':>11} "
        f"{'DSV':^5} {'Roll':^5} {'Repl':^5} {'Ship To'}"
    )
    print("-" * 100)

    for r in results:
        fname = r["file"].split("/")[-1][-22:]
        ftype = determine_file_type(r)

        if "DSV" in ftype:
            short_type = "DSV"
        elif "REPLEN" in ftype:
            short_type = "Replen"
        elif "ROLLOUT" in ftype:
            short_type = "Rollout"
        else:
            short_type = ftype[:13]

        qty = r.get("total_line_qty", 0)
        lines = len(r.get("line_items", []))
        amt = r.get("total_line_amount", 0)
        dates = r.get("dates", {})

        ship_date = format_date(dates.get("037", ""))
        cancel_date = format_date(dates.get("038", ""))
        mab_date = format_date(dates.get("063", ""))

        is_dsv = "Y" if "DSV" in ftype else "N"
        is_rollout = "Y" if "ROLLOUT" in ftype else "N"
        is_replen = "Y" if "REPLEN" in ftype else "N"

        ship_tos = [n for n in r.get("names", []) if n["qualifier"] == "ST"]
        if len(ship_tos) == 1:
            ship_to = ship_tos[0]["name"][:30] if ship_tos[0]["name"] else "1 DC"
        elif len(ship_tos) > 1:
            ship_to = f"{len(ship_tos)} DCs"
        else:
            ship_to = "N/A"

        print(
            f"{fname:<24} {short_type:<14} {qty:>8,} {lines:>5} {amt:>14,.2f} "
            f"{ship_date:>11} {cancel_date:>11} {mab_date:>11} "
            f"{is_dsv:^5} {is_rollout:^5} {is_replen:^5} {ship_to}"
        )


def main():
    # If --dir is provided, discover files from that directory
    # If no args at all, default to ./Edifiles/ relative to script location
    # If positional args, use them as file paths

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
            print("  python3 edi850_analyze.py <file1> [file2 ...]")
            print("  python3 edi850_analyze.py --dir /path/to/Edifiles")
            print("  python3 edi850_analyze.py '/path/to/folder/*850*'")
            print("  python3 edi850_analyze.py              # default: ./Edifiles/ next to script")
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
        # Default: look for Edifiles/ next to the script
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
            print("Usage: python3 edi850_analyze.py <file1> [file2 ...]")
            print("       python3 edi850_analyze.py --dir /path/to/Edifiles")
            print("       python3 edi850_analyze.py '/path/to/folder/*850*'")
            sys.exit(1)

    results = []
    for filepath in filepaths:
        try:
            result = parse_edi_file(filepath)
            results.append(result)
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")

    if results:
        print_analysis(results)


if __name__ == "__main__":
    main()
