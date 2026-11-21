# Review decisions: one row per REQ-EVIDENCE block

Reviewed: `/work/spec-annotated/` → corrected copy: `/work/out/spec-reviewed/`.
"Evidence lines retyped or removed" lists only changes to the type or presence of `evidence:` lines. Suffix (`->`) rewrites are listed under the reason.

| # | Property (module) | Old status | New status | Intent changed | Evidence lines retyped or removed | Reason (one line) |
|---|---|---|---|---|---|---|
| 1 | TypeOK (base) | model-internal | model-internal | no | none | Type invariant; block is accurate. |
| 2 | ActiveLeaderUniqueness (base) | requirement | **unknown** | yes | removed: doc zookeeperInternals.md:246, :210, :188 | The docs support uniqueness of the leader a quorum follows, but the same document (:212-213, :257-259, :278) says two servers can hold the leader state at the same time. The formula counts that local LEADING/BROADCAST state, so only impl evidence is left. Intent reworded to that state. |
| 3 | AcceptedEpochGECurrentEpoch (base) | requirement | **unknown** | no | removed: history f8f15de5 (×2), test Zab1_0Test.java:615, test Zab1_0Test.java:1126 | The history lines only fix when each epoch is written during the handshake, and the tests assert single values. No non-impl source states or directly implies acceptedEpoch ≥ currentEpoch. |
| 4 | OrderedHistories (base) | requirement | requirement | yes | none | The old intent said only "follow zxid order". The formula checks gap-free prefixes (seen, logged, recovered, global commit) and only increasing order (queued, pending), so the intent now says that. Suffixes of :225, :63, :234, Leader.java:891 and FollowerZooKeeperServer.java:95 restated; :63 gives one common order, not the prefix relation. |
| 5 | CommittedPrefixAgreement (base) | requirement | requirement | no | none | The DIFFSyncConsistencyTest suffix ("servers must not disagree on committed data") is narrowed to what its assertion checks. :63 and :242 still support the intent. |
| 6 | NormalAckHasDurabilityEvidence (base) | requirement | requirement | no | retyped: comment SyncRequestProcessor.java:83 → impl; removed: test DIFFSyncConsistencyTest.java:123 | The field comment only says what the queue holds. The test only waits for an ack and asserts nothing about durability. The TxnLog.java:99 suffix is narrowed, and the note's history-search result is corrected (package moves plus the initial import, not only 67c653cf). zookeeperInternals.md:119 still states the intent directly. |
| 7 | ApplyHasCommitCertificate (base) | requirement | requirement | no | none | Quotes found. Leader.java:902, :117 and :289 support quorum-for-commit, and :118, :235 and Zab1_0Test:655 support "apply at/after commit". Kept. |
| 8 | SyncEntryJustified (base) | mixed | mixed | no | none | Quotes found. Leader and follower clauses are supported by :198, :145, :194, Leader.java:653 and LearnerHandler.java:644. The LOOKING clause is correctly impl-abstraction. Kept. |
| 9 | SnapshotPublishedValid (base) | requirement | **mixed** | yes | none | zookeeperAdmin.md:2603-2604 supports only "when written, the snapshot covers applied work", and the same passage calls snapshots fuzzy. "Exact prefix of the *current* applied history" (what the formula checks) is impl-abstraction. Two clause lines added and both doc suffixes narrowed. |
| 10 | MonotoneUnlessRecovery (base) | mixed | mixed | no | removed: history 27d045af | 27d045af limits truncation inside the exempted sync step, so it supports no part of the intent. Unsupported "only" dropped from the :182, LearnerHandler.java:830 and TxnLog.java:83 suffixes, and the test suffix narrowed to its assertion. The second clause is renamed to the formula's scope ("shrink only in sync"). The exemption clause now says the log cut at sync is documented and the SNAP/committed/applied part is impl. |
| 11 | MCTypeOK (MC) | model-internal | model-internal | no | none | Type invariant of the MC driver; accurate. |
| 12 | ElectionUnreachable (MC) | model-internal | model-internal | no | none | Reachability canary; intent matches `~("FinishElection" \in seen)`. |
| 13 | SyncUnreachable (MC) | model-internal | model-internal | no | none | Reachability canary; intent matches the formula. |
| 14 | CommitUnreachable (MC) | model-internal | model-internal | no | none | Reachability canary; intent matches `~\E t : Quorum(commitWitness[t])`. |
| 15 | ApplyUnreachable (MC) | model-internal | model-internal | no | none | Reachability canary; intent matches the formula. |
| 16 | SnapshotUnreachable (MC) | model-internal | model-internal | no | none | Reachability canary; intent matches the formula. |
| 17 | RecoveryUnreachable (MC) | model-internal | model-internal | no | none | Reachability canary; intent matches the formula. |
| 18 | TraceMatched (Trace) | model-internal | model-internal | no | none | Trace-validation liveness check (`<>(l > Len(TraceLog))`); intent matches. |

## Note check (rule 5)

I read every `note:` line (9 blocks). None describes the model's actions or helpers, compares the model with the code, or calls anything weaker, stronger, a proxy, vacuous or a false alarm. None mentions `concerns.md`. No sentence had to be moved, and `out/concerns.md` records this. The notes I rewrote or extended (ActiveLeaderUniqueness, AcceptedEpochGECurrentEpoch, OrderedHistories, NormalAckHasDurabilityEvidence, MonotoneUnlessRecovery) only describe the evidence search and how the evidence relates to the intent.

## Standard applied to every block

- **Quote check:** the input has 67 evidence lines. Each of the 63 `source/` quotes was opened at its cited line (the script re-check is in `check.md`), and each of the 4 history quotes was checked against `tools/hist.sh show`. The output has 58 evidence lines: 9 removed, 1 retyped. All quotes in the input were found at their cited locations. No block failed on a missing quote.
- **Type check:** a comment counts as `comment` only if it states a rule, contract or reason. A test counts only for what its assertion checks. That rule produced the retype (SRP:83) and the removal (DIFFSync:123) in NormalAckHasDurabilityEvidence.
- **Support check:** a `->` suffix may restate its quote in intent terms. It may not add a restriction the quote does not carry ("only", "never", "prefix"/no-gap). The intent must say what the formula checks, and the kept non-impl lines together must support all of it. Where only part was supported, the block became `mixed` (SnapshotPublishedValid). Where nothing non-impl supported the intent, it became `unknown` (ActiveLeaderUniqueness, AcceptedEpochGECurrentEpoch).
