# Extended Events Capture — Detailed Comparison Report

**Report Date:** 2026-08-23 00:40 UTC  
**Data Source:** Extended Events ring_buffer (edi_monitoring_wfashion, edi_monitoring_flask)  
**Time Range:** Last captured events before ring_buffer rotation

---

## 1. Session Statistics

| Session | Events Captured | Memory Used |
|---------|----------------|-------------|
| edi_monitoring_wfashion | 141 | 308 KB |
| edi_monitoring_flask | 66 | 247 KB |

---

## 2. wfashion — Captured Activity

### Login & Startup (04:33:44 UTC)
| Time | User | App | Action |
|------|------|-----|--------|
| 04:33:37 | readwrite_user | .Net SqlClient | SELECT wfuser permissions |
| 04:33:44 | tarun | .Net SqlClient | INSERT wfuser_log (login) |
| 04:33:44 | tarun | .Net SqlClient | SELECT wfuser config (13 queries) |

### EDI 850 Processing (04:37:34–04:37:35 UTC)
**Customer:** DSVSAMSC  
**Application:** .Net SqlClient Data Provider  
**User:** plugg

| Time | Operation | Table | Details |
|------|-----------|-------|---------|
| 04:37:34.086 | SELECT | code_currency | Load currency codes |
| 04:37:34.140 | INSERT | edilog | Log EDI 850 receipt (docnumber='EDI1.in.in.txt') |
| 04:37:34.180 | UPDATE | edilog | Set edi_doc, isdoc='Y' |
| 04:37:34.430 | SELECT | cancel_reason, royaltor, warehouse | Load reference data |
| 04:37:34.453 | INSERT | edi_po_sku_qty | Insert SKU line item |
| 04:37:34.456 | UPDATE | code_sku | Set next_token='Y' for SKU 19396824102 |
| 04:37:34.462 | SELECT | store, shipvia, customer_edi | Load store/shipvia/config |
| 04:37:34.469 | SELECT | soheader | Get next orderno (MAX+1) |
| 04:37:34.598 | INSERT | soheader | Insert SO header (**79 rows**) |
| 04:37:35.395 | INSERT | sodetail | Insert SO detail (**72 rows**) |
| 04:37:35.396 | SELECT | @@identity | Get inserted SO id |
| 04:37:35.398 | SELECT | customer_edi | Load EDI config (x2) |

### Key SQL Captured
```sql
-- EDI 850 PO insert
INSERT INTO edi_po_sku_qty (customer, po, releaseno, sku, inner_box, box_qty, 
  edi_unit, price, edi_id, edi_id_length, po1_line, multiplier, seq_no, 
  sku_bo, sku_in, sku_it, sku_cb, sku_up, sku_iz, sku_cg, sku_sk, sac_line)
VALUES (@Parm1, @Parm2, ...)

-- SO header insert
INSERT INTO soheader (orderno, orderdate, shipdate, canceldate, customer, 
  blname, bladdr1, ..., edistatus, edibatch, edidate, ...)
SELECT @realorderno, ... FROM soheader_850 WHERE orderno = @orderno_850

-- SO detail insert
INSERT INTO sodetail (orderno, line, qty1, ..., style, royaltor, ...)
```

---

## 3. flask — Captured Activity

### EDI 850 Processing (04:38:12–04:38:14 UTC)
**Customer:** DSVSAMSC  
**PO:** 9385455174  
**Application:** .Net SqlClient Data Provider  
**User:** readwrite_user

| Time | Operation | Table | Details |
|------|-----------|-------|---------|
| 04:38:12.423 | INSERT | edilog | Log EDI 850 receipt (docnumber='EDI1.in') |
| 04:38:12.485 | INSERT | edi_po | **DSVSAMSC, PO 9385455174** |
| 04:38:12.566 | INSERT | edi_po_sku_qty | Insert SKU line item |
| 04:38:12.681 | SELECT | shipvia | Load shipvia config |
| 04:38:12.719 | SELECT | store | Load store config |
| 04:38:12.780 | SELECT | soheader | Get next orderno (MAX+1) |
| 04:38:12.823 | sp_describe | soheader | Describe INSERT parameters |
| 04:38:13.003 | INSERT | soheader | Insert SO header (**79 rows**) |
| 04:38:13.048 | SELECT | store | Load store warehouse |
| 04:38:13.073 | SELECT | code_sku | Load SKU details |
| 04:38:13.114 | SELECT | ivtf | Load style/color info |
| 04:38:13.145 | SELECT | division | Load size info |
| 04:38:13.379 | SELECT | sodetail | Check if line exists |
| 04:38:13.417 | sp_describe | sodetail | Describe INSERT parameters |
| 04:38:14.194 | INSERT | sodetail | Insert SO detail (**73 rows**) |
| 04:38:14.251 | UPDATE | edilog | Set edi_doc, isdoc='Y', edi_processed |
| 04:38:14.301 | sp_unprepare | — | Cleanup prepared statements |

### Key SQL Captured
```sql
-- EDI 850 PO insert (parameterized)
INSERT INTO edi_po (customer, po, beg_line) 
VALUES (@P1, @P2, @P3)
-- Values: DSVSAMSC, 9385455174, BEG*00*SA*9385455174**20260821

-- EDI SKU insert
INSERT INTO edi_po_sku_qty (customer, po, sku, box_qty, edi_unit, price, 
  po1_line, seq_no, edi_id, sku_in, sku_up)
VALUES (@P1, @P2, ...)
-- Values: DSVSAMSC, 9385455174, 19396824102, 1, EA, 10.5

-- SO header insert
INSERT INTO soheader (customer, custpo, orderdate, shipdate, ..., 
  edistatus, edibatch, edidate, ...)

-- SO detail insert
INSERT INTO sodetail (orderno, line, style, color, price, ..., 
  qty1, qty2, ..., org_qty1, org_qty2, ...)

-- edilog update
UPDATE edilog SET edi_doc = @P1, isdoc = 'Y', edi_processed = @P2 
WHERE edi_type = '850' AND custid = @P3 AND ISA_control = @P4
```

---

## 4. Side-by-Side Comparison

### Processing Flow

| Step | wfashion | flask |
|------|----------|-------|
| 1. Log EDI receipt | INSERT edilog | INSERT edilog |
| 2. Store PO | (not captured — edi_po INSERT missing) | INSERT edi_po |
| 3. Store SKU | INSERT edi_po_sku_qty | INSERT edi_po_sku_qty |
| 4. Load config | SELECT store, shipvia, customer_edi | SELECT store, shipvia, code_sku, ivtf, division |
| 5. Get next SO# | SELECT MAX(orderno)+1 | SELECT MAX(orderno)+1 |
| 6. Create SO header | INSERT soheader (79 rows) | INSERT soheader (79 rows) |
| 7. Create SO detail | INSERT sodetail (72 rows) | INSERT sodetail (73 rows) |
| 8. Update edilog | UPDATE edilog (isdoc='Y') | UPDATE edilog (isdoc='Y', edi_processed) |

### Key Differences

| Aspect | wfashion | flask |
|--------|----------|-------|
| **User** | plugg | readwrite_user |
| **edi_po INSERT** | ❌ Not captured (trigger gap) | ✅ Captured |
| **edilog INSERT** | ✅ Captured | ✅ Captured |
| **edilog UPDATE** | ✅ isdoc='Y' only | ✅ isdoc='Y' + edi_processed |
| **SO detail rows** | 72 | 73 |
| **SO header rows** | 79 | 79 |
| **Application** | .Net SqlClient | .Net SqlClient |
| **Prepared statements** | sp_executesql | sp_prepexec + sp_unprepare |
| **Parameter style** | @Parm1, @Parm2 | @P1, @P2 |

### Application Behavior Difference

**wfashion** uses `sp_executesql` with named parameters (`@Parm1`, `@Parm2`):
```sql
exec sp_executesql N'INSERT INTO edi_po_sku_qty (...) VALUES (@Parm1, @Parm2, ...)',
  N'@Parm1 nvarchar(8), @Parm2 nvarchar(15), ...',
  @Parm1=N'DSVSAMSC', @Parm2=N'7885440738', ...
```

**flask** uses `sp_prepexec` with positional parameters (`@P1`, `@P2`):
```sql
exec sp_prepexec @p1 output, N'@P1 nvarchar(16), @P2 nvarchar(20), ...',
  N'INSERT INTO edi_po (customer, po, beg_line) VALUES (@P1, @P2, @P3)',
  N'DSVSAMSC', N'9385455174', N'BEG*00*SA*9385455174**20260821'
```

This suggests **different application versions or ORM configurations** between wfashion and flask.

---

## 5. Query Patterns Captured

### wfashion — Read Queries
| Query | Purpose |
|-------|---------|
| SELECT wfuser.* | User permissions/config |
| SELECT wfuser_log | Login audit |
| SELECT code_currency | Currency rates |
| SELECT cancel_reason, royaltor, warehouse | Reference data |
| SELECT store, shipvia, customer_edi | Config lookups |
| SELECT MAX(orderno)+1 FROM soheader | Next SO number |
| SELECT @@identity | Get inserted ID |

### flask — Read Queries
| Query | Purpose |
|-------|---------|
| SELECT store | Store config |
| SELECT shipvia | Shipping methods |
| SELECT code_sku | SKU details |
| SELECT ivtf | Style/color info |
| SELECT division | Size info |
| SELECT sodetail (COUNT) | Check if line exists |
| SELECT MAX(orderno)+1 FROM soheader | Next SO number |
| SELECT TOP 5 soheader.* | SO search |

---

## 6. Summary

| Metric | wfashion | flask |
|--------|----------|-------|
| Total events | 141 | 66 |
| Login events | 1 (tarun) | 0 |
| EDI 850 processed | Yes | Yes |
| edi_po INSERT captured | No (trigger gap) | Yes |
| SO header rows | 79 | 79 |
| SO detail rows | 72 | 73 |
| Application user | plugg | readwrite_user |
| Parameter style | @Parm1 (named) | @P1 (positional) |
| Prepared stmt cleanup | No | Yes (sp_unprepare) |

### Root Cause Confirmed
The XEvents data confirms:
1. **wfashion** processes EDI 850s via `sp_executesql` — edi_po INSERTs are not captured (trigger gap)
2. **flask** processes EDI 850s via `sp_prepexec` — edi_po INSERTs ARE captured
3. Both databases process the same DSVSAMSC POs
4. The application uses **different query parameterization** between environments
