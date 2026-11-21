# Validation handoff and campaign summary (incremental run, case-002)

## Identity

- Source: `artifact/` neutral commit `update` 2efbdfc3754df193bce05b9792297c813377cdaf
  (baseline 1414ebfb1d16fd81abc38550a96950d919ecf805), instrumented by
  `harness/patches/instrumentation.patch` (verified equal to `git diff` of the tree).
- Harness command: `timeout 3300s bash harness/run.sh` (default five scenarios);
  reproduction: `SPECULA_SCENARIOS=repro-initial-state-failure bash harness/run.sh`;
  old-version control: `bash harness/repro/run-old-control.sh`.
- Reference: `spec/base.tla`, `spec/MC.tla`, `spec/Update.tla`,
  `spec/UpdateProps.tla`, `spec/Trace.tla` (final revision after the repairs in
  `spec/changelog.md`). Validation changed semantic spec files (repairs listed
  in the changelog, each with source evidence).

## Fresh new-version traces (retained suite)

All replay through reference actions with `TraceMatched`, every reference
invariant, and `HistoryPositionsMonotonicExceptRecovery` enabled
(ledger `spec/output/trace-suite-final4.ndjson`; logs `spec/output/trace-final4-*.log`, final reference):

| Trace | Events | Origin | Result |
|---|---:|---|---|
| traces/follower-snap.ndjson | 21 | V0 scenario rerun on new code | PASS |
| traces/follower-diff.ndjson | 20 | V0 scenario rerun on new code | PASS |
| traces/quorum-startup-mutation-shutdown.ndjson | 100 | V0 scenario rerun on new code | PASS |
| traces/leader-abandon-restart-recovery.ndjson | 346 | V0 scenario rerun on new code | PASS |
| traces/diff-sync-consistency.ndjson | 152 | update's DIFFSyncConsistencyTest | PASS |
| traces/repro-initial-state-failure.ndjson | 494 | reproduction derived from the update's test (attempt 3) | PASS under `Trace-conformance.cfg` (it violates protocol safety by design: evidence); the test itself FAILS = MC-2 reproduced |

Completion evidence: universal `TraceMatched` (Category A) with WF; each
completed check reports zero states left on the queue.

Negative controls (`traces/negative-controls/`, synthetic single mutations):
all four rejected (`spec/output/trace-neg-neg-*.log`).

Archived traces: `traces/archived-v0/*` — superseded: produced by the old code
(NEWLEADER records not queued before the ACK; `BroadcastReady` after
`startup()`), without config lines or the update-local events that the current
Trace spec requires. `traces/superseded-run1/*` — run-1 traces with sender
probes emitted after the send (fixed); the attempt-1 reproduction trace there
also replays (TraceMatched) on the final reference.

## Coverage of affected and interaction actions

| Action (reference) | Probe | Observed in |
|---|---|---|
| PersistCurrentEpoch (learner) | CurrentEpochPersisted | all six |
| ClearSyncMode (moved into NEWLEADER) | SyncModeChanged(NONE) | all six |
| StartupWithoutServing (new) | ZkStartup(INITIAL) | all six |
| LogSyncProposal at NEWLEADER (before ACK) | ProposalQueued in sync before NewLeaderAckSent | follower-diff, diff-sync-consistency, repro |
| LogSyncProposal after UPTODATE | ProposalQueued in sync after BroadcastReady | follower-snap |
| SendNewLeaderAck | NewLeaderAckSent | all six |
| StartServing (new) | BroadcastReady | all six |
| ReceiveNewLeaderAck / LeaderActivate | NewLeaderAckReceived / ZkStartup(RUNNING) | quorum, leader-abandon, diff-sync, repro |
| FsyncOne after the NEWLEADER ACK (window) | TxnDurable after NewLeaderAckSent | follower-diff, diff-sync, repro |
| BeginElection from INITIAL (no fast-forward) | PhaseChanged(election) while INITIAL | diff-sync, repro |
| Leaked SyncRequestProcessor after failure | TxnDurable after PhaseChanged(election) | diff-sync, repro |
| FLE win with stale data tree | PeerRoleChanged(leading) with data-tree zxid | diff-sync (116), repro |
| In-JVM restart (Crash/Restart) | reload visible in next PeerRoleChanged zxid | diff-sync, repro, leader-abandon |
| SyncDiff / SyncSnap | SyncModeChanged DIFF/SNAP | all / follower-snap, leader-abandon, repro |
| SyncTrunc | SyncModeChanged(TRUNC) | **not observed in any fresh trace (validation gap; MC reachability canary only)** |
| ReceiveSyncProposal/ReceiveSyncCommit (forwarded during sync) | SyncProposalReceived/SyncCommitReceived not in directive | follower-snap (fixture) |

Update fields compared by active Trace predicates: `zkState` (ZkStartup aux,
BroadcastReady), `syncBuf` head and `proposed` membership (ProposalQueued in
sync), `nlAckSent`/epoch (NewLeaderAckSent), `nlAcks` (NewLeaderAckReceived),
`UpToDateReady` (UpToDateReceived), data-tree position (`PosMatches(applied)`)
on peer probes, `syncCommits` head (CommitDelivered in sync).

Per-trace event inventory:

| Event | diff-sync-consistency | follower-diff | follower-snap | leader-abandon-restart-recovery | quorum-startup-mutation-shutdown | repro-initial-state-failure |
|---|---|---|---|---|---|---|
| AcceptedEpochPersisted | 8 | 1 | 1 | 9 | 2 | 12 |
| AckReceived | 3 | 0 | 0 | 27 | 12 | 52 |
| BroadcastReady | 3 | 1 | 1 | 6 | 1 | 3 |
| CommitDelivered | 2 | 1 | 1 | 22 | 6 | 26 |
| CurrentEpochPersisted | 8 | 1 | 1 | 9 | 2 | 12 |
| ElectionWon | 9 | 0 | 0 | 9 | 2 | 13 |
| FollowerRegistered | 5 | 1 | 1 | 6 | 1 | 7 |
| LeaderCommitted | 1 | 0 | 0 | 13 | 6 | 25 |
| LeaderProposed | 2 | 0 | 0 | 14 | 6 | 27 |
| NewLeaderAckReceived | 5 | 0 | 0 | 6 | 1 | 7 |
| NewLeaderAckSent | 5 | 1 | 1 | 6 | 1 | 7 |
| PeerRoleChanged | 19 | 0 | 0 | 19 | 4 | 27 |
| PhaseChanged | 33 | 3 | 3 | 37 | 8 | 47 |
| ProposalQueued | 4 | 1 | 1 | 22 | 6 | 28 |
| SnapshotInstalled | 0 | 0 | 1 | 1 | 0 | 0 |
| SyncCommitReceived | 2 | 1 | 1 | 0 | 0 | 2 |
| SyncModeChanged | 10 | 2 | 2 | 12 | 2 | 14 |
| SyncProposalReceived | 2 | 1 | 1 | 0 | 0 | 2 |
| SyncSelected | 5 | 1 | 1 | 6 | 1 | 7 |
| TxnAppended | 6 | 1 | 1 | 36 | 12 | 55 |
| TxnApplied | 3 | 1 | 1 | 35 | 12 | 51 |
| TxnDurable | 6 | 1 | 1 | 36 | 12 | 55 |
| UpToDateReceived | 3 | 1 | 1 | 6 | 1 | 3 |
| ZkStartup | 8 | 1 | 1 | 9 | 2 | 12 |
| **events** | **152** | **20** | **21** | **346** | **100** | **494** |

## Model-checking campaigns

All runs: `tools/run_tlc.sh` (outer `timeout`, graceful `-Dtlc2.TLC.stopAfter`,
states under `/dev/shm/specula-e2e-case-002/`, removed after each run). Runs
tagged rev-A/rev-B used earlier reference revisions and are provisional; every
conclusion below is backed by a run on the final reference
(`spec/output/FINAL_MODEL_SHA256`, from 2026-11-18T21:52:06Z). A
budget-terminated run is LIMITED_COVERAGE, never a proof.

Final-reference outcome by campaign (incremental order):

| Step | Campaign | Final run(s) | Outcome |
|---|---|---|---|
| 0 | Standard convergence (`MC.cfg`, core + structural invariants) | Z1 (BFS 30 min) | no violation; 40.8M distinct states, depth 42, queue nonempty: LIMITED_COVERAGE |
| 1 | Full update properties over complete `MCNext` from `MCInit` (`Update-full.cfg`) | Z2a (BFS 20 min), Z2b (sim 20 min) | no violation within budget (bug paths are deeper than the explored frontier): LIMITED_COVERAGE |
| 1b | Full `MCNext` from the reachable `FocusInit` (`Update-full-focusinit.cfg`) | Z5 | VIOLATION `CommittedPersistedOnQuorum` (focused violation admitted by full reference behavior) |
| 2 | Concrete focused (`Update-concrete.cfg`, from FocusInit) | Z3 | VIOLATION `CommittedPersistedOnQuorum` (MC-1), 20 states; final state = FocusInit2 |
| 2b | Concrete focused from FocusInit2 (`Update-concrete2-A2.cfg`) | Z3b | VIOLATION `LeaderCompleteness` (MC-2) |
| 2c | Crash variant (`Update-concrete2-A2-crash.cfg`, hunt-only ACTION_CONSTRAINT) | Z3c | VIOLATION `LeaderCompleteness` (MC-1 consequence) |
| 3a | Open focused with `EnvUpdate` (`Update-open.cfg`) | Z4a | VIOLATION `CommittedPersistedOnQuorum` (same as concrete) |
| 3b | Discharge of omitted TakeSnapshot/DropMessage (`Update-discharge.cfg`) | Z4b | no violation of `DischargeContext`; 8.4M distinct, depth 32: LIMITED_COVERAGE |
| 4 | Scenario hunts 1-4 (`MC-hunt-*.cfg`) | Z7 (BFS 15 min each), Z9 (sim 10 min each) | no violation; depth 30-35: LIMITED_COVERAGE |
| 4r | Reachability canaries (`MC-canary-*.cfg`, `Update-reach-focusinit-exact.cfg`) | Z6, Z8, Z8b | all witnessed: leader established/active, follower broadcast, DIFF ACK before fsync, committed+applied at follower, recovery, sync, SNAP, TRUNC (tight bounds), exact FocusInit |
| 5 | Final full checks after repairs | Z1, Z2a/b, Z7/Z9 on the final reference | as above |

Real-implementation evidence (final reference): `CommittedPersistedOnQuorum`
violated on `traces/diff-sync-consistency.ndjson` after event 94;
`LeaderCompleteness` after event 139 and `CommittedHistoriesPrefix` after event
211 on `traces/repro-initial-state-failure.ndjson` (`spec/evidence/trace-A1/`,
`spec/evidence/trace-A2/`). The activation of an older-epoch record (the
broad canary `CanaryActivationCommitsOldEpoch` was not reached from `MCInit`
within budget) is witnessed by Z3/Z5 from the reachable FocusInit and by the
real traces (diff-sync event 94; leader-abandon epoch-2/3 activations).

Validation gaps: SyncTrunc is not observed in any fresh implementation trace
(model reachability only); MC-1's crash consequence is not reproduced in-JVM.

### All runs (generated from the logs by `spec/tools/campaign_table.py`)

| Run | Config | Mode | Budget (min) | Workers | Explored | Depth | Outcome | Model |
|---|---|---|---|---|---|---|---|---|
| C1-MC-bfs | MC.cfg | BFS | 30 | 10 | 21495266 distinct | 38 | VIOLATION ServingApplyCommitted | rev-A (provisional) |
| C2a-update-full-bfs | Update-full.cfg | BFS | 30 | 10 | 41,717,049 distinct | - | exit killed/running | rev-A (provisional) |
| C2b-update-full-sim | Update-full.cfg | sim | 30 | 6 | 113330028 states / 944304 traces | - | exit killed/running | rev-A (provisional) |
| C4a-update-open-bfs | Update-open.cfg | BFS | 15 | 4 | 224548 distinct | 20 | VIOLATION CommittedPersistedOnQuorum | rev-A (provisional) |
| C4b-update-discharge | Update-discharge.cfg | BFS | 15 | 4 | 7862435 distinct | 32 | no violation; LIMITED_COVERAGE (time budget, queue 1711951) | rev-A (provisional) |
| C6-reach-focusinit-sim | Update-reach-focusinit.cfg | sim | 30 | 4 | 84140110 states / 701079 traces | - | VIOLATION CanaryFocusInitShape | rev-A (provisional) |
| F2a-update-full-bfs | Update-full.cfg | BFS | 30 | 10 | 42034502 distinct | 38 | no violation; LIMITED_COVERAGE (time budget, queue 9769495) | rev-B (provisional) |
| F2b-update-full-sim | Update-full.cfg | sim | 30 | 8 | 148898833 states / 1240673 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| F4a-update-open-bfs | Update-open.cfg | BFS | 15 | 3 | 208545 distinct | 20 | VIOLATION CommittedPersistedOnQuorum | rev-B (provisional) |
| F4b-update-discharge | Update-discharge.cfg | BFS | 20 | 3 | 11210721 distinct | 34 | no violation; LIMITED_COVERAGE (time budget, queue 2251646) | rev-B (provisional) |
| F5-update-full-focusinit | Update-full-focusinit.cfg | BFS | 15 | 3 | 183282 distinct | 20 | VIOLATION CommittedPersistedOnQuorum | rev-B (provisional) |
| F6-reach-focusinit-sim | Update-reach-focusinit.cfg | sim | 20 | 2 | 12590960 states / 104913 traces | - | VIOLATION CanaryFocusInitShape | rev-B (provisional) |
| F6x-reach-focusinit-exact | Update-reach-focusinit-exact.cfg | BFS | 20 | 6 | 1742495 distinct | 26 | VIOLATION CanaryFocusInitExact | rev-B (provisional) |
| H-election-bfs | MC-hunt-election.cfg | BFS | 15 | 3 | 6790971 distinct | 31 | no violation; LIMITED_COVERAGE (time budget, queue 1823922) | rev-B (provisional) |
| H-election-sim | MC-hunt-election.cfg | sim | 10 | 4 | 52087504 states / 434011 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| H-mutation-bfs | MC-hunt-mutation.cfg | BFS | 15 | 3 | 6488908 distinct | 35 | no violation; LIMITED_COVERAGE (time budget, queue 1231409) | rev-B (provisional) |
| H-mutation-sim | MC-hunt-mutation.cfg | sim | 10 | 4 | 30988038 states / 258205 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| H-recovery-bfs | MC-hunt-recovery.cfg | BFS | 15 | 3 | 5583293 distinct | 30 | no violation; LIMITED_COVERAGE (time budget, queue 1372469) | rev-B (provisional) |
| H-recovery-sim | MC-hunt-recovery.cfg | sim | 10 | 4 | 38831627 states / 323563 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| H-sync-bfs | MC-hunt-sync.cfg | BFS | 15 | 3 | 5868088 distinct | 31 | no violation; LIMITED_COVERAGE (time budget, queue 1358521) | rev-B (provisional) |
| H-sync-sim | MC-hunt-sync.cfg | sim | 10 | 4 | 30763387 states / 256332 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| R1-MC-bfs | MC.cfg | BFS | 30 | 12 | 43218375 distinct | 42 | no violation; LIMITED_COVERAGE (time budget, queue 7009587) | rev-B (provisional) |
| R1s-MC-sim | MC.cfg | sim | 15 | 10 | 74567749 states / 1122813 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| R3-update-concrete-A1 | Update-concrete.cfg | BFS | 15 | 4 | 118073 distinct | 20 | VIOLATION CommittedPersistedOnQuorum | rev-B (provisional) |
| R3b-update-concrete2-A2-initial | Update-concrete2-A2.cfg | BFS | 20 | 5 | 1069684 distinct | 21 | VIOLATION LeaderCompleteness | rev-B (provisional) |
| R3c-update-concrete2-A2-crash | Update-concrete2-A2-crash.cfg | BFS | 20 | 5 | 1189593 distinct | 23 | VIOLATION LeaderCompleteness | rev-B (provisional) |
| Z1-MC-bfs | MC.cfg | BFS | 30 | 12 | 42684229 distinct | 42 | no violation; LIMITED_COVERAGE (time budget, queue 6885529) | final |
| Z2a-update-full-bfs | Update-full.cfg | BFS | 20 | 8 | 23331592 distinct | 35 | no violation; LIMITED_COVERAGE (time budget, queue 5804656) | final |
| Z2b-update-full-sim | Update-full.cfg | sim | 20 | 4 | 51743326 states / 431134 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | final |
| Z3-update-concrete-A1 | Update-concrete.cfg | BFS | 10 | 2 | 110714 distinct | 20 | VIOLATION CommittedPersistedOnQuorum | final |
| Z3b-update-concrete2-A2-initial | Update-concrete2-A2.cfg | BFS | 12 | 2 | 1190305 distinct | 21 | VIOLATION LeaderCompleteness | final |
| Z3c-update-concrete2-A2-crash | Update-concrete2-A2-crash.cfg | BFS | 12 | 2 | 936986 distinct | 22 | VIOLATION LeaderCompleteness | final |
| Z4a-update-open-bfs | Update-open.cfg | BFS | 10 | 2 | 201727 distinct | 20 | VIOLATION CommittedPersistedOnQuorum | final |
| Z4b-update-discharge | Update-discharge.cfg | BFS | 20 | 3 | 8400778 distinct | 32 | no violation; LIMITED_COVERAGE (time budget, queue 1816363) | final |
| Z5-update-full-focusinit | Update-full-focusinit.cfg | BFS | 10 | 2 | 180699 distinct | 20 | VIOLATION CommittedPersistedOnQuorum | final |
| Z6-reach-focusinit-exact | Update-reach-focusinit-exact.cfg | BFS | 15 | 3 | 1539858 distinct | 25 | VIOLATION CanaryFocusInitExact | final |
| Z7-hunt-election-bfs | MC-hunt-election.cfg | BFS | 15 | 3 | 7197070 distinct | 31 | no violation; LIMITED_COVERAGE (time budget, queue 1912210) | final |
| Z7-hunt-mutation-bfs | MC-hunt-mutation.cfg | BFS | 15 | 3 | 6538255 distinct | 35 | no violation; LIMITED_COVERAGE (time budget, queue 1236742) | final |
| Z7-hunt-recovery-bfs | MC-hunt-recovery.cfg | BFS | 15 | 3 | 5901753 distinct | 30 | no violation; LIMITED_COVERAGE (time budget, queue 1436937) | final |
| Z7-hunt-sync-bfs | MC-hunt-sync.cfg | BFS | 15 | 3 | 6139900 distinct | 31 | no violation; LIMITED_COVERAGE (time budget, queue 1415085) | final |
| Z8-canary-CanaryCommittedApplied-w16 | MC-canary-CanaryCommittedApplied.cfg | BFS | 12 | 16 | 4743944 distinct | 34 | VIOLATION CanaryCommittedApplied | final |
| Z8-canary-CanaryCommittedApplied | MC-canary-CanaryCommittedApplied.cfg | BFS | 8 | 2 | 3227840 distinct | 31 | no violation; LIMITED_COVERAGE (time budget, queue 723102) | final |
| Z8-canary-CanaryDiffAckBeforeFsync | MC-canary-CanaryDiffAckBeforeFsync.cfg | BFS | 8 | 2 | 439350 distinct | 24 | VIOLATION CanaryDiffAckBeforeFsync | final |
| Z8-canary-CanaryFollowerBroadcast | MC-canary-CanaryFollowerBroadcast.cfg | BFS | 8 | 2 | 157496 distinct | 21 | VIOLATION CanaryFollowerBroadcast | final |
| Z8-canary-CanaryLeaderActive | MC-canary-CanaryLeaderActive.cfg | BFS | 8 | 2 | 76352 distinct | 19 | VIOLATION CanaryLeaderActive | final |
| Z8-canary-CanaryLeaderEstablished | MC-canary-CanaryLeaderEstablished.cfg | BFS | 8 | 2 | 2065 distinct | 11 | VIOLATION CanaryLeaderEstablished | final |
| Z8-canary-CanaryRecovery | MC-canary-CanaryRecovery.cfg | BFS | 8 | 2 | 1450 distinct | 8 | VIOLATION CanaryRecovery | final |
| Z8-canary-CanarySnap | MC-canary-CanarySnap.cfg | BFS | 8 | 2 | 5420 distinct | 12 | VIOLATION CanarySnap | final |
| Z8-canary-CanarySync | MC-canary-CanarySync.cfg | BFS | 8 | 2 | 2742 distinct | 12 | VIOLATION CanarySync | final |
| Z8-canary-CanaryTrunc-tight | MC-canary-CanaryTrunc-tight.cfg | BFS | 8 | 2 | 566830 distinct | 31 | VIOLATION CanaryTrunc | final |
| Z9-hunt-election-sim | MC-hunt-election.cfg | sim | 10 | 5 | 65606657 states / 546651 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | final |
| Z9-hunt-mutation-sim | MC-hunt-mutation.cfg | sim | 10 | 5 | 39677633 states / 330602 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | final |
| Z9-hunt-recovery-sim | MC-hunt-recovery.cfg | sim | 10 | 5 | 46998198 states / 391605 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | final |
| Z9-hunt-sync-sim | MC-hunt-sync.cfg | sim | 10 | 5 | 39768625 states / 331362 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | final |
| canary-CanaryActivationCommitsOldEpoch | MC-canary-CanaryActivationCommitsOldEpoch.cfg | BFS | 6 | 6 | 6985382 distinct | 35 | no violation; LIMITED_COVERAGE (time budget, queue 1294583) | rev-B (provisional) |
| canary-CanaryCommittedApplied | MC-canary-CanaryCommittedApplied.cfg | BFS | 6 | 6 | 4641382 distinct | 34 | VIOLATION CanaryCommittedApplied | rev-B (provisional) |
| canary-CanaryDiffAckBeforeFsync | MC-canary-CanaryDiffAckBeforeFsync.cfg | BFS | 6 | 6 | 476617 distinct | 25 | VIOLATION CanaryDiffAckBeforeFsync | rev-B (provisional) |
| canary-CanaryFollowerBroadcast | MC-canary-CanaryFollowerBroadcast.cfg | BFS | 6 | 6 | 174555 distinct | 22 | VIOLATION CanaryFollowerBroadcast | rev-B (provisional) |
| canary-CanaryLeaderActive | MC-canary-CanaryLeaderActive.cfg | BFS | 6 | 6 | 93702 distinct | 20 | VIOLATION CanaryLeaderActive | rev-B (provisional) |
| canary-CanaryLeaderEstablished | MC-canary-CanaryLeaderEstablished.cfg | BFS | 6 | 6 | 2627 distinct | 12 | VIOLATION CanaryLeaderEstablished | rev-B (provisional) |
| canary-CanaryRecovery | MC-canary-CanaryRecovery.cfg | BFS | 6 | 6 | 2187 distinct | 10 | VIOLATION CanaryRecovery | rev-B (provisional) |
| canary-CanarySnap | MC-canary-CanarySnap.cfg | BFS | 6 | 6 | 5501 distinct | 12 | VIOLATION CanarySnap | rev-B (provisional) |
| canary-CanarySync | MC-canary-CanarySync.cfg | BFS | 6 | 6 | 3203 distinct | 12 | VIOLATION CanarySync | rev-B (provisional) |
| canary-CanaryTrunc-tight | MC-canary-CanaryTrunc-tight.cfg | BFS | 15 | 4 | 583627 distinct | 31 | VIOLATION CanaryTrunc | rev-B (provisional) |
| canary-CanaryTrunc | MC-canary-CanaryTrunc.cfg | BFS | 6 | 6 | 5420062 distinct | 30 | no violation; LIMITED_COVERAGE (time budget, queue 1286497) | rev-B (provisional) |
| canary-sim-CanaryActivationCommitsOldEpoch | MC-canary-CanaryActivationCommitsOldEpoch.cfg | sim | 12 | 4 | 57137318 states / 380870 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| canary-sim-CanaryTrunc | MC-canary-CanaryTrunc.cfg | sim | 12 | 4 | 60484872 states / 403185 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-B (provisional) |
| hunt-A2-bfs | Update-concrete-A2.cfg | BFS | 12 | 16 | 35661771 distinct | 37 | no violation; LIMITED_COVERAGE (time budget, queue 8847823) | rev-A (provisional) |
| hunt-A2-crash-variant | Update-concrete2-A2-crash.cfg | BFS | 20 | 8 | 1505863 distinct | 25 | VIOLATION LeaderCompleteness | rev-A (provisional) |
| hunt-A2-from-focus2 | Update-concrete2-A2.cfg | BFS | 15 | 8 | 1259842 distinct | 22 | VIOLATION LeaderCompleteness | rev-A (provisional) |
| hunt-A2-sim | Update-concrete-A2.cfg | sim | 12 | 16 | 127286474 states / 1414155 traces | - | no violation; LIMITED_COVERAGE (simulation budget) | rev-A (provisional) |
| shakedown-MC | MC.cfg | BFS | 3 | 16 | 8924812 distinct | 34 | no violation; LIMITED_COVERAGE (time budget, queue 1895867) | rev-A (provisional) |
| shakedown-concrete | Update-concrete.cfg | BFS | 5 | 16 | 137221 distinct | 21 | VIOLATION CommittedPersistedOnQuorum | rev-A (provisional) |
