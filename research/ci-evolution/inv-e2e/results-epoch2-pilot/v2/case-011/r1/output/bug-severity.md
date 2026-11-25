# Severity Classification

## Summary

- Total entries: 3
- Critical: 0
- High: 2
- Medium: 0
- Low: 0
- Unassessed unresolved findings: 0

## Per-entry classification

| Entry | Finding | Status | Severity | Reasoning |
|---|---|---|---|---|
| 1 | MC-1 | REPRODUCED | High | The grant is tallied by the wrong round: RaftCore panics (Fatal::Panicked) when the responder is no longer a voter, and otherwise a real election can start on grants the current round never received, inflating the term. |
| 2 | MC-2 | REPRODUCED | High | The freshly established Leader steps down and starts an election at term+1 (term inflation, leadership loss); in debug builds RaftCore panics on try_leader_handler's assertion leader.vote >= state.vote. |
| 3 | CR-1 | FALSE POSITIVE | — | No behavioral consequence: code, code comments, and tests agree; only the document is stale. |
