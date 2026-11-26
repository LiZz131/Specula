# Validation handoff (incremental run, update 2efbdfc)

- **Source under test**: artifact commit `2efbdfc3754df193bce05b9792297c813377cdaf`
  (unchanged; instrumented copy `harness/work-source`, patch
  `harness/patches/instrumentation.patch`, sha256 in `provenance-manifest.json`).
- **Harness command**: `SPECULAR_REUSE_WORK_SOURCE=1 timeout 3000s harness/run.sh`
  (full rebuild: `timeout 3000s harness/run.sh`); log `spec/output/harness-run-2.log`.
- **Fresh traces** (all retained, all replayed): `traces/follower-snap.ndjson`,
  `traces/follower-diff.ndjson`, `traces/quorum-startup-mutation-shutdown.ndjson`,
  `traces/leader-abandon-restart-recovery.ndjson`,
  `traces/diff-sync-uncommitted-log.ndjson` — inventory and hashes:
  `spec/output/trace-validation/inventory.md`.
- **Final regression**: round r9 (`spec/output/trace-validation/r9/`) on the
  final `base.tla`/`Trace.tla`: 5/5 pass with `TraceMatched` and 8 invariants;
  each run has events+1 distinct states and 0 queued states.
- **Affected/interaction coverage** (fresh traces): `SyncProposalBuffered`
  (4), `SyncCommitBuffered` (4), `NewLeaderAck` (14), `NewLeaderAckCounted`
  (14), leader activation `PhaseChanged broadcast` with ack-quorum check (all
  quorum traces), `BroadcastReady` (UPTODATE) after `NewLeaderAck`, learner
  failure between NEWLEADER and UPTODATE with leaked SyncThread activity
  (diff-sync events 91-101). `NewLeaderAckRejected` (CR-3) was not observed in
  natural runs; it was observed in the CR-3 reproduction leader log.
- **Update effect comparisons**: `NewLeaderAck` requires an empty learner buffer,
  reset sync mode and the epoch persisted (Trace.tla `ValidateEventPostState`);
  mutations M1-M4 are rejected (`spec/output/trace-validation/negative/`).
- **Archived traces**: `traces/archived-v0/*` superseded (old implementation;
  removed `BroadcastReady` anchor; no `event.peer`); `traces/run1-superseded/*`
  superseded (first fresh run with the post-write ACK probe).
- **Semantic spec files changed by validation**: no change to `base.tla`
  semantics; `Trace.tla` interpretation repairs only (changelog r1-r7). Later
  model-checking repairs (FIFO, SelectSync, FollowLeader, volatile votes) were
  re-validated by r8/r9.
