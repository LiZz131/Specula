# Severity Classification

## Summary

- Total entries: 5
- Critical: 1
- High: 2
- Medium: 1
- Low: 1
- Unassessed unresolved findings: 0

## Per-entry classification

| Entry | Finding | Status | Severity | Reasoning |
|---|---|---|---|---|
| 1 | MC-1 | REPRODUCED | Critical | A transaction the old leader served after the NEWLEADER quorum is missing on the new leader (committed data lost). |
| 2 | MC-2 | REPRODUCED | High | Leader.waitForNewLeaderAck discards the ACK as from a different epoch; the re-elected leader fails to establish its epoch and times out, and an established leader loses that proposal ACK. |
| 3 | MC-3 | REPRODUCED | High | NullPointerException in Learner.syncWithLeader aborts synchronization; the learner returns to LOOKING and cannot join under load. |
| 4 | CR-4 | REPRODUCED | Medium | SyncThread and CommitProcessor threads keep running after shutdown, the data tree is not fast-forwarded, and the orphaned SyncThread keeps writing the shared log and ACKs to a dead connection. |
| 5 | CR-5 | REPRODUCED | Low | NullPointerException in Learner.syncWithLeader; the learner never reaches a running BROADCAST state. |
