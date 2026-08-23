# Pick Ticket Creation - Database Comparison

**Date:** 2026-08-22  
**Order:** 1991330 (ROSS STORES INC., Style D425206 BLACK + D425214 SURF GREY)

---

## Summary

| Metric | wf125sR_82026 | flask_82026 |
|--------|--------------|-------------|
| Pick Number | 976017 | 976021 |
| Total Audit Events | 95 | 90 |
| Tables Affected | 14 | 14 |
| Duration | ~4.1s (01:14:37.21 → 01:14:41.37) | ~0.3s (01:11:57.41 → 01:11:57.74) |
| invhead_box DELETE | Yes | No |
| Final pickheader UPDATE | Yes (3s later) | No |
| pickheader_log entries | 3 | 1 |

---

## Event Sequence Comparison

### wf125sR_82026 (95 events)

```
01:14:37.216  INSERT pickheader_log
01:14:37.232  INSERT pickheader
01:14:37.279  DELETE invhead_box          ← NOT IN flask
01:14:37.279  UPDATE pickheader           ← NOT IN flask
01:14:37.294  INSERT pickheader_log ×2    ← flask has only 1
01:14:37.388  UPDATE sodetail
01:14:37.669  UPDATE ecomm_inventory_update_temp ×2
01:14:37.701  UPDATE ivtf ×2 + ecomm ×2
01:14:37.748  UPDATE soheader ×2
01:14:37.794  DELETE code_sku ×2 + UPDATE customer ×2
01:14:37.810  UPDATE soheader ×4 + DELETE code_sku ×4 + UPDATE customer ×4
01:14:37.951  UPDATE logfdetail
01:14:38.138  UPDATE cutdetail
01:14:38.169  UPDATE logfdetail + sodetail
01:14:38.185  UPDATE sodetail
01:14:38.419  DELETE ivtf ×2 + UPDATE cutdetail + UPDATE ivtf
01:14:38.466  UPDATE pickdetail
01:14:38.482  INSERT pickdetail_log + INSERT pickdetail
01:14:38.482  UPDATE sodetail + ecomm ×4 + ivtf ×2 + soheader ×4 + code_sku ×4 + customer ×4
01:14:38.498  UPDATE logfdetail + cutdetail + sodetail + DELETE ivtf ×2 + UPDATE ivtf
01:14:38.498  UPDATE pickdetail + INSERT pickdetail_log + INSERT pickdetail
01:14:38.513  UPDATE sodetail ×2
01:14:41.372  UPDATE pickheader           ← NOT IN flask
```

### flask_82026 (90 events)

```
01:11:57.417  INSERT pickheader_log       ← only 1 (vs 3 in wf125sR)
01:11:57.417  INSERT pickheader
01:11:57.526  INSERT pickdetail           ← first detail immediately
01:11:57.526  UPDATE ecomm_inventory_update_temp ×2
01:11:57.542  UPDATE ivtf ×2 + ecomm ×2 + soheader ×2 + code_sku ×2 + customer ×2
01:11:57.542  UPDATE soheader ×4 + DELETE code_sku ×4 + UPDATE customer ×4
01:11:57.542  UPDATE logfdetail + cutdetail
01:11:57.558  DELETE ivtf ×2 + UPDATE cutdetail + sodetail + ivtf
01:11:57.558  UPDATE pickdetail + INSERT pickdetail_log
01:11:57.604  UPDATE sodetail
01:11:57.683  INSERT pickdetail (line 2)
01:11:57.683  UPDATE ecomm ×4 + ivtf ×2 + soheader ×4 + code_sku ×4 + customer ×4
01:11:57.698  UPDATE logfdetail + cutdetail + sodetail + DELETE ivtf ×2 + UPDATE ivtf
01:11:57.698  UPDATE pickdetail + INSERT pickdetail_log
01:11:57.745  UPDATE sodetail
```

---

## Key Differences

### 1. invhead_box Deletion (wf125sR only)
- **wf125sR**: DELETE invhead_box → UPDATE pickheader (assigns box to pick)
- **flask**: Not triggered — no invhead_box table activity
- **Impact**: wf125sR performs an extra step to link inventory boxing to the pick

### 2. pickheader_log Entries
- **wf125sR**: 3 INSERT entries (initial log + 2 detail logs)
- **flask**: 1 INSERT entry (initial log only)
- **Impact**: wf125sR logs more granular state changes on the pick header

### 3. Pick Detail Creation Order
- **wf125sR**: pickdetail created AFTER inventory allocation (lines 48-49)
- **flask**: pickdetail created BEFORE allocation (line 3), then updated
- **Impact**: Different workflow — flask creates detail first then allocates, wf125sR allocates then creates

### 4. Final pickheader UPDATE (wf125sR only)
- **wf125sR**: Final UPDATE 3s after creation (sets totals, status)
- **flask**: No final UPDATE — header created once
- **Impact**: wf125sR does a two-phase header creation (create → finalize)

### 5. Processing Speed
- **wf125sR**: 4.1 seconds total (slower, more steps)
- **flask**: 0.3 seconds total (faster, streamlined)
- **Impact**: flask appears to use a more optimized pick creation path

---

## Tables Affected (Same in Both)

| Table | INSERT | UPDATE | DELETE |
|-------|--------|--------|--------|
| pickheader | 1 | 1-2 | 0 |
| pickheader_log | 1-3 | 0 | 0 |
| pickdetail | 2 | 2 | 0 |
| pickdetail_log | 2 | 0 | 0 |
| sodetail | 0 | 8 | 0 |
| soheader | 0 | 16 | 0 |
| ivtf | 0 | 6 | 4 |
| cutdetail | 0 | 4 | 0 |
| logfdetail | 0 | 4 | 0 |
| ecomm_inventory_update_temp | 0 | 8 | 0 |
| customer | 0 | 16 | 0 |
| code_sku | 0 | 0 | 16 |
| invhead_box | 0 | 0 | 0-1 |

---

## Conclusion

Both databases executed the same pick ticket for the same order (1991330) with the same line items. The workflow differences suggest:

1. **wf125sR_82026** uses a more verbose logging approach (extra pickheader_log entries, final pickheader UPDATE)
2. **flask_82026** uses a streamlined approach (single header log, no final UPDATE)
3. The invhead_box DELETE in wf125sR may indicate different inventory boxing configuration
4. Both databases capture the same core tables (pickheader, pickdetail, sodetail, ivtf, etc.)

The audit triggers are working correctly in both databases and capturing all changes.
