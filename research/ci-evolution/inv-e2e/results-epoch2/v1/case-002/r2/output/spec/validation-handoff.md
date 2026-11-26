# Validation handoff (incremental run incr-8c80add29fe2)

* Source under test: `artifact/` HEAD `2efbdfc3754df193bce05b9792297c813377cdaf` (neutral commit `update`);
  instrumented copy `work-source/` = HEAD + `harness/patches/instrumentation.patch` (6 files, +32 lines incl. `SpecularTrace`).
* Harness command: `timeout 2400s harness/run.sh` (rebased prior harness: same 4 JUnit scenarios + the update's
  `DIFFSyncConsistencyTest`); logs `spec/output/incr/harness/`, results `harness-results.ndjson`.
* Prior harness reuse: writer, event schema, build/test recipe and all prior probes reused; only changes are the
  Specula->Specular rename, the `BroadcastReady` probe moved with `zk.startup()`->`zk.startServing()` (the only
  rejected hunk), and three update-window probes (`SyncProposalBuffered`, `SyncProposalApplied`, `NewLeaderAckSent`).
  First run used `mvn -o` and failed to resolve the surefire provider (no trace); rerun online.

## Fresh new-version traces (all pass TLC trace validation, `TraceMatched` completed, 0 states left)

| Trace | Records | Distinct states | Log |
|---|---:|---:|---|
| traces/fresh/follower-diff.ndjson | 17 | 18 | spec/output/incr/trace-follower-diff.log |
| traces/fresh/follower-snap.ndjson | 18 | 19 | spec/output/incr/trace-follower-snap.log |
| traces/fresh/quorum-startup-mutation-shutdown.ndjson | 72 | 73 | spec/output/incr/trace-quorum-startup-mutation-shutdown.log |
| traces/fresh/leader-abandon-restart-recovery.ndjson | 271 | 272 | spec/output/incr/trace-leader-abandon-restart-recovery.log |
| traces/fresh/diff-sync-consistency.ndjson (update scenario) | 125 | 126 | spec/output/incr/trace-diff-sync-consistency.log |

Command (per trace): `cd spec && JSON=../traces/fresh/<t>.ndjson ./run-tlc.sh trace-<t> Trace.tla Trace.cfg 300 -workers 4`
(exact java command lines in `spec/output/incr/command-results.ndjson`). Inventory with sha256 and per-event
counts: `spec/output/incr/trace-inventory.json`.

## Update coverage
* AffectedActions: `LearnerNewLeader` (CurrentEpochPersisted in sync + SyncModeChanged NONE + ProposalQueued hand-off),
  `LearnerAckNewLeader` (`NewLeaderAckSent`, 14 occurrences), `EnterBroadcast` (`BroadcastReady` after
  `startServing`, 12 occurrences) observed in fresh traces.
* Producer (DIFF buffering, `SyncProposalBuffered`), consumer (leader BROADCAST `PhaseChanged` after the ACK quorum,
  diff-sync-consistency event 84), and fault boundary (learner failure after the ACK, events 85-86; SyncThread
  flush continuing afterwards, event 94) are observed in the update scenario.
* Compared update effect: `Trace.ValidateEventPostState` at `NewLeaderAckSent` requires `syncPending = <<>>`
  (every buffered PROPOSAL handed to `logRequest`) and `syncMode = NONE` under `NewLeaderLogsPending = TRUE`.
  Non-vacuity: a real old-revision trace with the same probes (`traces/controls/old-follower-diff.ndjson`) is
  rejected at event 9 (`spec/output/incr/control-oldtrace-newsemantics.log`) and accepted under
  `Trace-oldcontrol.cfg` (`control-oldtrace-oldsemantics.log`).
* ACK-vs-durability observation (US-2): in every fresh DIFF trace `NewLeaderAckSent` precedes the `TxnDurable` of the
  handed-off txn (follower-diff: ACK event 11, TxnDurable event 17; diff-sync-consistency: s0 ACK 82, leader
  BROADCAST 84, s0 TxnDurable 94). Evaluated with the actual `UpdateProps!NewLeaderAckDurable` operator on the
  replayed states: violated at state 83 of diff-sync-consistency (`spec/evidence/trace-props/`).
* Gaps (not observed in any fresh trace): `SyncProposalApplied` (SNAP/TRUNC with a COMMIT before NEWLEADER), TRUNC
  directive, follower crash *inside* the ACK window (only the test's exception-driven failure is exercised),
  late joiner to a broadcasting leader (not modeled). These are bounded coverage limits, not replay failures.

## Archived old-version traces
All 5 prior traces (`traces/*.ndjson`) replay against the current Trace spec (`spec/output/incr/archived-*.log`);
they predate the update probes, so they are retained as regression evidence and superseded for update coverage
by the fresh traces above.

## Semantic spec changes made during validation
Only `Trace.tla` field interpretations (tree-position zxid for role/phase/registration/sync-mode/BroadcastReady
events; elected-leader zxid for `ElectionWon`), recorded in `spec/changelog.md` Round U. No base/MC change was
needed by trace validation; a base frame-condition omission (`LearnerAckNewLeader` did not keep `syncPending`)
was found by the first TLC run and fixed before any campaign result was credited.
