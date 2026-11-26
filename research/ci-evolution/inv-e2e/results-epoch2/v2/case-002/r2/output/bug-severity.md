# Severity Classification

## Summary

- Total entries: 3
- Critical: 0
- High: 1
- Medium: 1
- Low: 1
- Unassessed unresolved findings: 0

## Per-entry classification

| Entry | Finding | Status | Severity | Reasoning |
|---|---|---|---|---|
| 1 | MC-1 | REPRODUCED | High | A new leader is elected without the transaction that clients already read, and the old leader's only copy is truncated when it rejoins (lost committed write). |
| 2 | CR-2 | REPRODUCED | Medium | Each failed sync leaks the abandoned server's processor threads (3 failures left 3 extra CommitProcessor threads; none on the old revision); the leaked SyncThread keeps writing the shared log after the peer left the session and the peer's election vote uses a data tree older than its durable log (observed in a real trace). |
| 3 | CR-3 | REPRODUCED | Low | The leader misses its NEWLEADER quorum although every learner acked; activation waited for a learner sync timeout and re-sync (about 22 s versus under 4 s on the old revision). |
