# Modeling brief coverage

## Scenarios

| Brief scenario | Spec actions/state | Canonical bounded evidence | Implementation trace |
|---|---|---|---|
| 1 Election/epoch | `BeginElection` through `LeaderBroadcast` | `base.cfg`, `MC.cfg`, and election reachability logs | quorum and restart/recovery traces |
| 2 DIFF/TRUNC/SNAP | `EnterSyncPhase`, `SelectSync`, `CompleteSync` | canonical configs plus sync reachability logs | SNAP, DIFF, and restart/recovery traces |
| 3 Proposal/commit/apply | proposal, append, fsync, ACK, commit, apply actions | canonical configs plus mutation reachability logs | all retained scenarios with pipeline events |
| 4 Crash/restart/recovery | `TakeSnapshot`, `Crash`, `Restart`, sync repair | canonical configs plus recovery reachability logs | abandonment/restart/recovery trace |

## Invariants

| Safety property | Defined | Wired | Enabled |
|---|---|---|---|
| `TypeOK` | `base.tla` | inherited by `MC.tla` | `base.cfg`, `MC.cfg`, `Trace.cfg` |
| `ElectionSafety` | `base.tla` | inherited | base, MC, trace cfgs |
| `OneActiveLeaderPerEpoch` | `base.tla` | inherited | base, MC, trace cfgs |
| `CommittedHistoriesPrefix` | `base.tla` | inherited | base, MC, trace cfgs |
| `ApplyRequiresCommitCertificate` | `base.tla` | inherited | base, MC, trace cfgs |
| `PipelinePrefix` | `base.tla` | inherited | base, MC, trace cfgs |
| `EpochHistoryConsistency` | `base.tla` | inherited | base, MC, trace cfgs |
| `SyncCompletionJustified` | `base.tla` | inherited | base, MC, trace cfgs |
| `HistoryPositionsMonotonicExceptRecovery` | `base.tla` | inherited | base and MC cfgs |

## Questions and disposition

| Brief question | Trigger | Expected property | Target/result |
|---|---|---|---|
| Q1 split-brain same epoch | concurrent votes/election | election invariants | checked, no violation in completed bound |
| Q2 unjustified broadcast | split sync actions/modes | sync justification | checked, no violation in completed bound |
| Q3 apply without certificate | processor/message reorderings | apply certificate | checked, no violation in completed bound |
| Q4 illegal rollback | crash/restart/sync replacement | rollback temporal property | checked, no violation in completed bound |

Negative invariants (`NotElectionReached`, `NotSyncReached`,
`NotMutationReached`, `NotRecoveryReached`) were intentionally violated by their
hunt configs. Those counterexamples are reachability evidence, not bugs.

Coverage remains limited by explicit finite constants. The fresh canonical base
and MC models both use three servers, one transaction, two epochs, and level 23;
MC additionally retains one crash, one message drop, and one snapshot. They
naturally exhausted 6,354,157 and 21,701,056 distinct states respectively, with
zero states left on either queue. Broader timeout/open-frontier outputs remain
preserved only as limited evidence.
