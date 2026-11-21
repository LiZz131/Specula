# Brief coverage (incremental run, read from the actual cfg files)

## Scenarios (brief §2 and §8)

| Scenario | Hunt / focused cfg(s) | Reachability witness |
|---|---|---|
| 1 Election, epoch persistence, activation | `MC-hunt-election.cfg` | `MC-canary-CanaryLeaderEstablished.cfg`, `MC-canary-CanaryLeaderActive.cfg` |
| 2 DIFF/TRUNC/SNAP synchronization | `MC-hunt-sync.cfg` | `MC-canary-CanarySync.cfg`, `MC-canary-CanaryTrunc-tight.cfg` (TRUNC needs a deep path; the broad `MC-canary-CanaryTrunc.cfg` did not reach it within budget), `MC-canary-CanarySnap.cfg`, `MC-canary-CanaryFollowerBroadcast.cfg` |
| 3 Proposal pipeline, durability, commit, apply | `MC-hunt-mutation.cfg` | `MC-canary-CanaryCommittedApplied.cfg` |
| 4 Snapshot, crash, restart, re-election | `MC-hunt-recovery.cfg` | `MC-canary-CanaryRecovery.cfg` |
| 5 NEWLEADER ACK vs durability (update) | `Update-full.cfg`, `Update-concrete.cfg`, `Update-open.cfg`, `Update-full-focusinit.cfg`, `Update-concrete2-A2-crash.cfg` | `MC-canary-CanaryDiffAckBeforeFsync.cfg`; `Update-reach-focusinit-exact.cfg` (exact FocusInit), `Update-reach-focusinit.cfg`; real trace `diff-sync-consistency` |
| 6 INITIAL-state learner failure (update) | `Update-concrete2-A2.cfg` (FocusInit2), `Update-full.cfg` | real traces `diff-sync-consistency` (events 96-118) and `repro-initial-state-failure` |

## Invariants (brief §5) — defined / wired / enabled

| Invariant | Defined | Enabled in |
|---|---|---|
| `TypeOK` | base.tla | MC.cfg, all hunts, Update-*.cfg, Trace.cfg |
| `ElectionSafety` | base.tla | MC.cfg, MC-hunt-election.cfg, Trace.cfg, Update-* (via `UpdateControl`) |
| `OneActiveLeaderPerEpoch` | base.tla (migrated) | MC.cfg, MC-hunt-election.cfg, Trace.cfg |
| `CommittedHistoriesPrefix` | base.tla | MC.cfg, MC-hunt-sync/mutation/recovery.cfg, Trace.cfg, Update-* (via `UpdateControl`) |
| `ServingApplyCommitted` (revises `ApplyRequiresCommitCertificate`) | base.tla | MC.cfg, MC-hunt-sync/mutation/recovery.cfg, Trace.cfg |
| `PipelinePrefix` | base.tla | MC.cfg, MC-hunt-sync/mutation.cfg, Trace.cfg |
| `EpochHistoryConsistency` | base.tla | MC.cfg, MC-hunt-election/recovery.cfg, Trace.cfg |
| `SyncCompletionJustified` | base.tla | MC.cfg, MC-hunt-sync.cfg, Trace.cfg |
| `HistoryPositionsMonotonicExceptRecovery` (action) | base.tla | MC.cfg, MC-hunt-recovery.cfg, Trace.cfg (PROPERTIES) |
| `StructuralInvariants` (ProposedQueuedEqual, SyncBufferOnlyInSync, NewLeaderAckOnlyAfterEpoch) | MC.tla | MC.cfg |
| `CommittedPersistedOnQuorum` (new) | UpdateProps.tla | Update-full.cfg, Update-full-focusinit.cfg, Update-concrete.cfg, Update-open.cfg, TraceUpdateEvidence.cfg |
| `LeaderCompleteness` (new) | UpdateProps.tla | Update-full.cfg, Update-full-focusinit.cfg, Update-concrete.cfg, Update-concrete-A2.cfg, Update-concrete2-A2.cfg, Update-concrete2-A2-crash.cfg, Update-open.cfg, TraceUpdateEvidence*.cfg |
| `DischargeContext` (temporal) | Update.tla | Update-discharge.cfg |

`MC.cfg` lists the update properties as comments (they are checked by the
Update cfgs).

## Findings (brief §6.1)

| ID | Trigger | Expected violation | Targeting cfg | Outcome |
|---|---|---|---|---|
| Q1 | concurrent elections | ElectionSafety / OneActiveLeaderPerEpoch | MC-hunt-election.cfg | see validation-summary |
| Q2 | broadcast without completed sync | SyncCompletionJustified | MC-hunt-sync.cfg | see validation-summary |
| Q3 | apply without certificate | ServingApplyCommitted | MC-hunt-mutation.cfg | see validation-summary |
| Q4 | rollback outside recovery | HistoryPositionsMonotonicExceptRecovery | MC-hunt-recovery.cfg | see validation-summary |
| Q5 | ACK before durability + crash | CommittedPersistedOnQuorum, LeaderCompleteness | Update-concrete.cfg, Update-concrete2-A2-crash.cfg | violated (MC-1) |
| Q6 | INITIAL-state learner failure | LeaderCompleteness | Update-concrete2-A2.cfg | violated (MC-2), reproduced |

Code-review-only items CR-A (liveness) and CR-B (shutdown ordering abstraction)
are recorded in the brief; they have no hunt cfg by design.
