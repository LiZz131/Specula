# Review summary

Input: `/work/spec-annotated/` (base.tla, MC.tla, Trace.tla + 16 .cfg). Output: `/work/out/spec-reviewed/`.
Per-block detail: `decisions.md`. Checks: `check.md`.

## Counts

| | count |
|---|---|
| blocks reviewed (in-scope properties, each with exactly one block) | 18 |
| kept unchanged (`review: ok`) | 11 |
| changed | 7 |
| intent changed | 3 (ActiveLeaderUniqueness, OrderedHistories, SnapshotPublishedValid) |
| status changed | 3 (ActiveLeaderUniqueness, AcceptedEpochGECurrentEpoch, SnapshotPublishedValid) |
| evidence lines removed | 9 (3 doc, 3 history, 3 test) |
| evidence lines retyped | 1 (comment → impl) |
| note sentences moved to `concerns.md` | 0 (no note described the model; no `concerns.md` reference existed) |
| definitions / actions / helpers / .cfg changed | 0 |

The other 4 changed blocks (CommittedPrefixAgreement, NormalAckHasDurabilityEvidence, MonotoneUnlessRecovery, OrderedHistories) keep their status. Their changes are evidence retypes, removals and narrowed `->` suffixes; OrderedHistories also has a reworded intent.

## Status matrix (rows: old status, columns: new status)

| old \ new | requirement | mixed | unknown | impl-abstraction | model-internal | total old |
|---|---|---|---|---|---|---|
| requirement | 4 | 1 | 2 | 0 | 0 | 7 |
| mixed | 0 | 2 | 0 | 0 | 0 | 2 |
| model-internal | 0 | 0 | 0 | 0 | 9 | 9 |
| **total new** | 4 | 3 | 2 | 0 | 9 | 18 |

- requirement → requirement: OrderedHistories, CommittedPrefixAgreement, NormalAckHasDurabilityEvidence, ApplyHasCommitCertificate
- requirement → mixed: SnapshotPublishedValid
- requirement → unknown: ActiveLeaderUniqueness, AcceptedEpochGECurrentEpoch
- mixed → mixed: SyncEntryJustified, MonotoneUnlessRecovery
- model-internal → model-internal: TypeOK, MCTypeOK, ElectionUnreachable, SyncUnreachable, CommitUnreachable, ApplyUnreachable, SnapshotUnreachable, RecoveryUnreachable, TraceMatched

## The five blocks I was least sure about

1. **ActiveLeaderUniqueness (requirement → unknown).** This depends on reading "only one active leader at a time" (zookeeperInternals.md:246) as uniqueness of the leader that a quorum follows. The document gives that reason ("since followers only follow a single leader"). It also says at :257-259 and :278 that an old leader may still believe it is active, or that two servers may think they are the leader. A different reviewer could treat :246 as the intended rule and :278 as a tolerated anomaly, and keep `requirement`.
2. **AcceptedEpochGECurrentEpoch (requirement → unknown).** The handshake order in f8f15de5 and the startup check at QuorumPeer.java:1142, which refuses to load when accepted < current, strongly suggest an intended invariant. Still, no non-impl source states the inequality, and deriving it needs the follower's accepted-epoch write time, which is impl-only (Learner.java:509-511). This is a judgment call about what "directly implies" means.
3. **MonotoneUnlessRecovery, clause `durable-shrinks-only-in-sync` (kept requirement).** The cited sources say a log is cut as part of syncing with the leader: TxnLog.java:83 documents truncate as "to get in sync with the leader", and :182-183 and LearnerHandler.java:830 describe discarding at sync. None says a log never shrinks otherwise. I kept `requirement` because the only log-shortening operation is documented with sync as its purpose. A stricter reading would make this clause `unknown`.
4. **SnapshotPublishedValid (requirement → mixed).** I split "covers only applied work when written" (doc-supported) from "is exactly a prefix of the current applied history" (impl-abstraction), because the doc calls snapshots fuzzy and says nothing about later states. Another reviewer might read the snapshot's zxid label as the documented meaning of "prefix" and keep the whole block `requirement`.
5. **OrderedHistories (kept requirement, intent made precise).** The no-gap parts (seen history; committed history as a prefix of the global commit sequence) rest on reading "in order" at :225, :234 and :245 through the same document's FIFO-channel definition (:84-87: a message is delivered only after all messages sent before it). Under a strictly literal reading of "in order", those parts would form a separate `unknown` clause and the block would be `mixed`.
