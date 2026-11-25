
---

## Spec fixes made during validation / checking

- R-1 follower log adoption on AppendEntries; R-2 log append not durable before a queued SaveVote; R-3 tick only after the lease expired (generation, update-relevant repairs of V0 abstractions).
- R-4 leader lease installed at establishment (found by trace `candidate_prevote_then_establish`).
- R-5 `Option<LogId>::None == None` in `LogLE` (found by reachability canaries; V0's 3-voter `MC.cfg` never reached a leader — its election coverage was vacuous).
- `EnvUpdate` rewritten (TLC evaluation error, no semantic change).
See `spec/changelog.md`.

## Coverage limits

- Bounds: 3 nodes; MaxTerm 2–3 (5 in the witness closure); MaxLogIndex 2–4; ≤6 in-flight messages; ≤3 election ticks, ≤1 operator trigger, ≤2 membership appends, ≤1 crash/restart/drop per run.
- BFS never exhausted the full-model state spaces within 30 minutes; simulation follow-ups are random and non-exhaustive.
- The U-S2 witness was found under a pruning-only search monitor (`LivelockDirectorPhased`); the unconstrained BFS reached depth 21 and did not reach the ~25-step schedule. Absence results under monitors are not claimed.
- Not modeled (inherited or excluded): leader stepping down on `HigherVote` from replication, membership payload propagation to followers, snapshots, timing (election/lease durations, Pre-Vote rate limit), the default `RaftNetworkV2::pre_vote` synthesised grant, transport framing.
- Engine-level harness: runtime wrappers (`handle_tick_election`, `ExternalCommand::Elect`, `does_pre_candidate_vote_match`) are model-checked but not traced.
