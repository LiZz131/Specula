# Severity Classification

## Summary

- Total entries: 3
- Critical: 0
- High: 1
- Medium: 2
- Low: 0
- Unassessed unresolved findings: 0

## Per-entry classification

| Entry | Finding | Status | Severity | Reasoning |
|---|---|---|---|---|
| 1 | MC-1 | REPRODUCED | High | The established leader starts a new election at term+1 without any external request or higher term: leadership is abandoned and the term inflates; the stale Leader object (vote behind state.vote) trips the try_leader_handler assertion (RaftCore panic in debug builds) and, in release builds, the cluster stayed leaderless with the term inflating. |
| 2 | MC-2 | REPRODUCED | Medium | RaftCore panics ('target not in quorum set') and the node stops serving (Fatal::Panicked), in debug and release builds. |
| 3 | MC-3 | REPRODUCED | Medium | RaftCore panics ('target not in quorum set') and the node stops serving, in debug and release builds. |
