# Requirement-evidence ledger

Scope: every operator named after `INVARIANT(S)`/`PROPERTY(IES)` in `spec-original/*.cfg`
(no commented-out property lines exist; no `Update.tla` exists). Also included is
`NoIllegalRollback`, which carries the content of the alias
`HistoryPositionsMonotonicExceptRecovery`.

Evidence-type abbreviations: doc, comment, contract, test, history, impl (no `protocol`
evidence was cited, because no protocol paper text exists in `/work`).

| Property | Module | Status | Evidence types | Intent (one line) |
|---|---|---|---|---|
| TypeOK | base.tla | model-internal | — | Every model variable always holds a value of its declared type. |
| MCTypeOK | MC.tla | model-internal | — | MC fault counters stay within bounds; the milestone set holds only known names. |
| ElectionSafety | base.tla | requirement | doc, comment, history, test, impl | At most one server is ever established as leader for any given epoch. |
| OneActiveLeaderPerEpoch | base.tla | requirement | doc, impl | At any moment at most one running server is leading in any given epoch. |
| CommittedHistoriesPrefix | base.tla | requirement | doc, comment, test, impl | For any two servers, one's committed transaction sequence is a prefix of the other's. |
| ApplyRequiresCommitCertificate | base.tla | requirement | comment, doc, contract, test, impl | A server applies only quorum-committed transactions, in its commit order. |
| PipelinePrefix | base.tla | requirement | doc, impl | Transactions are queued/written/fsynced in proposal order; a snapshot never covers more than is applied. |
| EpochHistoryConsistency | base.tla | mixed | history, test, impl | currentEpoch ≤ acceptedEpoch, and no logged transaction has an epoch later than acceptedEpoch. |
| ↳ clause currentEpochAtMostAccepted | | requirement | history, test | currentEpoch never exceeds acceptedEpoch (ZOOKEEPER-2307 message; Zab1_0Test asserts). |
| ↳ clause logEpochAtMostAccepted | | unknown | impl only | No log entry's epoch exceeds acceptedEpoch (only QuorumPeer.loadDataBase check, against currentEpoch). |
| SyncCompletionJustified | base.tla | mixed | doc, history, test, impl | A broadcasting follower has synced with its leader, has a leader, and has currentEpoch = acceptedEpoch. |
| ↳ clause syncedBeforeBroadcast | | requirement | doc, history, test | Broadcast only after synchronization completed. |
| ↳ clause epochsAlignedInBroadcast | | requirement | history, test | currentEpoch set to the new epoch before leaving sync (ZOOKEEPER-1282). |
| ↳ clause leaderKnown | | model-internal | impl only | leaderOf bookkeeping is defined for a broadcasting follower. |
| NoIllegalRollback | base.tla | mixed | doc, contract, test, impl | Durable log, committed and applied prefixes never shrink except at crash or sync installation. |
| ↳ clause durableNoRollback | | requirement | doc, contract, test | The log is truncated only to get in sync with the leader. |
| ↳ clause appliedNoRollback | | requirement | doc | Applied updates are never rolled back (client guarantees). |
| ↳ clause committedNoRollback | | unknown | impl only | A learner's committed-but-unapplied prefix never shrinks. |
| HistoryPositionsMonotonicExceptRecovery | base.tla | alias → NoIllegalRollback | (see NoIllegalRollback) | `[][NoIllegalRollback]_allVars`; one-line pointer block. |
| NotElectionReached | MC.tla | model-internal | — | Canary (expected violated): no election win yet. |
| NotMutationReached | MC.tla | model-internal | — | Canary (expected violated): no transaction applied yet. |
| NotRecoveryReached | MC.tla | model-internal | — | Canary (expected violated): no crash followed by restart yet. |
| NotSyncReached | MC.tla | model-internal | — | Canary (expected violated): no sync mode selected yet. |
| TraceMatched | Trace.tla | model-internal | — | Trace replay eventually consumes every record of the selected trace. |

## Counts

Annotated blocks: 16. That is 15 status-bearing blocks plus 1 alias pointer block. The cfg files
name 15 properties: TypeOK, MCTypeOK, the 7 base safety properties,
HistoryPositionsMonotonicExceptRecovery, 4 canaries and TraceMatched. NoIllegalRollback is the
content-carrying target of the alias.

| Status (block level) | Count | Properties |
|---|---|---|
| requirement | 5 | ElectionSafety, OneActiveLeaderPerEpoch, CommittedHistoriesPrefix, ApplyRequiresCommitCertificate, PipelinePrefix |
| mixed | 3 | EpochHistoryConsistency, SyncCompletionJustified, NoIllegalRollback |
| model-internal | 7 | TypeOK, MCTypeOK, NotElectionReached, NotMutationReached, NotRecoveryReached, NotSyncReached, TraceMatched |
| impl-abstraction | 0 | — |
| unknown | 0 | — |
| alias (pointer only) | 1 | HistoryPositionsMonotonicExceptRecovery → NoIllegalRollback |

Clause-level statuses inside the 3 mixed blocks: requirement 5, unknown 2, model-internal 1.
