# Review summary — REQ-EVIDENCE annotations, etcd Raft (Linearizable ReadIndex)

## Counts

| | count |
|---|---|
| Blocks reviewed | **26** (base 9, MC 14, Trace 3) |
| Kept unchanged (`review: ok`) | **20** |
| Changed | **6**: TypeOK, ElectionSafety, LogMatching, CommittedPrefixAgreement, LeaderCompleteness, ReadDeliveryJustified |
| Intent changed | **1**: TypeOK |
| Status changed | **0** |
| Evidence lines removed | 5: four provenance-only commit messages (0b2b904, d747117, 5c55fdf, f1dae53) and one test case that does not assert its claim (`log_test.go:230`) |
| Evidence lines re-pointed | 1: `raft_paper_test.go:198` → `:211` |
| Evidence lines added | 1: `raft_paper_test.go:390 TestLeaderStartReplication` (LogMatching) |
| Evidence lines, before → after | 48 → 44 (non-impl 31 → 27; impl 17 → 17) |
| Note sentences moved to `concerns.md` | 0 (no note described the model) |

### Status matrix (old → new)

| old \ new | requirement | mixed | model-internal | impl-abstraction | unknown | alias pointer |
|---|---|---|---|---|---|---|
| requirement | **6** | 0 | 0 | 0 | 0 | 0 |
| mixed | 0 | **1** | 0 | 0 | 0 | 0 |
| model-internal | 0 | 0 | **11** | 0 | 0 | 0 |
| alias pointer (no status field) | 0 | 0 | 0 | 0 | 0 | **8** |

- requirement: ElectionSafety, CommitWithinLog, LogMatching, CommittedPrefixAgreement, LeaderCompleteness, ReadDeliveryJustified.
- mixed: ReadyNoInvention.
- model-internal: TypeOK, MessagesWellFormed, MCTypeOK, the 5 Hunt canaries and the 3 Trace checks.

No status changed because every `requirement` block still had non-`impl` evidence supporting its intent after the faulty lines were removed or re-pointed.

## Main findings

1. **A test cited for something it does not assert** (CommittedPrefixAgreement). The `TestLogMaybeAppend` case at `log_test.go:230` sets `wpanic: true`, but the test's deferred `recover` only reports panics that were *not* expected. If the committed entry were overwritten without a panic, every other expected value in that row (lasti 1, append true, commit 1, entries `[{1,4}]`) would still match. So the test does not assert that committed entries are protected. By contrast, `TestCommitTo`'s `{4, 0, true}` row *is* effectively asserted, because a non-panicking run cannot leave commit at 0. That line was kept in CommitWithinLog.
2. **A quote supporting the converse of its claim** (ElectionSafety). "win the election when receiving votes from a majority" shows that a majority is sufficient. The block used it for "leadership needs a majority". The same test asserts necessity at line 211 ("stay in candidate if it does not obtain the majority"), so the citation was re-pointed there.
3. **Provenance-only commit messages counted as evidence** (4 blocks). Subjects like "raft: add tests based on section 5.2 in raft paper" say where the tests come from but state no rule. Their `->` suffix named a source, not a part of the intent. The same rule was applied in all four blocks: each line was moved into `note:`.
4. **A missing premise in a derived property** (LogMatching). The cited tests support the AppendEntries consistency check only. The "same index and term ⇒ same entry" half also needs a leader to add entries only at the end of its log, so the verified `TestLeaderStartReplication` line was added.
5. **An intent broader than its formula** (TypeOK). The intent said "every model variable", but three history variables are unconstrained.

## The five blocks I was least sure about

1. **CommitWithinLog, persisted clause.** The only non-`impl` support for `durableCommit <= Len(durableLogs)` is the subject line of 5e1859c, "raft: panic if loaded commit is out of range". I counted it as a rule, because it declares an out-of-range reloaded commit an error, like TestCommitTo's "commit out of range -> panic". A stricter reader could call it narration of its own diff. The clause would then have only `impl` evidence (`raft.go:1195`), and the block would become `mixed`, with that clause `unknown`.
2. **ReadyNoInvention, index-bound clause.** No quote states "read index ≤ log length" outright. The clause is assembled from three pieces: a parameter doc (`read_only.go:49`, read index = commit index at arrival), a field doc (`log.go:32`) and "never decrease commit" (`log.go:188`), which sits directly above the guard it describes. If either comment were read as narration, the clause would be weaker. I kept `mixed`, with index-bound as `requirement`.
3. **CommittedPrefixAgreement.** With the test line removed, the top-level support is the general README sentence "The state machine is kept in sync through the use of a replicated log." I read that as directly implying that committed prefixes agree. It is a statement of purpose, not a precise rule.
4. **LogMatching.** I filled the evidence gap by adding a verified test line rather than splitting the block into clauses. The property is still derived from per-step rules plus ElectionSafety's one-leader-per-term evidence. No source states Log Matching itself.
5. **ReadDeliveryJustified.** The intent's qualifier "with the default safe read-only option" does not appear in the formula. I kept it as a scoping statement that matches the evidence. The forwarded-read half rests on README:29 ("safe read index"), which implies, but does not state, quorum acknowledgements.
