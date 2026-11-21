# Review summary

## Counts

| | n |
|---|---|
| Blocks reviewed | 16 (15 cfg properties + `NoIllegalRollback`, the content of the alias `HistoryPositionsMonotonicExceptRecovery`) |
| Kept unchanged (`review: ok`) | 9 |
| Changed | 7 (ElectionSafety, CommittedHistoriesPrefix, ApplyRequiresCommitCertificate, PipelinePrefix, EpochHistoryConsistency, SyncCompletionJustified, NoIllegalRollback) |
| Intent changed | 3 (ElectionSafety, PipelinePrefix, EpochHistoryConsistency) |
| Status changed | 1 (PipelinePrefix: requirement → mixed) |
| Evidence lines removed | 2 (test FollowerResyncConcurrencyTest.java:608; contract FollowerZooKeeperServer.java:95) |
| Evidence lines retyped | 0 |
| Evidence arrows narrowed (quote, type and location unchanged) | 10 |
| Clause lines added | 3 (PipelinePrefix); no existing clause status changed |
| `note:` sentences moved to concerns.md | 0 (none described the model) |
| Quotes checked against source | 50 before review, 48 after; all appear verbatim on the cited line |

## Status matrix (old → new)

| old \ new | requirement | mixed | model-internal | alias pointer |
|---|---|---|---|---|
| requirement (5) | 4 | 1 | 0 | 0 |
| mixed (3) | 0 | 3 | 0 | 0 |
| model-internal (7) | 0 | 0 | 7 | 0 |
| alias pointer (1) | 0 | 0 | 0 | 1 |

New totals: requirement 4, mixed 4, model-internal 7, alias 1.

## The five blocks I was least sure about

1. **PipelinePrefix (requirement → mixed).** I read "Followers process messages in the order they are received" (zookeeperInternals.md:226) and "see and record proposals in order" (:245) as covering the recorded, fsynced log. I did not read them as covering the separate queue and written-but-unsynced stages, which are named only in SyncRequestProcessor. A more generous reader could keep the whole block as `requirement`.
2. **NoIllegalRollback, clause appliedNoRollback (kept requirement).** The support is a set of client/service-level guarantees: Single System Image and Reliability (zookeeperOver.md:166-171, zookeeperProgrammers.md:1176-1178). The per-server, "except crash/sync" form follows from them by implication, and the note already flags this. It could arguably be `unknown`.
3. **EpochHistoryConsistency, clause currentEpochAtMostAccepted (kept requirement).** This rests on a JIRA title and its fix (19d85670: "not starting because acceptedEpoch is less than the currentEpoch") plus two single-scenario test assertions. No doc or comment states the rule outright.
4. **ElectionSafety (intent reworded).** I changed "established as leader" to "takes leadership" because `leadersByEpoch` is filled when a server wins the election, before activation. Whether "established" was materially wrong, rather than just loose, is a judgement call.
5. **SyncCompletionJustified, clause leaderKnown (kept model-internal).** "A broadcasting follower has a leader" is backed only by `impl` (Follower.java:107). I accepted it as well-formedness of the `leaderOf`/`Nil` bookkeeping, but it could be classed as `impl-abstraction`.
