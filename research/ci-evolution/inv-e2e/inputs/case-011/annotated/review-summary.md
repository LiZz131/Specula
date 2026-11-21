# Review summary

## Counts

| Item | Count |
|---|---|
| Blocks reviewed | 13 (all in-scope properties: 12 cfg invariants + `TraceConsumed`; no `Update.tla`, no commented-out cfg properties) |
| Kept unchanged (`review: ok`) | 6 — VoteRequestAfterDurable, GrantedResponseAfterDurable, NoForgedMessageEndpoints, MCTypeOK, TraceConsumed, TraceTypeOK |
| Changed | 7 |
| Intent changed | 3 — TypeOK, DurableVoteNotAhead, DurableLogNotAhead |
| Status changed | 1 — DurableVoteNotAhead |
| Evidence lines retyped comment → impl | 2 — `vote_handler/mod.rs:163`, `change_handler.rs:50` |
| Evidence lines removed | 1 — `raft_log_storage.rs:98` (DurableLogNotAhead) |
| Evidence lines added | 3 — `log_pointers.md:27`, `:24`, `:19` (DurableLogNotAhead) |
| Arrows narrowed (no type change) | 7 lines in 3 blocks: DurableVoteNotAhead ×3, DurableLogNotAhead ×3, CandidateRoleHasPendingSelfVote ×1 |
| Note sentences moved to concerns.md | 1 (MembershipAtMostOneOutstanding) |

## Status matrix (old → new)

| old \ new | requirement | impl-abstraction | model-internal | mixed | unknown | total old |
|---|---|---|---|---|---|---|
| requirement | 5 | 1 | 0 | 0 | 0 | 6 |
| impl-abstraction | 0 | 1 | 0 | 0 | 0 | 1 |
| model-internal | 0 | 0 | 5 | 0 | 0 | 5 |
| mixed | 0 | 0 | 0 | 1 | 0 | 1 |
| unknown | 0 | 0 | 0 | 0 | 0 | 0 |
| **total new** | 5 | 2 | 5 | 1 | 0 | 13 |

## The five blocks I was least sure about

1. **DurableVoteNotAhead** (requirement → impl-abstraction). The formula compares the stored vote with the in-memory vote. The documented invariant orders only the I/O cursors, and `engine_impl.rs:153-162` / f4b5f61d let the two votes diverge when leader restore is disabled. The other reading is that the model's `vote` stands for the "accepted vote I/O". Under that reading the annotator's I/O-cursor intent and `requirement` hold. I chose to keep the intent faithful to the formula's variable rather than to the evidence's vocabulary. I also considered `mixed`, but the formula is a single comparison with no clauses to split, so I used `impl-abstraction`.
2. **VoteRequestAfterDurable** (kept impl-abstraction). Only queue order plus an awaited `save_vote` puts the requests after persistence, and `SendVote` has no wait condition. `unknown` would also be defensible. The 36d2c115 and 88754e09 messages tipped it toward "this is how the code happens to work".
3. **CertifiedLeaderHasFrozenQuorum** (kept mixed). The clause split is conceptual rather than syntactic (one `IsQuorum` atom). Recording raft-essentials.md:103 as "not counted" is a judgement call: one could argue it pulls against the frozen-config clause.
4. **LeaderRoleHasCommittedSelfVote** (kept requirement, one line retyped). I applied one test for comment versus impl: does the comment add a meaning, rule or reason beyond restating the adjacent code? Under that test `vote_handler/mod.rs:163` and `change_handler.rs:50` became impl. `candidate.rs:113`, `raft_state/mod.rs:446` and `:459` stayed comment because each adds "granted by a quorum". Another reviewer could draw this line differently.
5. **MembershipAtMostOneOutstanding** (kept requirement, note sentence moved). The moved sentence ("not log indexes … read here as a count") is borderline between "how the evidence relates to the intent" and "how the model's index variables should be read". I treated it as the latter. The intent's "one config beyond the committed one" relies on the index variables counting configs, which is how the `base`/`MC` actions use them.
