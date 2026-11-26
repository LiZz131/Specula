# Severity Classification

## Summary

- Total entries: 3
- Critical: 0
- High: 1
- Medium: 1
- Low: 0
- Unassessed unresolved findings: 0

## Per-entry classification

| Entry | Finding | Status | Severity | Reasoning |
|---|---|---|---|---|
| 1 | MC-1 | REPRODUCED | Medium | The freshly established Leader abandons term T and starts an election at T+1 that peers holding its lease reject, leaving the cluster without a working leader for at least a lease and inflating the term (the disruption Pre-Vote is documented to prevent); with debug assertions the stale Leader object trips Engine::try_leader_handler and RaftCore panics. |
| 2 | MC-2 | REPRODUCED | High | grant_by's expect("target not in quorum set") panics and the node's RaftCore task terminates (follower or leader; debug and release builds), so the node stops serving until restarted. |
| 3 | CR-1 | FALSE POSITIVE | — | None in the implementation: the code behavior is the intended one (comments, network trait docs, Config docs, tests); only the prose is stale and should be corrected. |
