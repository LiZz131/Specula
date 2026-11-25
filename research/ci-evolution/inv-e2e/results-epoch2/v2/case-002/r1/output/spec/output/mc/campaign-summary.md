# Model-checking campaign summary (case-002, revision `update`)

All runs: `spec/run-tlc.sh` (outer `timeout`, `-Dtlc2.TLC.stopAfter`, states under
`/dev/shm/specula-e2e-case-002/`, removed after each run). Ledger: `spec/output/mc/ledger.ndjson`.
"BUDGET-LIMITED" = stopped by the 30-minute (or stated) budget with states still queued, or a
simulation run; reported as LIMITED_COVERAGE, never as proof. A TLC "completed" message after
`stopAfter` is classified by the queue size.

## Order executed (incremental checking chapter)

0. Small sanity (`MC-small.cfg`, exhaustive) and standard convergence round `MC.cfg`
   (pre-repair `mc-standard-r1`; final artifacts `mc-standard-final`).
1. Full update check over complete `MCNext`: `Update-full-2s.cfg` (MC-1 violation in full
   MCNext), `Update-full-followup-2s.cfg` (exhaustive, no further violation after the Case-B
   repair), `Update-full-followup.cfg` (3 servers, budget-limited), simulation follow-ups
   (`Update-full-followup-sim.cfg`, `Update-full-followup-e3-sim.cfg` with MaxEpoch 3).
2. Concrete focused check: `Update-focused-followup.cfg` (budget-limited).
3. Open and discharge: `Update-open-followup.cfg` (budget-limited) and `Update-discharge.cfg`
   (`UpdDischarge` over complete MCNext, budget-limited, no violation).
4. Scenario hunts: `Update-hunt-diff-ack.cfg` / `-followup.cfg` (MC-1), two-phase
   Init-rooted witness `evidence/witness-lost-commit/Phase1.cfg` + `Phase2.cfg` (MC-2) and
   `Phase2-crash.cfg` (MC-1 crash consequence), trace-prefix continuation
   `evidence/E3prefix-focus.cfg` (MC-2), `Update-hunt-lost-commit.cfg` BFS (stopped by the
   repair) and simulation `Update-hunt-lost-commit-sim.cfg` (no hit within budget);
   V0 hunts `MC-hunt-*.cfg` and update canaries `Update-canary-*.cfg` (reachability).
5. Final checks on the final artifacts: `mc-standard-final`, `mc-standard-sim-final`,
   `small-final`, all canaries `*-final`, hunts `upd-hunt-diff-ack*-r3`, witness phases
   re-derived (`evidence/witness-lost-commit/tlc-phase*-final.log`).

Notes:
- Uniform random simulation did not reach the ~50-step `UpdLeaderCompleteness` path; the
  Init-rooted witness was obtained by restricting which servers act in each phase (strict
  subsets of MCNext), and phase 2 starts exactly in phase 1's final state.
- Stopped/superseded runs are kept and marked in their logs (repair invalidation or
  replacement), not counted as coverage.

## Run table
| id | cfg | minutes | outcome | violation | stats | depth | log |
|---|---|---:|---|---|---|---|---|
| small-sanity-1 | MC-small.cfg | 10 | EXHAUSTED, no violation | - | 162281 states generated, 65480 distinct states found, 0 states left on queue. | 39 | spec/output/mc/small-sanity-1.log |
| upd-hunt-diff-ack-r1 | Update-hunt-diff-ack.cfg | 30 | VIOLATION | Action property UpdNewLeaderAckAfterDurable is violated | 36331 states generated, 13192 distinct states found, 1416 states left on queue. | 32 | spec/output/mc/upd-hunt-diff-ack-r1.log |
| upd-hunt-diff-ack-r2 | Update-hunt-diff-ack-followup.cfg | 30 | VIOLATION | Invariant UpdEstablishedHistoryDurableOnQuorum is violated | 50380 states generated, 19346 distinct states found, 1834 states left on queue. | 35 | spec/output/mc/upd-hunt-diff-ack-r2.log |
| mc-hunt-election | MC-hunt-election.cfg | 15 | VIOLATION | Invariant NotElectionReached is violated | 69 states generated, 24 distinct states found, 11 states left on queue. | 4 | spec/output/mc/mc-hunt-election.log |
| mc-hunt-mutation | MC-hunt-mutation.cfg | 15 | VIOLATION | Invariant NotMutationReached is violated | 6950 states generated, 3599 distinct states found, 230 states left on queue. | 27 | spec/output/mc/mc-hunt-mutation.log |
| mc-hunt-recovery | MC-hunt-recovery.cfg | 15 | VIOLATION | Invariant NotRecoveryReached is violated | 91 states generated, 48 distinct states found, 33 states left on queue. | 4 | spec/output/mc/mc-hunt-recovery.log |
| mc-hunt-sync | MC-hunt-sync.cfg | 15 | VIOLATION | Invariant NotSyncReached is violated | 303 states generated, 98 distinct states found, 25 states left on queue. | 8 | spec/output/mc/mc-hunt-sync.log |
| upd-canary-DiffPayload | Update-canary-DiffPayload.cfg | 15 | BUDGET-LIMITED (LIMITED_COVERAGE) | - | - | - | spec/output/mc/upd-canary-DiffPayload.log |
| upd-canary-DiffPayload | Update-canary-DiffPayload.cfg | 10 | VIOLATION | Invariant UpdNotDiffPayload is violated | 22846 states generated, 8043 distinct states found, 1042 states left on queue. | 26 | spec/output/mc/upd-canary-DiffPayload.log |
| upd-canary-SyncLog | Update-canary-SyncLog.cfg | 10 | VIOLATION | Invariant UpdNotSyncLog is violated | 8406 states generated, 2884 distinct states found, 533 states left on queue. | 20 | spec/output/mc/upd-canary-SyncLog.log |
| upd-canary-NlAck | Update-canary-NlAck.cfg | 10 | VIOLATION | Invariant UpdNotNlAck is violated | 1418 states generated, 492 distinct states found, 162 states left on queue. | 12 | spec/output/mc/upd-canary-NlAck.log |
| upd-canary-NlAckBeforeDurable | Update-canary-NlAckBeforeDurable.cfg | 10 | VIOLATION | Invariant UpdNotNlAckBeforeDurable is violated | 37055 states generated, 13530 distinct states found, 1693 states left on queue. | 30 | spec/output/mc/upd-canary-NlAckBeforeDurable.log |
| upd-canary-UpToDate | Update-canary-UpToDate.cfg | 10 | VIOLATION | Invariant UpdNotUpToDate is violated | 5111 states generated, 1609 distinct states found, 254 states left on queue. | 17 | spec/output/mc/upd-canary-UpToDate.log |
| upd-canary-EstablishedWithHistory | Update-canary-EstablishedWithHistory.cfg | 10 | VIOLATION | Invariant UpdNotEstablishedWithHistory is violated | 22687 states generated, 7934 distinct states found, 1010 states left on queue. | 27 | spec/output/mc/upd-canary-EstablishedWithHistory.log |
| mc-standard-r1 | MC.cfg | 30 | BUDGET-LIMITED, no violation (LIMITED_COVERAGE) | - | 291949652 states generated, 56514298 distinct states found, 6141983 states left on queue. | 30 | spec/output/mc/mc-standard-r1.log |
| upd-open-followup-r1 | Update-open-followup.cfg | 30 | stopped (replaced) | - | 123 states generated, 50 distinct states found, 42 states left on queue. | 5 | spec/output/mc/upd-open-followup-r1.failed-nonconstructive-envupdate.log |
| upd-full-2s-r1 | Update-full-2s.cfg | 30 | VIOLATION | Action property UpdNewLeaderAckAfterDurable is violated | 253319 states generated, 86700 distinct states found, 12791 states left on queue. | 31 | spec/output/mc/upd-full-2s-r1.log |
| upd-full-followup-2s-r1 | Update-full-followup-2s.cfg | 30 | VIOLATION | Invariant PipelinePrefix is violated | 762515 states generated, 249996 distinct states found, 29838 states left on queue. | 37 | spec/output/mc/upd-full-followup-2s-r1.log |
| upd-discharge-r1 | Update-discharge.cfg | 30 | stopped (replaced) | - | - | - | spec/output/mc/upd-discharge-r1.superseded-envupdate-rewrite.log |
| upd-discharge-r2 | Update-discharge.cfg | 30 | stopped (replaced) | - | - | - | spec/output/mc/upd-discharge-r2.log |
| upd-open-followup-r2 | Update-open-followup.cfg | 30 | stopped (replaced) | - | - | - | spec/output/mc/upd-open-followup-r2.log |
| upd-focused-followup-r1 | Update-focused-followup.cfg | 30 | stopped (replaced) | - | - | - | spec/output/mc/upd-focused-followup-r1.log |
| upd-full-followup-r1 | Update-full-followup.cfg | 30 | stopped (replaced) | - | - | - | spec/output/mc/upd-full-followup-r1.log |
| upd-hunt-lost-commit-bfs-r1 | Update-hunt-lost-commit.cfg | 30 | stopped (replaced) | - | - | - | spec/output/mc/upd-hunt-lost-commit-bfs-r1.log |
| upd-full-followup-2s-r2 | Update-full-followup-2s.cfg | 30 | EXHAUSTED, no violation | - | 1982402 states generated, 607117 distinct states found, 0 states left on queue. | 54 | spec/output/mc/upd-full-followup-2s-r2.log |
| upd-hunt-diff-ack-r3 | Update-hunt-diff-ack.cfg | 15 | VIOLATION | Action property UpdNewLeaderAckAfterDurable is violated | 35926 states generated, 13044 distinct states found, 1596 states left on queue. | 30 | spec/output/mc/upd-hunt-diff-ack-r3.log |
| upd-hunt-diff-ack-followup-r3 | Update-hunt-diff-ack-followup.cfg | 15 | VIOLATION | Invariant UpdEstablishedHistoryDurableOnQuorum is violated | 58264 states generated, 21441 distinct states found, 2245 states left on queue. | 34 | spec/output/mc/upd-hunt-diff-ack-followup-r3.log |
| upd-discharge-r3 | Update-discharge.cfg | 30 | BUDGET-LIMITED, no violation (LIMITED_COVERAGE) | - | 59737010 states generated, 13830742 distinct states found, 3286241 states left on queue. | 25 | spec/output/mc/upd-discharge-r3.log |
| upd-full-followup-r2 | Update-full-followup.cfg | 30 | BUDGET-LIMITED, no violation (LIMITED_COVERAGE) | - | 76295048 states generated, 17654974 distinct states found, 4030082 states left on queue. | 27 | spec/output/mc/upd-full-followup-r2.log |
| upd-focused-followup-r2 | Update-focused-followup.cfg | 30 | BUDGET-LIMITED, no violation (LIMITED_COVERAGE) | - | 74727830 states generated, 17494415 distinct states found, 3689495 states left on queue. | 28 | spec/output/mc/upd-focused-followup-r2.log |
| upd-open-followup-r3 | Update-open-followup.cfg | 30 | BUDGET-LIMITED, no violation (LIMITED_COVERAGE) | - | 134079249 states generated, 17421253 distinct states found, 6462583 states left on queue. | 19 | spec/output/mc/upd-open-followup-r3.log |
| mc-hunt-election-final | MC-hunt-election.cfg | 10 | VIOLATION | Invariant NotElectionReached is violated | 56 states generated, 22 distinct states found, 12 states left on queue. | 4 | spec/output/mc/mc-hunt-election-final.log |
| mc-hunt-mutation-final | MC-hunt-mutation.cfg | 10 | VIOLATION | Invariant NotMutationReached is violated | 7113 states generated, 3670 distinct states found, 190 states left on queue. | 27 | spec/output/mc/mc-hunt-mutation-final.log |
| mc-hunt-recovery-final | MC-hunt-recovery.cfg | 10 | VIOLATION | Invariant NotRecoveryReached is violated | 60 states generated, 35 distinct states found, 26 states left on queue. | 3 | spec/output/mc/mc-hunt-recovery-final.log |
| mc-hunt-sync-final | MC-hunt-sync.cfg | 10 | VIOLATION | Invariant NotSyncReached is violated | 295 states generated, 91 distinct states found, 23 states left on queue. | 8 | spec/output/mc/mc-hunt-sync-final.log |
| upd-canary-DiffPayload-final | Update-canary-DiffPayload.cfg | 10 | VIOLATION | Invariant UpdNotDiffPayload is violated | 22243 states generated, 7810 distinct states found, 991 states left on queue. | 26 | spec/output/mc/upd-canary-DiffPayload-final.log |
| upd-canary-SyncLog-final | Update-canary-SyncLog.cfg | 10 | VIOLATION | Invariant UpdNotSyncLog is violated | 8122 states generated, 2785 distinct states found, 512 states left on queue. | 20 | spec/output/mc/upd-canary-SyncLog-final.log |
| upd-canary-NlAck-final | Update-canary-NlAck.cfg | 10 | VIOLATION | Invariant UpdNotNlAck is violated | 1382 states generated, 481 distinct states found, 159 states left on queue. | 12 | spec/output/mc/upd-canary-NlAck-final.log |
| upd-canary-NlAckBeforeDurable-final | Update-canary-NlAckBeforeDurable.cfg | 10 | VIOLATION | Invariant UpdNotNlAckBeforeDurable is violated | 35901 states generated, 13037 distinct states found, 1614 states left on queue. | 30 | spec/output/mc/upd-canary-NlAckBeforeDurable-final.log |
| upd-canary-UpToDate-final | Update-canary-UpToDate.cfg | 10 | VIOLATION | Invariant UpdNotUpToDate is violated | 5018 states generated, 1581 distinct states found, 253 states left on queue. | 17 | spec/output/mc/upd-canary-UpToDate-final.log |
| upd-canary-EstablishedWithHistory-final | Update-canary-EstablishedWithHistory.cfg | 10 | VIOLATION | Invariant UpdNotEstablishedWithHistory is violated | 22318 states generated, 7832 distinct states found, 996 states left on queue. | 26 | spec/output/mc/upd-canary-EstablishedWithHistory-final.log |
| small-final | MC-small.cfg | 15 | EXHAUSTED, no violation | - | 162281 states generated, 65480 distinct states found, 0 states left on queue. | 39 | spec/output/mc/small-final.log |
| upd-hunt-lost-commit-sim-r1 | Update-hunt-lost-commit-sim.cfg | 30 | BUDGET-LIMITED (LIMITED_COVERAGE) | - | - | - | spec/output/mc/upd-hunt-lost-commit-sim-r1.log |
| mc-standard-sim-final | MC-sim.cfg | 30 | BUDGET-LIMITED (LIMITED_COVERAGE) | - | - | - | spec/output/mc/mc-standard-sim-final.log |
| upd-full-followup-sim-r1 | Update-full-followup-sim.cfg | 30 | BUDGET-LIMITED (LIMITED_COVERAGE) | - | - | - | spec/output/mc/upd-full-followup-sim-r1.log |
| upd-full-followup-e3-sim-r1 | Update-full-followup-e3-sim.cfg | 30 | BUDGET-LIMITED (LIMITED_COVERAGE) | - | - | - | spec/output/mc/upd-full-followup-e3-sim-r1.log |
| mc-standard-final | MC.cfg | 30 | BUDGET-LIMITED, no violation (LIMITED_COVERAGE) | - | 146077169 states generated, 33727671 distinct states found, 7542420 states left on queue. | 30 | spec/output/mc/mc-standard-final.log |

Simulation runs report traces instead of BFS statistics:

- upd-hunt-lost-commit-sim-r1: Progress: 74948259 states checked, 90279 traces generated (trace length: mean=54, var(x)=663, sd=26)
- mc-standard-sim-final: Progress: 64887926 states checked, 812831 traces generated (trace length: mean=54, var(x)=618, sd=25)
- upd-full-followup-sim-r1: Progress: 69350629 states checked, 98497 traces generated (trace length: mean=54, var(x)=635, sd=25)
- upd-full-followup-e3-sim-r1: Progress: 51520865 states checked, 53357 traces generated (trace length: mean=75, var(x)=592, sd=24)

Additional evidence-directory TLC runs (not in the ledger):

- evidence/witness-lost-commit/tlc-phase1-final.log: Init -> S, UpdEstablishedHistoryDurableOnQuorum violated (34 states)
- evidence/witness-lost-commit/tlc-phase2-final.log: S -> UpdLeaderCompleteness violated (16 states)
- evidence/witness-lost-commit/tlc-phase2-crash-final.log: S -> crash -> UpdLeaderCompleteness violated (17 states)
- evidence/tlc-E3prefix-focus.log: validated trace state (cursor 103) -> UpdLeaderCompleteness violated (16 states)
- evidence/tlc-E3prefix-fullMCNext-bfs-stopped.log: full MCNext BFS from the trace state, stopped at level 9 (no violation, open frontier)
