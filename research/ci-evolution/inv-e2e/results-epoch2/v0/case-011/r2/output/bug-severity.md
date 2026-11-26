# Severity Classification

## Summary

- Total entries: 2
- Critical: 0
- High: 1
- Medium: 0
- Low: 0
- Unassessed unresolved findings: 0

## Per-entry classification

| Entry | Finding | Status | Severity | Reasoning |
|---|---|---|---|---|
| 1 | MC-1 | REPRODUCED | High | The healthy term-T Leader bumps its own term to T+1 while keeping a Leader object at (T, committed); RaftCore::trigger_routine_actions -> try_leader_handler hits debug_assert leader.vote >= state.vote and the core panics (Fatal::Panicked); in release builds the Leader runs behind its persisted vote. |
| 2 | CR-1 | FALSE POSITIVE | — | None at runtime: the failed reply is dropped (not a grant), as the repository test pre_vote_unreachable_peer_is_not_a_grant confirms; only the documentation is stale. |
