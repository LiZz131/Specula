# Requirement-evidence ledger

There is one row per annotated property: every operator named after `INVARIANT(S)`/`PROPERT(Y|IES)` in a
`.cfg` under `spec-original/`. No commented-out property lines were found, and there is no `Update.tla`.
Aliases point to the definition that carries the content.

| # | Property | Module | Status | Evidence types | Intent (one line) |
|---|---|---|---|---|---|
| 1 | ElectionSafety | base.tla | requirement | test ×2, history, doc, impl ×2 | In any one term, at most one server becomes leader. |
| 2 | CommitWithinLog | base.tla | requirement | comment ×2, test ×2, history, impl ×3 | applied ≤ commit ≤ last log index on every server, and persisted commit ≤ persisted log length. |
| 3 | LogMatching | base.tla | requirement | test ×3, history, impl ×2 | Logs that agree on the term at an index are identical up to that index. |
| 4 | CommittedPrefixAgreement | base.tla | requirement | doc, test ×2, comment, impl ×2 | Any two servers agree on all entries up to the smaller of their commit indexes. |
| 5 | LeaderCompleteness | base.tla | requirement | test ×4, history, impl ×2 | An entry committed in a term is in the log of every leader of a later term, at the same index. |
| 6 | ReadDeliveryJustified | base.tla | requirement | contract ×2, doc ×2, history, impl ×4 | With ReadOnlySafe, every delivered read state (local or forwarded) is backed by acks from a quorum. |
| 7 | ReadyNoInvention | base.tla | mixed (index-bound: requirement; ctx-domain: model-internal) | comment ×3, test, impl ×2 | A delivered read state's index ≤ the serving leader's log length, and its context fields are request contexts. |
| 8 | TypeOK | base.tla | model-internal | — | Every variable stays in its declared type/bounded domain. |
| 9 | MessagesWellFormed | base.tla | model-internal | — | Every in-flight message has fields in the model's bounded domains. |
| 10 | MCTypeOK | MC.tla | model-internal | — | TypeOK plus fault/budget counters within their limits. |
| 11 | MCElectionSafety | MC.tla | alias → ElectionSafety (requirement) | — | see #1 |
| 12 | MCCommitWithinLog | MC.tla | alias → CommitWithinLog (requirement) | — | see #2 |
| 13 | MCLogMatching | MC.tla | alias → LogMatching (requirement) | — | see #3 |
| 14 | MCCommittedPrefixAgreement | MC.tla | alias → CommittedPrefixAgreement (requirement) | — | see #4 |
| 15 | MCLeaderCompleteness | MC.tla | alias → LeaderCompleteness (requirement) | — | see #5 |
| 16 | MCMessagesWellFormed | MC.tla | alias → MessagesWellFormed (model-internal) | — | see #9 |
| 17 | MCReadDeliveryJustified | MC.tla | alias → ReadDeliveryJustified (requirement) | — | see #6 |
| 18 | MCReadyNoInvention | MC.tla | alias → ReadyNoInvention (mixed) | — | see #7 |
| 19 | HuntLeader | MC.tla | model-internal | — | Canary: no leader yet (expected violation = election reachable). |
| 20 | HuntCommit | MC.tla | model-internal | — | Canary: no commit advance yet (expected violation = commit reachable). |
| 21 | HuntQuorumCheck | MC.tla | model-internal | — | Canary: no quorum check yet (expected violation = CheckQuorum reachable). |
| 22 | HuntReadyRead | MC.tla | model-internal | — | Canary: no read state published yet (expected violation = read delivery reachable). |
| 23 | HuntReadResponse | MC.tla | model-internal | — | Canary: no read-index response received yet (expected violation = forwarded read reachable). |
| 24 | TraceCanProgress | Trace.tla | model-internal | — | While trace records remain, the next one can be replayed. |
| 25 | TraceMatched | Trace.tla | model-internal | — | Replay eventually consumes the whole trace. |
| 26 | TraceTypeOK | Trace.tla | model-internal | — | TypeOK plus the trace cursor within bounds. |

## Counts by status

The 26 annotated properties are 18 content definitions plus 8 aliases.

| Status | Content definitions | Including aliases (resolved) |
|---|---|---|
| requirement | 6 | 12 |
| mixed | 1 | 2 |
| model-internal | 11 | 12 |
| impl-abstraction | 0 | 0 |
| unknown | 0 | 0 |
| **total** | **18** | **26** |

Notes:
* Evidence counts are the number of `evidence:` lines per block.
* No `protocol` lines were recorded. The Raft paper and thesis are cited in the source, but their text is
  not in `/work`, so no exact quote was available (see the `note:` lines and concerns E3).
