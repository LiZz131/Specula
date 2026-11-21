# Review decisions: one row per REQ-EVIDENCE block

Blocks reviewed: 16. That is the 15 names listed after `INVARIANT(S)`/`PROPERTY`/`PROPERTIES` in the `.cfg` files, plus `NoIllegalRollback`, which carries the content of the alias `HistoryPositionsMonotonicExceptRecovery`. There is no `Update.tla`.
Line numbers refer to `out/spec-reviewed/`.

"Arrows narrowed" means the `-> <part supported>` text was cut back to what the quote literally says. The quote, location and type were left unchanged. No evidence line was retyped.

| # | Property (block location) | Old status | New status | Intent changed | Evidence lines retyped / removed | Reason (one line) |
|---|---|---|---|---|---|---|
| 1 | TypeOK (base.tla:518) | model-internal | model-internal | no | none | A type invariant of the model, so the block is correct as written. |
| 2 | ElectionSafety (base.tla:550) | requirement | requirement | yes | none (3 arrows narrowed: :195, 1a556bd1, Zab1_0Test:213) | The intent said "established as leader", but `leadersByEpoch` records every election winner of an epoch, so it now says "takes leadership". zookeeperInternals.md:130 ("only one leader uses a given epoch") still supports it directly. |
| 3 | OneActiveLeaderPerEpoch (base.tla:566) | requirement | requirement | no | none | All quotes are present and correctly typed. zookeeperInternals.md:130 supports the per-epoch intent, and the :246 per-epoch reading is explained in the note. |
| 4 | CommittedHistoriesPrefix (base.tla:583) | requirement | requirement | no | removed: `test FollowerResyncConcurrencyTest.java:608` (1 arrow narrowed: :59) | The removed test only asserts equal per-session ephemeral counts. Total order (:63) and in-order COMMIT processing (:234, Leader.java:891) still support the prefix intent. |
| 5 | ApplyRequiresCommitCertificate (base.tla:599) | requirement | requirement | no | removed: `contract FollowerZooKeeperServer.java:95` (1 arrow narrowed: Zab1_0Test:655) | The removed contract says a COMMIT must match the head of `pendingTxns`, which is about commit order and not about what is applied. Leader.java:902, :117, :235 and CommitProcessor.java:70 still cover both conjuncts. |
| 6 | PipelinePrefix (base.tla:617) | requirement | **mixed** | yes | none (1 arrow narrowed: :226) | The separate queued and written-but-unsynced stages are backed only by `impl`: the :226 arrow had stretched "followers process messages in order" to "every stage". New clauses: durableInProposalOrder = requirement, intermediateStages = impl-abstraction, snapshotWithinApplied = requirement. |
| 7 | EpochHistoryConsistency (base.tla:641) | mixed | mixed | yes | none | The intent said "no logged transaction" has a later epoch, but the formula bounds only `LastEpoch(durable[s])`, so the intent was narrowed to "the last fsynced log entry". Both clause statuses were checked and kept (my history search of both file paths also found only 776db780). |
| 8 | SyncCompletionJustified (base.tla:660) | mixed | mixed | no | none (1 arrow narrowed: :194) | The :194 doc line orders syncing before the NEW_LEADER ACK, not "leaving synchronization", so the arrow was corrected. The 148c2cd6/f8f15de5 messages and the test assertions check out, so the clauses were kept. |
| 9 | NoIllegalRollback (base.tla:685) | mixed | mixed | no | none (3 arrows narrowed: :183, :119, zookeeperProgrammers.md:1177) | The :183 arrow added an "only" that the doc does not say. :119 defines ACK as persistent recording, and :1177 is about updates a client has seen. The clause statuses survive. |
| 10 | HistoryPositionsMonotonicExceptRecovery (base.tla:709) | alias → NoIllegalRollback | alias → NoIllegalRollback | no | none | `== [][NoIllegalRollback]_allVars`, so the one-line pointer block is correct. |
| 11 | MCTypeOK (MC.tla:89) | model-internal | model-internal | no | none | Bounds on harness counters and milestone names, i.e. observer bookkeeping. |
| 12 | NotElectionReached (MC.tla:103) | model-internal | model-internal | no | none | A canary. The intent matches `"leader" \notin seen` (`Mark("leader")` in MCWinElection). |
| 13 | NotMutationReached (MC.tla:110) | model-internal | model-internal | no | none | A canary. The intent correctly says "apply" (`Mark("apply")` in MCApplyOne), not "mutation". |
| 14 | NotRecoveryReached (MC.tla:117) | model-internal | model-internal | no | none | A canary. The intent matches `~({"crash","restart"} \subseteq seen)`. |
| 15 | NotSyncReached (MC.tla:124) | model-internal | model-internal | no | none | A canary. The intent matches `"sync" \notin seen` (added by MCSelectSync). |
| 16 | TraceMatched (Trace.tla:376) | model-internal | model-internal | no | none | Trace-acceptance check of the model. I repeated the note's search claim (no `SyncSelected`/`TxnDurable`/`BroadcastReady`/`ndjson` in source/) and got no matches. |

## Support check worksheet (non-`impl` lines kept, and what each literally supports)

- **ElectionSafety**
  - :130 supports the whole intent (one leader per epoch).
  - :195, Learner.java:513, 1a556bd1 and Zab1_0Test:213 support only the mechanism (a follower acks one epoch once; the proposed epoch must exceed the accepted epoch). The note already says so.
- **OneActiveLeaderPerEpoch**
  - :130 supports the whole intent.
  - :246 supports at most one active leader at a time. The note explains the per-epoch reading.
  - :211 supports that no second leader is established while one holds a quorum.
- **CommittedHistoriesPrefix**
  - :63 supports the same delivery order on all servers.
  - :59 supports that every server eventually delivers what one delivered.
  - :234 and Leader.java:891 support in-order commit.
- **ApplyRequiresCommitCertificate**
  - Leader.java:902 and :117 support "committed means quorum-accepted" (the certificate conjunct).
  - :235 supports delivery when committed.
  - CommitProcessor.java:70 supports applying writes in zxid order (the prefix conjunct).
  - Zab1_0Test:655/656 supports no apply before COMMIT, in one scenario.
- **PipelinePrefix**
  - :229 and :245 support that the fsynced log follows proposal order.
  - :226 supports in-order processing on a follower.
  - zookeeperAdmin.md:2593 supports that the snapshot is named by an already-committed transaction (it does not reach beyond applied).
  - Nothing supports the queued/written intermediate stages.
- **EpochHistoryConsistency**
  - 19d85670 supports that a persisted accepted epoch below the current epoch is a fault.
  - Zab1_0Test:614-615 and :748-749 assert accepted=1, current=0 after ACKEPOCH.
  - The last-entry clause has `impl` evidence only (QuorumPeer.java:1122).
- **SyncCompletionJustified**
  - :194 supports synced before the NEW_LEADER ACK.
  - 148c2cd6 supports NEWLEADER after the sync payload.
  - f8f15de5 supports that current epoch is set at NEWLEADER, before the ACK.
  - QuorumPeerMainTest:1179 (assertion at 1182-1184) supports that the restarted follower serves the leader's value.
  - Zab1_0Test:637 and :780 support current = accepted = 1 after the NEWLEADER ACK.
  - leaderKnown has `impl` evidence only and is kept as model-internal.
- **NoIllegalRollback**
  - :119 supports that ACKed proposals are persistent.
  - :183, TxnLog.java:83 and TruncateTest:225 (assertion at 226-229) support the sync-time discard/truncation exception.
  - zookeeperOver.md:168 and zookeeperProgrammers.md:1177 support no backwards view and no rollback of seen updates, at service level (the note says so).
  - committedNoRollback has `impl` evidence only and stays unknown.
