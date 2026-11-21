# Modeling brief coverage

This is the standard-path semantic copy of the compatible legacy artifact at
`../brief-coverage.md`, updated for the repaired canonical suite.

## Scenarios

| Brief scenario | Spec actions/state | Canonical bounded evidence | Implementation trace |
|---|---|---|---|
| 1 Election/epoch | `BeginElection` through `LeaderBroadcast` | `base.cfg`, `MC.cfg`, and `MC-hunt-election.cfg` | quorum and restart/recovery traces |
| 2 DIFF/TRUNC/SNAP | `EnterSyncPhase`, `SelectSync`, `CompleteSync` | canonical configs plus `MC-hunt-sync.cfg` | SNAP, DIFF, and restart/recovery traces |
| 3 Proposal/commit/apply | proposal, append, fsync, ACK, commit, apply actions | canonical configs plus `MC-hunt-mutation.cfg` | all retained scenarios with pipeline events |
| 4 Crash/restart/recovery | `TakeSnapshot`, `Crash`, `Restart`, sync repair | canonical configs plus `MC-hunt-recovery.cfg` | abandonment/restart/recovery trace |

## Invariants

| Safety property | Defined | Enabled |
|---|---|---|
| `TypeOK` | `base.tla` | base, MC, trace cfgs |
| `ElectionSafety` | `base.tla` | base, MC, trace cfgs |
| `OneActiveLeaderPerEpoch` | `base.tla` | base, MC, trace cfgs |
| `CommittedHistoriesPrefix` | `base.tla` | base, MC, trace cfgs |
| `ApplyRequiresCommitCertificate` | `base.tla` | base, MC, trace cfgs |
| `PipelinePrefix` | `base.tla` | base, MC, trace cfgs |
| `EpochHistoryConsistency` | `base.tla` | base, MC, trace cfgs |
| `SyncCompletionJustified` | `base.tla` | base, MC, trace cfgs |
| `HistoryPositionsMonotonicExceptRecovery` | `base.tla` | base and MC cfgs |

The canonical base and MC bounds retain three voting servers, majority quorum,
two epochs (including re-election), one complete transaction, one bounded
crash, drop, and snapshot in MC, and exhaustive BFS through TLC level 23. The
fresh terminal suite exhausted 6,354,157 distinct base states and 21,701,056
distinct MC states with zero states left on either queue. That depth exceeds the
preserved depth-22 mutation/apply reachability witness. Pre-existing broader
runs remain preserved as timeout/open-frontier evidence and are not represented
as proof.

## Trace-validation coverage

`Trace.tla` accepts no scenario-name filter. Every retained NDJSON file is run
separately with `TraceMatched` enabled. The trace input assumption checks the
complete event schema; each step checks all five captured state fields (using
documented unknown sentinels) and the event-specific zxid/pipeline position.

## Incremental update coverage (current run)

| Update scenario | Reference actions | Update.tla / cfg | Properties enabled | Trace evidence |
|---|---|---|---|---|
| U1 ACK vs durability | ReceiveSyncPayload, PersistCurrentEpoch, ClearSyncMode, AckNewLeader, AppendOne, FsyncOne, LeaderBroadcast | `Update-focused-ackdurable.cfg`, `Update-focused-quorumdurable.cfg`, `Update-full.cfg` | NewLeaderAckDurable, CommittedDurableOnQuorum | follower-diff (ev 12), update-observe-ack-durability, update-diff-sync-consistency (ev 82-89); TraceSync action replay |
| U2 crash in window | + Crash, Restart, election chain | `Update-hunt-postact-crash.cfg`, `Update-focused-completeness.cfg`, `Update-recovery-full.cfg` | LeaderCompleteness, CommittedHistoriesPrefix | (crash not injected in real runs; model only) |
| U3 post-NEWLEADER COMMIT | outside reference sync scope | n/a (code observation CR-1) | n/a | update-observe-commit-after-newleader + surefire NPE |
| U4 aborted sync (INITIAL) | BeginElection(sync), AppendOne/FsyncOne (leaked), CastVote/WinElection (memHist), sync chain | `Update-hunt-postact-leak.cfg`, `Update-hunt-postact-syncedlog.cfg`, `Update-focused-syncedlog.cfg`, `Update-hunt-postact-full.cfg` | LeaderCompleteness, SyncedLogMatchesLeader | update-diff-sync-consistency (ev 87-126) |
| control (unaffected) | all | `MC.cfg`, `Update-focused.cfg` | ElectionSafety, OneActiveLeaderPerEpoch + all prior invariants | all traces |

Reachability canaries (expected violations): `Update-reach-nlack-logged.cfg`,
`Update-reach-uptodate.cfg`, `Update-reach-activate.cfg`,
`Update-reach-recovery-shape.cfg` (focused initial family reachable from MCInit),
inherited `MC-hunt-*.cfg`.

Additional full-model simulations from `MCInit`: `Update-full.cfg` (simulate,
depth 100), `Update-full-sim-quorum.cfg`, `Update-full-sim-completeness.cfg`
(three epochs, two crashes), `MC-sim.cfg`. Ghost/divergence hunts:
`Update-reach-bothacked.cfg` (witness), `Update-hunt-ghost.cfg`,
`Update-hunt-ghost-full.cfg`.
