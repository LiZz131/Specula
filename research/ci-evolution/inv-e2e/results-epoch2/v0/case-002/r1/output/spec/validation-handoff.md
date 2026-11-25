# Validation handoff (incremental)

- Source under test: artifact HEAD `2efbdfc3754df193bce05b9792297c813377cdaf` (`update`);
  baseline `1414ebfb1d16fd81abc38550a96950d919ecf805`.
- Harness command: `timeout 3600s bash harness/run.sh` (from `.specula-output/`), rebased
  patch `harness/patches/instrumentation.patch` (applies with `git apply --check` to a fresh
  archive), build/test ledger `spec/output/harness-command-results.ndjson`,
  run log `spec/output/harness-run-005.log`.
- Trace validation command: `spec/run-trace.sh <trace> <tag>` (real TLC, `TraceMatched` +
  post-state checks; states under `/dev/shm/specula-e2e-case-002`, removed after each run).

## Fresh new-version traces (retained suite)
| Trace | Records | sha256 | DIFF proposals logged at NEWLEADER before ACK | shutdown skipped in INITIAL |
|---|---:|---|---:|---:|
| `traces/diff-sync-uptodate-failure.ndjson` | 185 | `eb30d35ee5523e6a…` | 2 | 2 |
| `traces/follower-diff.ndjson` | 27 | `e80b41e0375ac5b2…` | 1 | 0 |
| `traces/follower-snap.ndjson` | 27 | `648635000a8ce4e8…` | 0 | 0 |
| `traces/leader-abandon-restart-recovery.ndjson` | 349 | `d0f1e532a855ca05…` | 0 | 0 |
| `traces/quorum-startup-mutation-shutdown.ndjson` | 89 | `cd3e38e8f51deed9…` | 0 | 0 |
| `traces/repro-stale-tree-reelection-1.ndjson` (supplementary, MC-2 reproduction) | 235 | see provenance | n/a | yes |

Final regression (final artifacts, `spec/output/trace-final2-summary.txt`): 6/6 PASS, each
with states = records + 1 and no error (`TraceMatched` satisfied).  Non-vacuity: 3 mutants
rejected (`spec/output/trace-nonvacuity-summary.txt`).

## Update coverage (affected / interaction actions observed in fresh traces)
| Action | Event(s) | Traces |
|---|---|---|
| LearnerNewLeaderStartup | `SyncModeChanged(NONE)` + `ZkServerState(INITIAL)` | all 5 |
| LearnerLogPendingOne | `ProposalQueued` between INITIAL and `NewLeaderAckSent` | follower-diff, diff-sync, repro |
| LearnerSendNewLeaderAck | `NewLeaderAckSent` (aux.pending must be 0) | all 5 |
| LearnerUptodateStartServing | `UptodateReceived`, `ZkServerState(RUNNING)`, `BroadcastReady` | all 5 |
| LearnerUptodateLogOne | `ProposalQueued` after `BroadcastReady` | follower-snap |
| LearnerUptodateCommitOne / LearnerEnterBroadcast | `CommitDelivered`, `PhaseChanged(broadcast)` | all 5 |
| ServerShutdown (INITIAL, skipped) | `ZkShutdownSkipped` aux.zkState=INITIAL | diff-sync, repro |
| ServerShutdown (RUNNING) | `ZkShutdownStarted`, `ZkTreeFastForwarded`, `ZkSyncDrained` | all 5 |
| LeaderStartZkServer / NEWLEADER ack counting | `NewLeaderAckCounted`, `NewLeaderQuorum`, leader `ZkServerState(RUNNING)` | quorum, leader-abandon, diff-sync, repro |
| Restart | `DatabaseLoaded` | quorum, leader-abandon, diff-sync, repro |

Gaps (not observed in any fresh trace): `NewLeaderAckRejected` (CR-1 race),
`SyncCommitApplied` (late joiner in SNAP/TRUNC receiving commits before NEWLEADER), TRUNC sync
mode.  Leader `propose`/`tryToCommit` are not instrumented (implied, gated observation steps).

## Archived traces
`traces/archived-v0/*`: superseded (old schema; old-version NEWLEADER behaviour).
`traces/superseded-attempt(2, 3, 4)/*`: earlier harness revisions (probe fixes).

## Semantic spec changes made during validation
Yes: `OneActiveLeaderPerEpoch` refinement (Case A), `ServerShutdown` fast-forward start point
(Case B, from the reproduction trace), vote lifetime (Case B, from model checking).  All six
retained traces were re-validated on the final artifacts.
