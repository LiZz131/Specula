# Review summary

## Counts

| Item | Count |
|---|---|
| Blocks reviewed (one per in-scope property) | 13 |
| Kept unchanged (`review: ok`) | 8: TypeOK, MCTypeOK, NotReachLeader, NotReachCommitWitness, NotReachOutstandingMembership, TraceMatched, ActiveLeaderHasCommittedVote, CommitWithinLocalLog |
| Changed | 5: ElectionSafety, CommittedLogAgreement, CommitWitnessSound, MembershipOrder, OneOutstandingMembership |
| Intent changed | 1 (ElectionSafety) |
| Status changed | 0 |
| Evidence lines removed | 7 (MembershipOrder 1, OneOutstandingMembership 6) |
| Evidence lines retyped | 1 (OneOutstandingMembership: `comment` → `impl` for core/admin.rs:137) |
| Evidence arrows reworded (line kept) | 4 (CommittedLogAgreement 3, OneOutstandingMembership 1) |
| Clauses added or split | 1 (CommitWitnessSound: `matched-term-kept: unknown` split from `quorum-support`) |
| Note sentences moved to `concerns.md` | 0 |
| `concerns.md` references removed from the model | 0 (none present) |

### Status matrix (old → new)

| old \ new | requirement | impl-abstraction | unknown | mixed | model-internal |
|---|---|---|---|---|---|
| requirement | 5 | 0 | 0 | 0 | 0 |
| impl-abstraction | 0 | 0 | 0 | 0 | 0 |
| unknown | 0 | 0 | 1 | 0 | 0 |
| mixed | 0 | 0 | 0 | 1 | 0 |
| model-internal | 0 | 0 | 0 | 0 | 6 |

## The five blocks I was least sure about

1. **OneOutstandingMembership.** Kept as `requirement`. Only two non-`impl` lines support it: membership_state.rs:9 and the commit message 7f34793. Read literally, together they give the intent. Two doubts:
   - "Committed" in the comments means committed in the cluster. 7f34793 is the only bridge to the node's own commit index, and raft_state.rs:49 says that index is volatile.
   - At restart, raft_core.rs:193-195 sets the commit index to `None` while storage/helper.rs:102-130 rebuilds the committed membership from storage. No quote covers this case (the note already says so).
   
   `unknown` would also be defensible. Removing six propose-after-commit / at-most-one-outstanding lines is the largest correction in this review. I made it because those quotes constrain proposals, not which entry is recorded as committed.
2. **CommitWitnessSound.** Two doubts:
   - The new clause `matched-term-kept` could be labelled `impl-abstraction` instead of `unknown`. I found no statement either way.
   - Clause `commit-not-below-witness` (kept as `requirement`) rests on one doc line from async-raft, deleted in 0135e3b, and covers only the leader. The `max` at replication.rs:190 was added in 4a83c76 under "TODO(xp): remove this line"; the `>` guard at replication.rs:146 is code only.
3. **ElectionSafety.** Narrowing the intent was a judgment call: "so a term never has two different leaders" is the natural meaning, but the formula does not check it by itself. The status is also borderline. a68a9a9 says openraft allows more than one leader per term, so the property fits neither `impl-abstraction` nor `requirement` well. I kept `unknown`, as the annotator had it.
4. **CommitWithinLocalLog.** Kept because engine_impl.rs:356 ("Committed index can not > last_log_id.index") reads as a rule and names no role. If it were read as narrating the `min` below it, the remaining non-`impl` evidence would cover only followers handling append-entries, and the block would need narrowing or `mixed`.
5. **MembershipOrder.** I removed guide/src/effective-membership.md:18 rather than rewording its arrow, because the literal quote supports no part of the intent. The remaining evidence orders the two entries by position ("first/second", "last"), not by index, as the note says. Keeping the line with a narrower arrow would also be a reasonable call.
