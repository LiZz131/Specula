# Validation handoff — case-010

- Source: artifact `b16ba7105238d46b0d51e3cc5d92ce9fe16de834` ("update"); old control worktree `work-old` at `f8533cdd2177479d5792649efc05e78abc8cb802` ("baseline").
- Harness command: `harness/run-all.sh` (= `harness/run.sh` + `harness/run-old-control.sh` + `harness/repro/run-repro.sh new|old SpeculaTruncAbortReproTest trunc-abort`); every Maven/JUnit run under `timeout 15m`. Logs: `spec/output/harness/`, `spec/output/repro/`.
- Prior harness: V0 patch reused unchanged (applies cleanly); incremental probes added by `harness/apply_update_probes.py`. Incompatibility recorded: the V0 schema-2 ("stateful") shadow-history probe was not preserved (`harness/src` empty), so fresh traces are schema-1 + incremental fields; the schema-2-only Trace checks are inactive.
- Semantic spec files changed during validation: yes (see `spec/changelog.md` Round 1/2): ReceiveSyncMode leader-phase guard removed; LeaderDecideSync/syncPlan; syncComplete timing; ObserveSetPeerState(LOOKING) atomic phase reset; LeaderSyncDecision committedTx relation.

## Fresh trace inventory (round 2; round-1 traces kept in `traces/superseded-r1/`, V0 traces in `traces/archived-v0/`)

| Trace | events | ApplyTxn | BeginSnapshot | ChooseSyncMode | CommitProposal | CompleteLearnerSync | FinishElection | FinishSnapshot | FlushTxnLog | FollowerCommit | FollowerPendingProposal | FormNewLeaderQuorum | GracefulShutdown | LeaderPropose | LeaderSyncDecision | LearnerShutdown | PersistAcceptedEpoch | PersistCurrentEpoch | QueueForSync | ReceiveSyncMode | RecordProposalAck | ReloadDatabase | RestartLoadDatabase | SetPeerState | SetZabState | SyncApplyCommitted |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| diff-sync-after-snap-new.ndjson | 282 | 33 | 1 | 9 | 11 | 4 | 6 | 1 | 33 | 22 | 22 | 1 | 5 | 11 | 5 | 9 | 3 | 5 | 33 | 5 | 22 | 1 | 5 | 12 | 23 | 0 |
| diff-sync-after-snap-oldcontrol.ndjson | 231 | 23 | 1 | 9 | 11 | 4 | 6 | 1 | 23 | 12 | 12 | 1 | 5 | 11 | 5 | 9 | 3 | 5 | 23 | 5 | 22 | 0 | 5 | 12 | 23 | 0 |
| election-ordered-new.ndjson | 84 | 6 | 1 | 4 | 2 | 2 | 3 | 1 | 6 | 4 | 4 | 1 | 3 | 2 | 2 | 4 | 3 | 3 | 6 | 2 | 4 | 0 | 3 | 6 | 12 | 0 |
| repro-trunc-abort-new.ndjson | 124 | 5 | 1 | 9 | 2 | 4 | 6 | 1 | 6 | 3 | 4 | 1 | 4 | 2 | 5 | 8 | 3 | 5 | 6 | 5 | 4 | 0 | 4 | 12 | 23 | 1 |
| repro-trunc-abort-old.ndjson | 124 | 5 | 1 | 9 | 2 | 4 | 6 | 1 | 6 | 3 | 4 | 1 | 4 | 2 | 5 | 8 | 3 | 5 | 6 | 5 | 4 | 0 | 4 | 12 | 23 | 1 |
| restart-catchup-new.ndjson | 151 | 6 | 2 | 10 | 2 | 5 | 7 | 2 | 6 | 4 | 4 | 2 | 7 | 2 | 5 | 10 | 6 | 7 | 6 | 5 | 4 | 0 | 7 | 14 | 28 | 0 |
| snap-complete-new.ndjson | 98 | 5 | 2 | 6 | 2 | 3 | 4 | 2 | 5 | 3 | 3 | 1 | 4 | 2 | 3 | 6 | 3 | 4 | 5 | 3 | 4 | 0 | 4 | 8 | 16 | 0 |

## Results (TLC trace validation, `TraceMatched` + invariants; logs in `spec/output/`)

| Trace | Model | Result |
|---|---|---|
| election-ordered-new (prior scenario) | TraceUpdate, new | PASS 85/85 states, all base + update invariants |
| restart-catchup-new (prior scenario) | TraceUpdate, new | PASS 152/152 |
| diff-sync-after-snap-new (update scenario from the diff) | TraceUpdate, new | PASS 283/283 (SNAP abort: fully=true, dbInitialized=false, ReloadDatabase) |
| snap-complete-new (update-focused) | TraceUpdate, new | PASS 99/99 (NEWLEADER sync snapshot persisted) |
| repro-trunc-abort-new (MC-1 code observation) | Trace no-inv, new | conforms 125/125; with update invariants: UpdIdleDbBackedByDisk violated at state 65 (TRUNC abort), OrderedHistories at state 95 (log gap) |
| diff-sync-after-snap-oldcontrol (old code) | Trace no-inv, old | conforms 232/232; UpdIdleDbBackedByDisk at 172, OrderedHistories/UpdDurableCoversCommitted at 202 |
| repro-trunc-abort-old (old code) | Trace no-inv, old | conforms 125/125; UpdIdleDbBackedByDisk at 65 |

Non-vacuity controls (round 2, `spec/output/trace-control-*.log`): the update trace replayed against the old-code model is rejected at line 39 (first serving LearnerShutdown: syncAlive=true vs old-code expectation false); mutants are rejected at their events: SNAP-abort `dbInitialized` flipped (171), `fully` flipped (171), leader decision SNAP->TRUNC (168), leader `maxCommittedTx` +1 (17).

## Update coverage

| Update element | Observed in fresh trace | Compared fields |
|---|---|---|
| LearnerShutdown fully=true (SNAP abort) | diff-sync-after-snap-new | fully, zkRunning, dbInitialized |
| LearnerShutdown fully=false (TRUNC abort, DIFF, serving) | repro-trunc-abort-new, all | fully, zkRunning, syncAlive, dbInitialized |
| ReloadDatabase after clear | diff-sync-after-snap-new | dbInitialized |
| LeaderSyncDecision DIFF/SNAP/TRUNC | all / diff-sync, snap-complete / repro | mode, maxCommittedTx (= model leader tree), committedTx |
| ReceiveSyncMode DIFF/SNAP/TRUNC | all | mode, dbInitialized, plan consistency |
| SyncApplyCommitted (TRUNC) | repro-trunc-abort-new | tx, FIFO on in-memory tree |
| PersistSyncSnapshot (SNAP) | snap-complete-new | stage transition, subsequent FIFO |
| LeakedFlush (stale processor flush) | not observed (no queued request at shutdown in any scenario) | — validation gap; mechanism observed via syncAlive=true |

Gaps: LeakedFlush events, observers, and TRUNC chosen from the committed-log iterator branch are not observed.
