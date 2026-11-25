# Validation handoff (Validation 4)

- Source: commit `update` 2efbdfc3754df193bce05b9792297c813377cdaf (artifact/), instrumented copy `work-source/`.
- Harness: `bash harness/run.sh` (rebased V0 patch; incompatibility: one hunk drifted, re-placed; see `spec/output/harness-rebase-apply.log`).
- Fresh traces (all replayed with `spec/Trace.tla`/`Trace.cfg`, `TraceMatched` completed, 0 queued states):
  `spec/output/trace/r4-*.log`, inventory/hashes in `spec/output/trace/coverage.json`, ledger `spec/output/trace/ledger.ndjson`.

| Trace | Records | Result | Model states (depth) |
|---|---:|---|---|
| diff-sync-uncommitted-log (update scenario) | 136 | pass | see r4 log |
| follower-diff (+repeat-1..3) | 17 each | pass | 18 |
| follower-snap | 18 | pass | 21 |
| quorum-startup-mutation-shutdown | 76 | pass | 77 |
| leader-abandon-restart-recovery | 286 | pass | see r4 log |

- Affected Actions observed in fresh traces (Action-replayed with post-state checks):
  CompleteSync (DIFF 15, SNAP 2), ClearSyncMode, LogSyncProposal, AckNewLeader (17),
  ReceiveUpToDate (15), EnterBroadcast; interaction Actions CountNewLeaderAck (14),
  LeaderBroadcast, PersistCurrentEpoch, SelectSync, ObserveCommit, AppendOne, FsyncOne,
  ApplyOne, Restart(+Crash before reload).
- Failure in the INITIAL window observed: 2 NewLeaderAckSent without UPTODATE in the update
  scenario; leaked SyncThread fsync after LOOKING; in-memory zxid lag (seq 97-102).
- Gaps: TRUNC branch not exercised by any scenario (unchanged code path; MC only);
  `NewLeaderAckMismatch` never fired (CR-1 race unobserved); election/discovery and
  leader-side broadcast pipeline remain observed projections (inherited V0 limitation:
  FLE voting, Propose, DeliverAck, Commit are not instrumented); real fail-stop crash not
  exercised by the harness (in-JVM restart only).
- Archived V0 traces: `traces/archived-V0/*` superseded (pre-update event set lacks the
  mandatory NEWLEADER-ACK/reload events required by the current Trace spec); first rebased
  run `traces/superseded-r1/*` superseded by the capture-point fixes (still informative:
  r1 diff-sync seq 98 election with stale in-memory zxid).
- Non-vacuity: update properties violated on real traces (`spec/output/trace/evidence*-*.log`);
  a hypothetical ACK-after-fsync model rejects the DIFF traces at NewLeaderAckSent and accepts
  SNAP (`spec/evidence/mut-ack-requires-durable/tlc-*.log`).
- Semantic spec files changed during validation: yes (recorded in `spec/changelog.md`).
