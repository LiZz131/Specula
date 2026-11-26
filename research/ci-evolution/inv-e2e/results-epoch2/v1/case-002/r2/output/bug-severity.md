# Severity Classification

## Summary

- Total entries: 4
- Critical: 0
- High: 1
- Medium: 2
- Low: 1
- Unassessed unresolved findings: 0

## Per-entry classification

| Entry | Finding | Status | Severity | Reasoning |
|---|---|---|---|---|
| 1 | MC-1 | REPRODUCED | High | A transaction the previous leader already served after its NEWLEADER quorum is missing at the next leader (lost or truncated cluster-wide). |
| 2 | CR-1 | REPRODUCED | Medium | NullPointerException in Learner.syncWithLeader; the learner abandons synchronization and cannot join until a retry avoids the interleaving. |
| 3 | CR-2 | REPRODUCED | Low | Leaked FollowerRequestProcessor/CommitProcessor/RequestThrottler threads; the orphaned SyncThread keeps flushing and dies with a critical-thread error writing to the closed learner socket. |
| 4 | CR-3 | REPRODUCED | Medium | Leader.waitForNewLeaderAck rejects the ACK as from a different epoch and the real NEWLEADER ACK is ignored; the leader does not form its NEWLEADER quorum and stalls until the init limit. |
