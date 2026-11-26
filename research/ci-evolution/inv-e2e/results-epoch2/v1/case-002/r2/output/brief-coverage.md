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

---

## Incremental update coverage (run incr-8c80add29fe2)

| Update Scenario | Reference actions | Update.tla focus | Property | Configs | Trace evidence |
|---|---|---|---|---|---|
| US-1 hand-off before ACK | `SelectSync`, `LearnerNewLeader`, `LearnerAckNewLeader` | `AffectedActions` | `AckedHistoryHandedOff` (U1) | Update-seed-focused-U1(U3).cfg, Update-full-U1U3.cfg, Update-seed-oldcontrol-U1.cfg (control) | `NewLeaderAckSent` check in all fresh traces; old-revision trace rejected |
| US-2 ACK vs fsync | `LearnerAckNewLeader`, `AppendOne`, `FsyncOne`, `Crash` | `AffectedActions` + `InteractionActions` | `NewLeaderAckDurable` (U2) | Update-seed-focused-U2.cfg, Update-full-U2.cfg, Update-seed-fixedcontrol.cfg (control) | diff-sync-consistency events 82/84/94; operator violated at replay state 83 |
| US-3 served txn after re-election | US-2 + `LeaderBroadcast`, `Restart`, election/discovery/sync | `FocusedNext` | `CommittedSurvivesLeaderChange` (U3) | Update-seed-focused-U1U3.cfg, Update-seed-full-U1U3.cfg, Update-seed-oldcontrol-U3.cfg, Update-seed-fixedcontrol.cfg | crash inside the window not exercised by the harness (reproduction test covers it) |

Reachability canaries (expected violations = witnesses): `NotUpdateSeed` (16 steps), `NotNewLeaderAckReached`,
`NotDiffHandoffReached`, inherited `NotElectionReached`, `NotMutationReached`, `NotRecoveryReached`,
`NotSyncReached` — all re-run on the final model (`spec/output/incr/canary-*.log`, `hunt-*.log`).

Properties enabled per cfg are listed in each `Update*.cfg`; prior safety properties remain enabled in `MC.cfg`,
`base.cfg`, and `Trace.cfg`. Open/discharge: not applicable — `Update.tla` defines no `EnvUpdate`; every focused
relation is a restriction of `MCNext`.
