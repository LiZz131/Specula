# Review decisions — one row per REQ-EVIDENCE block

Reviewed copy: `out/spec-reviewed/`. Twenty-six blocks were reviewed: 9 in `base.tla`, 14 in `MC.tla` and 3 in `Trace.tla`. In-scope properties are every name after `INVARIANT(S)`/`PROPERTY(IES)` in any `.cfg`. There is no `Update.tla`.

"Evidence lines retyped or removed" lists every evidence line that was removed, re-pointed, retyped or added. Removed lines are not lost: their content is now explained in the block's `note:`.

| # | Property | Module | Old status | New status | Intent changed | Evidence lines retyped / removed | Reason (one line) |
|---|---|---|---|---|---|---|---|
| 1 | TypeOK | base | model-internal | model-internal | **yes** | none | The formula leaves `leaderHistory`, `commitHistory` and `scenarioSeen` unconstrained, so "every model variable" overclaimed. The intent now names the exceptions. |
| 2 | ElectionSafety | base | requirement | requirement | no | **re-pointed** test `raft_paper_test.go:198` → `:211` (same test, TestLeaderElectionInOneRoundRPC); **removed** history `0b2b904 (message)` | Line 198 ("win the election when receiving votes from a majority") shows only that a majority *suffices*. The claimed part, "leadership needs a majority", is asserted by the line-211 cases. The commit message only names paper §5.2 and supports no part of the intent. |
| 3 | CommitWithinLog | base | requirement | requirement | no | none | All quotes are present at the cited lines and correctly typed. The three clauses are covered: applied ≤ commit by `log.go:37`; commit ≤ last index by TestCommitTo (its non-panic path cannot yield commit 0, so the panic is asserted), `log_test.go:189` and `raft.go:432`; persisted commit ≤ persisted log by history 5e1859c. |
| 4 | LogMatching | base | requirement | requirement | no | **removed** history `d747117 (message)`; **added** test `raft_paper_test.go:390 TestLeaderStartReplication` | The commit message is provenance only. The cited tests covered the AppendEntries consistency check, but not the premise that a term never places two different entries at one index. The added test asserts that the leader appends each proposal as a new entry at `lastIndex+1`. |
| 5 | CommittedPrefixAgreement | base | requirement | requirement | no | **removed** test `log_test.go:230 TestLogMaybeAppend` | The test's `recover` handler flags only *unexpected* panics. For this case, the expected lasti/append/commit/entries values also hold if the committed entry is overwritten without a panic, so the test does not assert what it was cited for. README:4, TestLeaderAcknowledgeCommit and `log.go:32` remain. |
| 6 | LeaderCompleteness | base | requirement | requirement | no | **removed** history `5c55fdf (message)` | The commit message only names paper §5.4.1 and states no rule. The four test lines (TestVoter, two current-term-commit tests, TestLeaderAcknowledgeCommit) still support the intent. |
| 7 | MessagesWellFormed | base | model-internal | model-internal | no | none | ok: the formula is a field-domain check on all 11 message fields, and the intent matches. |
| 8 | ReadDeliveryJustified | base | requirement | requirement | no | **removed** history `f1dae53 (message)` | The commit message names the thesis section but states no quorum rule. The contract (`raft.go:167`, `node.go:156`) and doc (README:28-29) lines still support the intent. |
| 9 | ReadyNoInvention | base | mixed | mixed | no | none | ok. The index-bound clause is supported by `read_only.go:49`, `log.go:32`, `log.go:188` and the TestReadOnlyOptionSafe assertion. The ctx-domain clause is a pure domain check (also implied by TypeOK), so `model-internal` is right. |
| 10 | MCTypeOK | MC | model-internal | model-internal | no | none | ok: the intent matches (TypeOK plus 8 bounded counters). |
| 11 | MCElectionSafety | MC | alias → ElectionSafety | alias (unchanged) | no | none | ok: a one-line pointer to the correct definition. |
| 12 | MCCommitWithinLog | MC | alias → CommitWithinLog | alias (unchanged) | no | none | ok: pointer is correct. |
| 13 | MCLogMatching | MC | alias → LogMatching | alias (unchanged) | no | none | ok: pointer is correct. |
| 14 | MCCommittedPrefixAgreement | MC | alias → CommittedPrefixAgreement | alias (unchanged) | no | none | ok: pointer is correct. |
| 15 | MCLeaderCompleteness | MC | alias → LeaderCompleteness | alias (unchanged) | no | none | ok: pointer is correct. |
| 16 | MCMessagesWellFormed | MC | alias → MessagesWellFormed | alias (unchanged) | no | none | ok: pointer is correct. |
| 17 | MCReadDeliveryJustified | MC | alias → ReadDeliveryJustified | alias (unchanged) | no | none | ok: pointer is correct. |
| 18 | MCReadyNoInvention | MC | alias → ReadyNoInvention | alias (unchanged) | no | none | ok: pointer is correct. |
| 19 | HuntLeader | MC | model-internal | model-internal | no | none | ok: a reachability canary. `scenarioSeen.leader` is set only by BecomeLeader. |
| 20 | HuntCommit | MC | model-internal | model-internal | no | none | ok: a canary. `scenarioSeen.commit` is set only when a leader's HandleAppendResponse raises commit. |
| 21 | HuntQuorumCheck | MC | model-internal | model-internal | no | none | ok: a canary. Set only by CheckQuorum, which requires the Leader role. |
| 22 | HuntReadyRead | MC | model-internal | model-internal | no | none | ok: a canary. Set by ReadyPublish when produced reads are non-empty. |
| 23 | HuntReadResponse | MC | model-internal | model-internal | no | none | ok: a canary. Set only by HandleReadIndexResponse. |
| 24 | TraceCanProgress | Trace | model-internal | model-internal | no | none | ok: a trace-replay check. The intent matches `traceLine <= Len => ENABLED TraceNext`. |
| 25 | TraceMatched | Trace | model-internal | model-internal | no | none | ok: the intent matches `<>(traceLine = Len(TraceLog)+1)`. |
| 26 | TraceTypeOK | Trace | model-internal | model-internal | no | none | ok: the intent matches (TypeOK plus cursor bounds). |

## Checks applied uniformly to every block

1. **Quote:** every cited `source/` line was opened and its quote found on that line. That is all 43 in the annotated copy and all 43 in the reviewed copy, including the added one. The 5 commit-message lines (`<commit> (message)`) in the annotated copy were read with `tools/hist.sh show`.
2. **Type:** every `comment`/`contract` line was checked for a stated rule, contract or definition, not narration. Every `test` line was checked against the test's actual assertions. This check removed `log_test.go:230` and re-pointed `raft_paper_test.go:198`.
3. **Support:** the part of the intent each non-`impl` line supports was written down. Four commit messages supported no part: each only names the paper or thesis section the work follows. They were applied the same way in all four blocks (ElectionSafety, LogMatching, LeaderCompleteness, ReadDeliveryJustified) and moved to `note:`.
4. **Derived properties** (ElectionSafety, LogMatching, LeaderCompleteness): a block keeps `requirement` only if its non-`impl` evidence covers each premise the protocol argument needs. LogMatching lacked one premise, so a verified test line was added.
5. **Intent vs formula:** every formula was re-read. Only TypeOK's intent claimed more than its formula checks.
6. **Notes:** each of the 7 `note:` lines was read sentence by sentence. None describes the model, so nothing was moved (see `concerns.md`).
