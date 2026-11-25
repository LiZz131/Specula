# Incremental CI report

MODEL_CHANGE_REQUIRED: the update adds an optional Pre-Vote round. The reference, MC, Trace, and harness were updated (plus repairs of pre-existing model defects), 21 fresh traces validate, and model checking found two update-introduced defects, both reproduced through the public Raft API: stale Pre-Vote responses from an earlier round are counted (RaftCore panics when the responder was removed), and a Pre-Vote round started while Candidate survives leader establishment so the new Leader re-elects.

CI verdict: **FAIL**. Reproduced bugs: 2; other unresolved findings: 0; other dispositions: 1.

[Findings and evidence](confirmed-bugs.md) · [Severity](bug-severity.md)

## Validation limits

- Bounded three-node model (MaxTerm 2, MaxLogIndex 4, bounded election/membership/crash/drop counters and message bag); 30-minute BFS runs did not exhaust their queues and simulations are sampled (spec/output/campaigns.md).
- Model time is abstract: tick restarts and response delays are unconstrained; reachability of each finding was confirmed in code (spec/confirmation-MC-1.md, spec/confirmation-MC-2.md).
- Follower-side membership replication and the leadership-transfer lease bypass are not modeled (V0 abstractions kept); the MC-1 panic is reached through leader-side membership change.
- Engine-level traces cannot observe the RaftCore Pre-Vote response filter; it is exercised by the integration reproduction.
- Old-revision controls are not applicable: the old revision has no Pre-Vote round or Trigger::elect(bool).
- No fairness or liveness claim.
