# Pick Ticket Comparison Report

**Report Date:** 2026-08-23  
**Databases:** wfashion vs flask  
**Server:** 192.168.168.106:2436

---

## Row Count Comparison

| Table | wfashion | flask | Delta | Notes |
|-------|----------|-------|-------|-------|
| pickdetail | 589,733 | 589,732 | **wfashion +1** | Pick detail records |
| pickdetail_log | 1,813,817 | 1,813,816 | **wfashion +1** | Pick detail audit log |
| pickheader_log | 1,075,881 | 1,075,879 | **wfashion +2** | Pick header audit log |
| edi_po | 315,884 | 315,884 | ✅ Identical | EDI purchase orders |

---

## Analysis

### Pick Processing Activity
- wfashion shows **+1 pickdetail** record vs flask
- wfashion shows **+1 pickdetail_log** entry (audit trail for the pick)
- wfashion shows **+2 pickheader_log** entries (header-level audit)

This suggests pick ticket processing was run on wfashion but not on flask.

### EDI Status
- edi_po tables are **in sync** between both databases
- No EDI processing differences detected

---

## Comparison History

| Date | pickdetail (wf/fl) | pickdetail_log (wf/fl) | pickheader_log (wf/fl) | edi_po (wf/fl) | Notes |
|------|-------------------|----------------------|----------------------|----------------|-------|
| 2026-08-23 | 589,733 / 589,732 | 1,813,817 / 1,813,816 | 1,075,881 / 1,075,879 | 315,884 / 315,884 | After pick processing on wfashion |
