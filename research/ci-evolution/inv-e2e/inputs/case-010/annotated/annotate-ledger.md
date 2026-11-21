# Requirement-evidence ledger

Model: `spec-original/` (ZooKeeper Zab follower synchronization and shutdown), annotated copy in `out/spec-annotated/`.
Source revision: `ea3042d5` (`base`, 2020-11-23). There is no `Update.tla`.

In scope: every name after `INVARIANT(S)` / `PROPERT(Y|IES)` in the 16 `.cfg` files. No commented-out `INVARIANT`/`PROPERTY` lines exist. 18 names in total. None of them is a pure alias (`A == B`): the canaries are negations (`~ReachedX`) and `MonotoneUnlessRecovery == [][MonotoneStep]_vars` is a temporal wrapper, so each name got its own block. The step predicate `MonotoneStep` is covered by the `MonotoneUnlessRecovery` block.

Evidence-type abbreviations: doc, comment, contract, test, history, impl (`protocol` was not used, because no Zab paper or protocol spec exists under `/work`).

| Property | Module | Status | Evidence types | Intent (one line) |
|---|---|---|---|---|
| TypeOK | base.tla | model-internal | — | Every base-model variable stays inside its declared domain. |
| ActiveLeaderUniqueness | base.tla | requirement | doc, impl | At any time at most one running server is an activated leader (LEADING and in the broadcast phase). |
| AcceptedEpochGECurrentEpoch | base.tla | requirement | history, test, impl | A server's current epoch never exceeds its accepted epoch. |
| OrderedHistories | base.tla | requirement | doc, comment, contract, impl | All per-server histories and the global commit sequence follow zxid order; committed ⊑ global commit order; applied ⊑ committed. |
| CommittedPrefixAgreement | base.tla | requirement | doc, test, history, impl | Of any two servers, one's committed history is a prefix of the other's. |
| NormalAckHasDurabilityEvidence | base.tla | requirement | doc, comment, contract, test, impl | The leader counts a server's proposal ack only if that server has flushed the proposal to its log. |
| ApplyHasCommitCertificate | base.tla | requirement | comment, doc, test, impl | A server applies a transaction only after it was committed on a quorum of acks. |
| SyncEntryJustified | base.tla | mixed | doc, comment, impl | A running server is in broadcast only as a leader with a NEWLEADER quorum or as a follower that finished sync. |
| SnapshotPublishedValid | base.tla | requirement | doc, impl | A server's last published snapshot covers only transactions it had already applied (a prefix of its applied history). |
| MonotoneUnlessRecovery | base.tla | mixed | doc, comment, contract, history, test, impl | Except in a step that completes a learner sync, no server's logged, committed or applied history gets shorter. |
| MCTypeOK | MC.tla | model-internal | — | TypeOK plus well-typed MC counters and coverage set. |
| ElectionUnreachable | MC.tla | model-internal | — | Canary (expected to be violated): FinishElection is never recorded. |
| SyncUnreachable | MC.tla | model-internal | — | Canary: CompleteLearnerSync is never recorded. |
| CommitUnreachable | MC.tla | model-internal | — | Canary: no transaction gets a quorum commit witness. |
| ApplyUnreachable | MC.tla | model-internal | — | Canary: no server applies a transaction. |
| SnapshotUnreachable | MC.tla | model-internal | — | Canary: FinishSnapshot is never recorded. |
| RecoveryUnreachable | MC.tla | model-internal | — | Canary: RestartLoadDatabase is never recorded. |
| TraceMatched | Trace.tla | model-internal | — | Trace validation: the replay eventually consumes every logged event. |

## Clauses of the `mixed` properties

| Property | Clause | Status | Main evidence |
|---|---|---|---|
| SyncEntryJustified | leader-in-broadcast | requirement | zookeeperInternals.md:198, :145; Leader.java:653-655 comment |
| SyncEntryJustified | follower-in-broadcast | requirement | zookeeperInternals.md:194; LearnerHandler.java:643-645 comment |
| SyncEntryJustified | no-other-role-in-broadcast | impl-abstraction | QuorumPeer.java:855-857 only; ZabState is "(Used for monitoring)" (QuorumPeer.java:487, cc900a3b) |
| MonotoneUnlessRecovery | durable-shrinks-only-in-sync | requirement | zookeeperInternals.md:176-183; LearnerHandler.java:830-831; TxnLog.java:82-84; 27d045af message |
| MonotoneUnlessRecovery | committed-and-applied-never-shrink | requirement | zookeeperInternals.md:180-182; DIFFSyncConsistencyTest.java:213 |
| MonotoneUnlessRecovery | sync-step-exemption | impl-abstraction | Learner.java:565-597; ZKDatabase.java:599-622 |

## Counts by status (18 properties)

| Status | Count | Properties |
|---|---|---|
| requirement | 7 | ActiveLeaderUniqueness, AcceptedEpochGECurrentEpoch, OrderedHistories, CommittedPrefixAgreement, NormalAckHasDurabilityEvidence, ApplyHasCommitCertificate, SnapshotPublishedValid |
| mixed | 2 | SyncEntryJustified, MonotoneUnlessRecovery |
| impl-abstraction | 0 | — (two clauses of the mixed properties are impl-abstraction) |
| unknown | 0 | — |
| model-internal | 9 | TypeOK, MCTypeOK, ElectionUnreachable, SyncUnreachable, CommitUnreachable, ApplyUnreachable, SnapshotUnreachable, RecoveryUnreachable, TraceMatched |

## Where I was least sure

- **AcceptedEpochGECurrentEpoch**: nothing outside the code states the inequality. The `requirement` status rests on two history messages (f8f15de5) that fix the order of the two epoch writes, and on tests that check concrete epoch values. The direct check (QuorumPeer.java:1142) is impl only.
- **ActiveLeaderUniqueness**: zookeeperInternals.md:246 supports it, but :257-259 and :278 of the same document say an old leader can still believe it is active. See `concerns.md`.
- **SnapshotPublishedValid**: the only non-impl source describes snapshot file naming and fuzziness (zookeeperAdmin.md:2598-2611). It supports the snapshot's label and contents being already-applied work, not an exact image. A scratch TLC run also found a reachable violation (`concerns.md` C1).
