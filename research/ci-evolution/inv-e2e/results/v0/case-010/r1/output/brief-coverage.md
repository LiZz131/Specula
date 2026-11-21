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

---

## Incremental update coverage (case-010; read from the actual cfg files)

V0 cfg names that no longer resolve (`MCCoreNext`, `CommitHuntNext`, `ActiveLeaderUniqueness`, ...) were removed from the current suite (`MC-complete-candidate.cfg`, `MC-core-diagnostic.cfg`, `MC-recovery-complete.cfg`, `MC-snapshot-complete.cfg`, `base-wide.cfg`); the inherited hunt cfgs were rebased onto MC v3 sentinels. Originals remain in the immutable prior suite.

### Scenarios -> configs

| Scenario | Real trace | Model configs |
|---|---|---|
| V0 1-4 (election/epochs, sync cut, pipeline, recovery) | `election-ordered-v3b`, `restart-catchup-v3b` | `MC.cfg`, `MC-full.cfg`, `MC-wide.cfg`, inherited `MC-*-hunt.cfg` |
| U1 SNAP-window exit (changed) | `snap-abort-rejoin-v3b`, `snap-complete-restart-v3b` | `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg`, `Update-hunt-snap.cfg`, `Update-hunt-snap-steered.cfg`, controls `Update-hunt-snap-oldcontrol.cfg`, `Update-hunt-snap-steered-oldcontrol.cfg`, canaries `Update-canary-snapabort.cfg`, `Update-canary-reload.cfg`, `Update-canary-snapcommit.cfg` |
| U2 TRUNC-window exit (sibling) | none (requires a commit/NEWLEADER race; reproduction is Part 4) | `Update-hunt-trunc.cfg`, `Update-hunt-trunc-steered.cfg`, canary `Update-canary-truncabort.cfg` |
| U3 DIFF exit after NEWLEADER | none | `Update-hunt-diffwindow.cfg`, `Update-hunt-diffwindow-steered.cfg`, canary `Update-canary-diffabort.cfg` |

### Properties -> enabling configs

| Property | Defined | Enabled in |
|---|---|---|
| `LeaderUniquenessPerEpoch`, `AcceptedEpochGECurrentEpoch`, `OrderedHistories`, `CommittedPrefixAgreement`, `NormalAckHasDurabilityEvidence`, `ApplyHasCommitCertificate`, `SyncEntryJustified`, `SnapshotPublishedValid`, `DurableHistoryConsistent`, `LeaderCompleteness`, `MonotoneUnlessRecovery` | `base.tla` | `base.cfg`, `MC.cfg`, `MC-full.cfg`, `MC-wide.cfg`, all `Update-full/focused/open/hunt*` cfgs, `Trace.cfg` (invariants) |
| `ReportedHistoryDurable`, `SnapExitReportsDisk` | `Update.tla` | `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg`, all `Update-hunt*.cfg` |
| `DischargeContext` | `Update.tla` | `Update-discharge.cfg` |
| `TraceMatched` | `Trace.tla` | `Trace.cfg`, `Trace-oldsemantics-control.cfg` |

### Additional configs added during model checking (final)

| Config | Purpose |
|---|---|
| `spec/Update-hunt-snap-only-steered.cfg`, `...-consequence.cfg` | U1 changed branch only (TRUNC excluded) |
| `spec/Update-hunt-snap-steered-oldcontrol*.cfg` | exact-old differential controls (not findings) |
| `spec/Update-hunt-mc1-deterministic.cfg` | MC-1 witness with deterministic leader-side ordering |
| `spec/Update-continue-mc1-consequence.cfg` + `spec/UpdateContinueMC1.tla` | MC-1 consequence from the witness's reachable final state |
| `spec/Update-hunt-trunc-steered2.cfg`, `spec/Update-hunt-diffwindow-steered2.cfg`, `spec/Update-hunt-mc2-leadercompleteness.cfg` | U2 crash variant / U3; MC-2 witness and its LeaderCompleteness variant search |
| `spec/Update-hunt-trunclog-*.cfg` | early crash-free U2 schedule (superseded by the MC-1 configs; simulations stopped before final repairs) |
| `spec/Update-canary-*.cfg` | reachability canaries (steered and unsteered) |
