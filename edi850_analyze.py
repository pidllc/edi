#!/usr/bin/env python3
"""
EDI 850 (Purchase Order) Analyzer
Parses and displays key information from EDI 850 files.

Usage:
    python3 edi850_analyze.py <file1.in> [file2.in ...]
    python3 edi850_analyze.py *.in
"""

import sys
import re
from datetime import datetime


def parse_edi_file(filepath):
    """Parse an EDI 850 file and extract all key fields."""
    with open(filepath) as f:
        data = f.read()

    result = {"file": filepath, "raw_length": len(data)}

    # --- ISA Segment (Interchange Header) ---
    isa_match = re.search(r"ISA\*(.+?)~", data)
    if isa_match:
        parts = isa_match.group(1).split("*")
        result["isa_sender_id"] = parts[7].strip() if len(parts) > 7 else ""
        result["isa_receiver_id"] = parts[5].strip() if len(parts) > 5 else ""
        result["isa_date"] = parts[8] if len(parts) > 8 else ""
        result["isa_time"] = parts[9] if len(parts) > 9 else ""
        result["isa_control"] = parts[12] if len(parts) > 12 else ""
        result["isa_version"] = parts[11] if len(parts) > 11 else ""

    # --- GS Segment (Functional Group) ---
    gs_match = re.search(r"GS\*([^~]+)~", data)
    if gs_match:
        parts = gs_match.group(1).split("*")
        result["gs_functional_id"] = parts[0] if len(parts) > 0 else ""
        result["gs_sender"] = parts[2].strip() if len(parts) > 2 else ""
        result["gs_receiver"] = parts[3].strip() if len(parts) > 3 else ""

    # --- ST Segment (Transaction Set Header) ---
    st_match = re.search(r"ST\*([^~]+)~", data)
    if st_match:
        parts = st_match.group(1).split("*")
        result["transaction_id"] = parts[0] if len(parts) > 0 else ""
        result["transaction_control"] = parts[1] if len(parts) > 1 else ""

    # --- BEG Segment (Beginning of Purchase Order) ---
    beg_match = re.search(r"BEG\*([^~]+)~", data)
    if beg_match:
        parts = beg_match.group(1).split("*")
        result["po_purpose"] = parts[0] if len(parts) > 0 else ""
        result["po_type"] = parts[1] if len(parts) > 1 else ""
        result["po_number"] = parts[2] if len(parts) > 2 else ""
        result["po_id_referenced"] = parts[3] if len(parts) > 3 else ""
        result["po_date"] = parts[4] if len(parts) > 4 else ""

    # --- CUR Segment (Currency) ---
    cur_match = re.search(r"CUR\*([^~]+)~", data)
    if cur_match:
        parts = cur_match.group(1).split("*")
        result["currency_entity"] = parts[0] if len(parts) > 0 else ""
        result["currency_code"] = parts[1] if len(parts) > 1 else ""

    # --- REF Segments (Reference Identifiers) ---
    refs = re.findall(r"REF\*([^~]+)~", data)
    result["refs"] = {}
    for ref in refs:
        parts = ref.split("*")
        if len(parts) >= 2:
            result["refs"][parts[0]] = parts[1]

    # --- FOB Segment ---
    fob_match = re.search(r"FOB\*([^~]+)~", data)
    if fob_match:
        result["fob"] = fob_match.group(1)

    # --- ITD Segment (Terms of Sale) ---
    itd_match = re.search(r"ITD\*([^~]+)~", data)
    if itd_match:
        parts = itd_match.group(1).split("*")
        result["terms_code"] = parts[0] if len(parts) > 0 else ""
        result["terms_basis"] = parts[1] if len(parts) > 1 else ""
        result["terms_discount_pct"] = parts[2] if len(parts) > 2 else ""
        result["terms_net_days"] = parts[4] if len(parts) > 4 else ""

    # --- DTM Segments (Date/Time References) ---
    dtms = re.findall(r"DTM\*([^~]+)~", data)
    result["dates"] = {}
    for dtm in dtms:
        parts = dtm.split("*")
        if len(parts) >= 2:
            qualifier = parts[0]
            date_val = parts[1]
            result["dates"][qualifier] = date_val

    # --- N1 Segments (Names/Locations) ---
    n1s = re.findall(r"N1\*([^~]+)~", data)
    result["names"] = []
    for n1 in n1s:
        parts = n1.split("*")
        if len(parts) >= 2:
            entry = {
                "qualifier": parts[0],
                "name": parts[1],
                "id_qual": parts[2] if len(parts) > 2 else "",
                "id": parts[3] if len(parts) > 3 else "",
            }
            result["names"].append(entry)

    # --- N3/N4 Segments (Address details) ---
    n3s = re.findall(r"N3\*([^~]+)~", data)
    n4s = re.findall(r"N4\*([^~]+)~", data)
    result["addresses"] = []
    for i in range(max(len(n3s), len(n4s))):
        addr = {}
        if i < len(n3s):
            parts = n3s[i].split("*")
            addr["addr1"] = parts[0] if len(parts) > 0 else ""
            addr["addr2"] = parts[1] if len(parts) > 1 else ""
        if i < len(n4s):
            parts = n4s[i].split("*")
            addr["city"] = parts[0] if len(parts) > 0 else ""
            addr["state"] = parts[1] if len(parts) > 1 else ""
            addr["zip"] = parts[2] if len(parts) > 2 else ""
            addr["country"] = parts[3] if len(parts) > 3 else ""
        result["addresses"].append(addr)

    # --- PO1 Segments (Line Items) ---
    po1s = re.findall(r"PO1\*([^~]+)~", data)
    result["line_items"] = []
    result["total_line_qty"] = 0
    result["total_line_amount"] = 0.0
    for po1 in po1s:
        # PO1*line*qty*uom*price*price_qual*item_qual*item*upc_qual*upc*vn_qual*vn*size_qual*size
        parts = po1.split("*")
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
    sacs = re.findall(r"SAC\*([^~]+)~", data)
    result["sac"] = []
    for sac in sacs:
        parts = sac.split("*")
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
    mtxs = re.findall(r"MTX\*([^~]+)~", data)
    result["notes"] = []
    for mtx in mtxs:
        parts = mtx.split("*")
        for p in parts:
            if p and p.strip():
                result["notes"].append(p.strip())

    # --- TD5 Segments (Carrier Info) ---
    td5s = re.findall(r"TD5\*([^~]+)~", data)
    result["carrier"] = []
    for td5 in td5s:
        result["carrier"].append(td5)

    # --- CTT Segment (Transaction Totals) ---
    ctt_match = re.search(r"CTT\*([^~]+)~", data)
    if ctt_match:
        parts = ctt_match.group(1).split("*")
        result["ctt_line_count"] = parts[0] if len(parts) > 0 else ""

    # --- AMT Segment (Total Amount) ---
    amt_match = re.search(r"AMT\*1\*([^~]+)~", data)
    if amt_match:
        try:
            result["total_amount"] = float(amt_match.group(1))
        except ValueError:
            result["total_amount"] = 0.0

    return result


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
            # Deduplicate and limit
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
        f"{'File':<22} {'Type':<14} {'Qty':>8} {'POs':>5} {'Amount':>14} "
        f"{'Ship Date':>11} {'Cancel':>11} {'MAB By':>11} "
        f"{'DSV':^5} {'Roll':^5} {'Repl':^5} {'Ship To'}"
    )
    print("-" * 100)

    for r in results:
        fname = r["file"].split("/")[-1][:21]
        ftype = determine_file_type(r)

        # Short type labels
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

        # Flags
        is_dsv = "Y" if "DSV" in ftype else "N"
        is_rollout = "Y" if "ROLLOUT" in ftype else "N"
        is_replen = "Y" if "REPLEN" in ftype else "N"

        # Ship To summary
        ship_tos = [n for n in r.get("names", []) if n["qualifier"] == "ST"]
        if len(ship_tos) == 1:
            ship_to = ship_tos[0]["name"][:30] if ship_tos[0]["name"] else "1 DC"
        elif len(ship_tos) > 1:
            ship_to = f"{len(ship_tos)} DCs"
        else:
            ship_to = "N/A"

        print(
            f"{fname:<22} {short_type:<14} {qty:>8,} {lines:>5} {amt:>14,.2f} "
            f"{ship_date:>11} {cancel_date:>11} {mab_date:>11} "
            f"{is_dsv:^5} {is_rollout:^5} {is_replen:^5} {ship_to}"
        )


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 edi850_analyze.py <file1.in> [file2.in ...]")
        print("       python3 edi850_analyze.py *.in")
        sys.exit(1)

    results = []
    for filepath in sys.argv[1:]:
        try:
            result = parse_edi_file(filepath)
            results.append(result)
        except Exception as e:
            print(f"Error parsing {filepath}: {e}")

    if results:
        print_analysis(results)


if __name__ == "__main__":
    main()
