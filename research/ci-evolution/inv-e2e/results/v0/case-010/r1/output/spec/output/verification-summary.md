# Verification summary — incremental case-010 (source `update` b16ba7105238d46b0d51e3cc5d92ce9fe16de834)

## Disposition

- Source delta: **MODEL_CHANGE_REQUIRED** (final decision label `MODEL_UPDATED`). `Learner.shutdown` now requests a full shutdown when `syncMode == SNAP`; a full shutdown of a non-running server clears the ZKDatabase, so the next `getLastLoggedZxid` reloads disk instead of reporting a SNAP image that was never persisted.
- Validation: **PASSED** on the final artifacts — four fresh traces from the rebased harness (two V0 regression scenarios, the update's own test, one update-derived forced-SNAP completion scenario) replay completely with `TraceMatched` and real-object post-state checks (`spec/output/final4-gate-trace-*-v3b.log`). Field consumption shown by an old-semantics model and four field mutants, each rejected at the expected event (`spec/output/final4-nonvacuity-*.log`).
- Model checking: **LIMITED_COVERAGE** everywhere (time-bounded, non-empty queues). One finding, **MC-1** (`spec/bug-report.md`): a TRUNC-mode learner exit keeps a non-durable in-memory commit, because the update's full-shutdown condition covers SNAP only; the consequence is a committed hole on the learner's disk after an empty-DIFF resync.
- Differential evidence for the changed branch: under the steered U1 schedule the exact-old exit violates `ReportedHistoryDurable` at depth 39 and `DurableHistoryConsistent` at depth 55, while the updated exit restricted to SNAP/DIFF syncs shows no violation through depth 58 (8.4M distinct states, bounded).

## Commands

- Harness: `SPECULA_TRACE_RUN_ID=v3b bash harness/run.sh` (Maven `-B -pl zookeeper-server`, each test `timeout 15m`).
- Trace validation: `scripts/validate_trace.sh <trace> <log>` -> `JSON=<trace> timeout 20m java ... tlc2.TLC -metadir /dev/shm/specula-e2e-case-010/<fresh> -config Trace.cfg -workers 1 Trace`.
- TLC campaigns: `scripts/tlc.sh <Spec> <cfg> <log> <outer-timeout> [TLC args]` (`timeout`, `-metadir /dev/shm/specula-e2e-case-010/<name>.XXXX`, state dir removed after the run, log in `spec/output/`). Batches: `scripts/run_F2.sh`, `scripts/run_F3.sh`; F1 command line is recorded in each `final-*.log` header.
- Bounds (standard): 3 peers, MaxEpoch 2, MaxTxn 2, 1 extra election round, 1 crash, 1 injected learner exit, 1 periodic snapshot; per-config overrides are in each cfg.

## Model repairs found by the loop (all Case A/B, recorded in `spec/changelog.md`)

Trace validation: leader epoch-agreement concurrency, election-phase split, per-process reset at restart, racing duplicate `Learner.shutdown` calls (trace mapping only). Model checking: `ApplyTxn` only on serving servers; TRUNC keeps snapshot-covered records (`snapZ`) — the first SNAP-steered counterexample depended on the faulty truncation and was discarded; no ACKs from the shutdown drain; steering vote constraint (earlier crash-based U2/U3 "completed" runs were vacuous and were re-run).

## Reachability / non-vacuity

Canaries (expected violations are witnesses): SNAP-window exit (depth 13), reload after clear (14), in-memory COMMIT inside a SNAP window (39 under SnapOnlySteer), DIFF exit after NEWLEADER with log ahead of the data tree (unsteered and U3-steered), election, sync completion, snapshot publication, restart. The MC-1 witness itself reaches a TRUNC exit with a memory-only commit. Commit/apply hunts and the crash-based TRUNC canary are covered by the F3 simulation follow-up (table below).

## Gaps and limits

- No campaign exhausted its state space; BFS reached depth 28-35 on unsteered configs, 43-58 on steered ones.
- The crash-based U2 path (old leader's uncommitted record) and the U3 consequence (uncommitted record below a committed one after a DIFF-window exit) were not reached within bounds; U3 remains an open question, not a finding.
- `Update-open.cfg` explores the EnvUpdate havoc slowly (depth 12); discharge (`DischargeContext`) found no violation up to depth 29.
- MC-1 has no real-system reproduction in this task.

## Campaign outcomes (final model)

Superseded/aborted entries are kept for provenance: runs on earlier model revisions carry `-premodelfix`, `-pretruncfix`, `-predrainfix` suffixes (not listed); `final3-*` runs marked exit 143 were stopped after the FIFO-cut repair and re-run as `final4-*`; `final-base-bfs` and `final-update-canary-truncabort-bfs` (exit 1) were aborted by an operator cleanup and re-run as `final5-*`. `final-*` runs that predate the FIFO-cut repair remain valid as no-violation results because that repair only removes transitions; every violation and differential result is re-established in `final4-*`.

| Log | Config | Mode | Result | Distinct states | Depth/level | Queue left | Cex length |
|---|---|---|---|---:|---:|---:|---:|
| `final-base-bfs.log` | `base.cfg` | BFS | exit 1 | 3,482,695 | 20 | 1,194,783 |  |
| `final-mc-apply-hunt-bfs.log` | `MC-apply-hunt.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 1,582,935 | 29 | 328,279 |  |
| `final-mc-commit-hunt-bfs.log` | `MC-commit-hunt.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 1,554,009 | 29 | 323,399 |  |
| `final-mc-election-hunt-bfs.log` | `MC-election-hunt.cfg` | BFS | violation: NeverElection | 28 | 4 | 17 | 4 |
| `final-mc-full-bfs.log` | `MC-full.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 11,368,722 | 28 | 3,235,830 |  |
| `final-mc-recovery-hunt-bfs.log` | `MC-recovery-hunt.cfg` | BFS | violation: NeverRestart | 28 | 4 | 18 | 4 |
| `final-mc-snapshot-hunt-bfs.log` | `MC-snapshot-hunt.cfg` | BFS | violation: NeverSnapshot | 174753 | 21 | 51588 | 21 |
| `final-mc-standard-bfs.log` | `MC.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 15,038,660 | 35 | 3,870,317 |  |
| `final-mc-sync-hunt-bfs.log` | `MC-sync-hunt.cfg` | BFS | violation: NeverCompleteSync | 176340 | 21 | 52039 | 21 |
| `final-mc-wide-bfs.log` | `MC-wide.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 10,342,158 | 33 | 2,416,853 |  |
| `final-update-canary-diffabort-bfs.log` | `Update-canary-diffabort.cfg` | BFS | violation: NeverDiffAbortAfterNewLeader | 2810807 | 33 | 517322 | 33 |
| `final-update-canary-diffwindow-steered2-bfs.log` | `Update-canary-diffwindow-steered2.cfg` | BFS | violation: NeverDiffAbortAfterNewLeader | 1255685 | 35 | 216266 | 34 |
| `final-update-canary-reload-bfs.log` | `Update-canary-reload.cfg` | BFS | violation: CanaryNoReloadAfterClear | 8611 | 14 | 2958 | 14 |
| `final-update-canary-snapabort-bfs.log` | `Update-canary-snapabort.cfg` | BFS | violation: CanaryNoSnapAbort | 5223 | 13 | 1895 | 13 |
| `final-update-canary-snapcommit-bfs.log` | `Update-canary-snapcommit.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 2,993,378 | 33 | 681,449 |  |
| `final-update-canary-snaponly-steered-reload-bfs.log` | `Update-canary-snaponly-steered-reload.cfg` | BFS | violation: NeverReloadAfterClear | 1016 | 15 | 242 | 15 |
| `final-update-canary-snaponly-steered-snapcommit-bfs.log` | `Update-canary-snaponly-steered-snapcommit.cfg` | BFS | violation: NeverInMemorySyncCommitSnap | 72810 | 39 | 13291 | 39 |
| `final-update-canary-trunc-steered2-bfs.log` | `Update-canary-trunc-steered2.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 1,528,274 | 36 | 334,876 |  |
| `final-update-canary-truncabort-bfs.log` | `Update-canary-truncabort.cfg` | BFS | exit 1 | 7,820 | 11 | 3,571 |  |
| `final-update-discharge-bfs.log` | `Update-discharge.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 5,538,540 | 29 | 1,355,364 |  |
| `final-update-focused-bfs.log` | `Update-focused.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 8,644,209 | 32 | 1,983,088 |  |
| `final-update-full-bfs.log` | `Update-full.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 14,630,448 | 34 | 3,728,907 |  |
| `final-update-full-sim.log` | `Update-full.cfg` | simulation | time bound, no violation (LIMITED_COVERAGE) | 29832283 checked / 605262 traces |  |  |  |
| `final-update-hunt-diffwindow-steered2-bfs.log` | `Update-hunt-diffwindow-steered2.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 5,923,989 | 47 | 863,010 |  |
| `final-update-hunt-snap-only-steered-bfs.log` | `Update-hunt-snap-only-steered.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 8,421,171 | 58 | 1,678,647 |  |
| `final-update-hunt-snap-only-steered-consequence-bfs.log` | `Update-hunt-snap-only-steered-consequence.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 6,615,392 | 51 | 2,000,554 |  |
| `final-update-hunt-snap-steered-oldcontrol-bfs.log` | `Update-hunt-snap-steered-oldcontrol.cfg` | BFS | violation: ReportedHistoryDurable | 53775 | 39 | 10708 | 39 |
| `final-update-hunt-snap-steered-oldcontrol-consequence-bfs.log` | `Update-hunt-snap-steered-oldcontrol-consequence.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 1,684,417 | 51 | 428,122 |  |
| `final-update-hunt-trunc-steered2-bfs.log` | `Update-hunt-trunc-steered2.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 4,539,193 | 43 | 817,910 |  |
| `final-update-open-bfs.log` | `Update-open.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 153,460 | 12 | 72,060 |  |
| `final2-update-discharge-bfs.log` | `Update-discharge.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 4,517,113 | 29 | 1,125,947 |  |
| `final3-mc-apply-hunt-sim.log` | `MC-apply-hunt.cfg` | simulation | violation: NeverApply | 707 checked / 27 traces |  |  | 55 |
| `final3-mc-commit-hunt-sim.log` | `MC-commit-hunt.cfg` | simulation | violation: NeverCommit | 716 checked / 26 traces |  |  | 54 |
| `final3-mc-recovery-hunt-sim.log` | `MC-recovery-hunt.cfg` | simulation | violation: NeverRestart | 56 checked / 8 traces |  |  | 3 |
| `final3-mc-snapshot-hunt-sim.log` | `MC-snapshot-hunt.cfg` | simulation | violation: NeverSnapshot | 683 checked / 41 traces |  |  | 49 |
| `final3-update-canary-trunc-steered2-sim.log` | `Update-canary-trunc-steered2.cfg` | simulation | violation: NeverTruncAbortMemoryOnly | 10669413 checked / 86566 traces |  |  | 104 |
| `final3-update-hunt-diffwindow-steered2-sim.log` | `Update-hunt-diffwindow-steered2.cfg` | simulation | exit 143 | 8622788 checked / 108792 traces |  |  |  |
| `final3-update-hunt-snap-steered-oldcontrol-consequence-bfs.log` | `Update-hunt-snap-steered-oldcontrol-consequence.cfg` | BFS | exit 143 | 4,133,718 | 55 | 938,018 |  |
| `final3-update-hunt-trunc-steered2-sim.log` | `Update-hunt-trunc-steered2.cfg` | simulation | violation: LeaderCompleteness | 870488 checked / 7138 traces |  |  | 80 |
| `final4-mc-standard-bfs.log` | `MC.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 8,386,971 | 31 | 2,010,037 |  |
| `final4-update-continue-mc1-consequence-bfs.log` | `Update-continue-mc1-consequence.cfg` | BFS | violation: DurableHistoryConsistent | 35031 | 19 | 9649 | 19 |
| `final4-update-hunt-diffwindow-steered2-sim.log` | `Update-hunt-diffwindow-steered2.cfg` | simulation | time bound, no violation (LIMITED_COVERAGE) | 18049777 checked / 227129 traces |  |  |  |
| `final4-update-hunt-mc1-deterministic-bfs.log` | `Update-hunt-mc1-deterministic.cfg` | BFS | violation: ReportedHistoryDurable | 3609392 | 56 | 757706 | 55 |
| `final4-update-hunt-mc2-leadercompleteness-sim.log` | `Update-hunt-mc2-leadercompleteness.cfg` | simulation | time bound, no violation (LIMITED_COVERAGE) | 29762462 checked / 241311 traces |  |  |  |
| `final4-update-hunt-snap-only-steered-bfs.log` | `Update-hunt-snap-only-steered.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 7,723,787 | 58 | 1,447,794 |  |
| `final4-update-hunt-snap-steered-oldcontrol-bfs.log` | `Update-hunt-snap-steered-oldcontrol.cfg` | BFS | violation: ReportedHistoryDurable | 52284 | 39 | 10174 | 39 |
| `final4-update-hunt-snap-steered-oldcontrol-consequence-bfs.log` | `Update-hunt-snap-steered-oldcontrol-consequence.cfg` | BFS | violation: DurableHistoryConsistent | 6068424 | 57 | 1223364 | 57 |
| `final4-update-hunt-trunc-steered2-sim.log` | `Update-hunt-trunc-steered2.cfg` | simulation | violation: DurableHistoryConsistent | 8452598 checked / 68610 traces |  |  | 89 |
| `final5-base-bfs.log` | `base.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 16,986,614 | 24 | 5,293,093 |  |
| `final5-update-canary-truncabort-bfs.log` | `Update-canary-truncabort.cfg` | BFS | time bound, no violation (LIMITED_COVERAGE) | 8,531,527 | 28 | 2,302,148 |  |
| `final5-update-canary-truncabort-sim.log` | `Update-canary-truncabort.cfg` | simulation | time bound, no violation (LIMITED_COVERAGE) | 29037711 checked / 507760 traces |  |  |  |

Trace validation logs (final artifacts): `final5-gate-trace-*-v3b.log` (PASS x4), non-vacuity `final4-nonvacuity-*` (all rejected at the expected line).
