# Modeling-brief coverage

This matrix maps each V0 obligation to its specification element and evidence location. Final run counts and outcomes are recorded in `spec/output/verification-summary.md`; all checks are bounded evidence, not proof.

| Brief obligation | Base-spec encoding | Implementation trace scenario | Model-checking evidence |
|---|---|---|---|
| Vote ordering and one quorum-elected leader | `BeginElectionRound`, `CastVote`, `FinishElection`; `ActiveLeaderUniqueness` | both traces record every peer's successful `FinishElection` | `MC-election-hunt.cfg`; ordinary `MC.cfg` |
| Accepted/current epoch separation and durable update order | `PersistAcceptedEpoch`, `PersistCurrentEpoch`, `RecordEpochAck`, `FormEpochQuorum`; `AcceptedEpochGECurrentEpoch` | both startup paths and the restart path | `MC.cfg`; epoch-quorum reachability reported from exploration |
| DISCOVERY → SYNCHRONIZATION → BROADCAST gate | explicit `phase`, `newLeaderReady`, `syncComplete`; `SyncEntryJustified` | both startup paths; repeated after full restart and follower rejoin | `MC-sync-hunt.cfg`; ordinary `MC.cfg` |
| DIFF/TRUNC/SNAP selection and synchronization cut | `ChooseSyncMode`, `CompleteLearnerSync` with separate `durable`, `committed`, and `applied` histories | normal startup sync plus the missed-mutation follower catch-up | all three modes branch in `MCNext`; `MC-sync-hunt.cfg` |
| Proposal → pending → sync queue → durable ACK → quorum commit | pipeline actions and `acks`, `durabilityEvidence`, `commitWitness`; `NormalAckHasDurabilityEvidence` | ordered two-mutation trace and both mutations around recovery/catch-up | `MC-commit-hunt.cfg`; ordinary `MC.cfg` |
| Apply only after a certified global commit | `ApplyTxn`; `ApplyHasCommitCertificate`, `CommittedPrefixAgreement` | both traces include client read-after-write assertions and `ApplyTxn` observations | ordinary `MC.cfg`; commit hunt reaches the precondition |
| Ordered committed/applied prefixes | dense zxid order, `OrderedHistories`, `CommittedPrefixAgreement` | two ordered mutations; recovery scenario preserves and catches up the prefix | completed ordinary `MC.cfg` uses `MaxTxn=1`; wider `MC-wide.cfg` retains the two-transaction bound |
| Recovery distinguishes durable, recovery-visible, committed, applied | `Crash`, `RestartLoadDatabase`, `recoveryVisible`; recovery exception in `MonotoneUnlessRecovery` | full ensemble restart plus follower restart after a missed mutation | `MC-recovery-hunt.cfg`; one-crash bound in `MC.cfg` |
| Fuzzy snapshot begin/publish boundary | `snapshotImage`, `BeginSnapshot`, `FinishSnapshot`; `SnapshotPublishedValid` | startup/recovery can emit real snapshots if triggered by the exact-old server | one bounded snapshot branch in `MC.cfg`; reachability counter retained |

## Deliberate exclusions

The V0 suite does not model observers, dynamic reconfiguration/joint quorums, session semantics, ACLs, watches, multi-op rollback, transport byte framing, learner throttling, digest mismatch repair, or disk corruption. It fixes a three-participant majority ensemble. The completed ordinary configuration has one transaction; `MC-wide.cfg` and the real traces retain two. `MaxEpoch`, `MaxTxn`, two election rounds, one crash, and one snapshot are state-space limits; green results under them are `LIMITED_COVERAGE`.

## Incremental coverage (case-010)

| Brief item (modeling-brief §8) | Spec encoding | Trace evidence | Model-checking cfg(s) |
|---|---|---|---|
| U1 unfinished SNAP sync (update target) | `LeaderDecideSync`/`ReceiveSyncMode(SNAP)`, `SyncApplyCommitted`, `LearnerExit`/`LearnerShutdown` (`LearnerFully`), `ReloadDatabase` | `diff-sync-after-snap-new` (fully=true, cleared, reload), `snap-complete-new`, old control `diff-sync-after-snap-oldcontrol` | `Update-snapfix-new.cfg`, `Update-snapfix-old.cfg`, `Update-e2e-snap-{new,old}.cfg`, `Update-canary-SnapAbort/SnapClear.cfg` |
| U2 unfinished TRUNC sync (sibling) | `ReceiveSyncMode(TRUNC)` with `syncPlan.z`/`cut`, `SyncApplyCommitted` | `repro-trunc-abort-{new,old}` | `Update-focused-txn1.cfg`, `Update-e2e-trunc-new.cfg`, `Update-canary-TruncAbort.cfg` |
| U3 serving learner sync processor not stopped | `LearnerShutdownEffects` (`LearnerDrains`), `leakedQueued`, `LeakedFlush` | `syncAlive` on every serving LearnerShutdown (new: true, old: false); LeakedFlush itself not observed | `Update-leak-new.cfg`, `Update-leak-old.cfg`, `Update-focused.cfg`, `Update-canary-Leak.cfg` |
| Rejoin consumer of reused/reloaded DB | `JoinEstablishedLeader`, DIFF after exit | `diff-sync-after-snap-new`, repro traces | `Update-canary-Rejoin.cfg` |
| `UpdIdleDbBackedByDisk` | `spec/UpdateProps.tla` | evaluated on every replayed state (`TraceUpdate`) | enabled in `Update-full.cfg`, `Update-focused*.cfg`, `Update-snapfix-*.cfg`, `Update-leak-*.cfg`, `Update-open.cfg` |
| `UpdDurableCoversCommitted` | `spec/UpdateProps.tla` | as above | as above + `Update-e2e-*.cfg` |
| Open/discharge | `Update!EnvUpdate`, `DischargeContext` | — | `Update-open.cfg`, `Update-discharge.cfg` |

Unchanged V0 rows above still apply; the inherited hunt cfgs were rebased (CodeVersion, MaxLearnerExits) and rerun.
