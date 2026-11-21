# Modeling brief coverage

| Frozen requirement | Semantic artifact | Runtime evidence |
|---|---|---|
| Roles and election/discovery/sync/broadcast phases | `base.tla` actions `StartServer` through `FollowerReady` | all retained traces; canonical base |
| accepted/current epochs and quorum decisions | epoch memory/persistence, support/ack/new-leader sets | epoch markers in 5 traces; base and MC invariants |
| DIFF/TRUNC/SNAP synchronization | `SelectSync`, `ApplySync`, sync proposal/commit/snapshot actions | `SyncModeSelected`, `SyncModeApplied`, `BootstrapSnapshot` events |
| queued/volatile/durable/committed/applied transactions | distinct model functions and pipeline actions | proposal through apply markers; `PipelineOrdering` |
| snapshots, persistence, crash/restart/re-election | stable/snapshot state, `Crash`, `StartServer` | 7 starts and 7 crashes per fresh trace; canonical MC |
| independent request processors | queue, append, force, ack, commit, apply transitions | ordering varies in retained traces and is fully replayed |
| type/well-formedness | `TypeOK`, `MCTypeOK`, event shape checks | canonical base/MC and every trace |
| one active leader per epoch | `SingleReadyLeaderPerEpoch` | canonical base/MC and every trace |
| common committed prefix | `CommittedHistoriesArePrefixes` | canonical base/MC and every trace |
| no premature apply | `PipelineOrdering`, `AppliedWasGloballyCommitted` | canonical base and every trace |
| monotonicity with explicit recovery | pipeline sets plus `Crash`/`StartServer`; SNAP recovery window | canonical MC and restart traces |
| epoch/history consistency | `EpochConsistency`, `ServingEpochDurable` | canonical base/MC and every trace |
| justified synchronized broadcast | sync guards, `syncApplied`, `FollowerReady` | synchronization markers in every trace |

Canonical exhaustive bounds are recorded in `base.cfg` and `MC.cfg`. Legacy
hunt configurations and their prior logs remain present. The three new broader
two-voter fault runs under `spec/output/repair/*open-frontier.log` timed out with
nonzero queues and are classified only as limited coverage, never as completed
model checking.

