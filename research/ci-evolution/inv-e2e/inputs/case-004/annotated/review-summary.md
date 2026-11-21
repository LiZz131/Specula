# Review summary

## Counts

| | Count |
|---|---|
| Blocks reviewed | **25**: 13 full blocks (12 in `base.tla`, 1 in `Trace.tla`) + 12 one-line alias blocks in `MC.tla` |
| Kept unchanged (`review: ok`) | **19**: IOOrder, CommitWithinAccepted, MembershipOrder, LearnersExcluded, CurrentTermCommit, CommittedLogAgreement, TraceMatched, and all 12 MC aliases |
| Changed | **6**: TypeOK, MembershipWellFormed, CandidateGrantSound, LeaderVoteCommitted, MatchWithinLeaderLog, DurableStateBounded |
| Intent changed | **1**: TypeOK |
| Status changed | **0** |
| Evidence lines retyped comment → impl | **4**: engine_impl.rs:642, candidate.rs:106, vote_handler/mod.rs:178, vote_handler/mod.rs:119 |
| Evidence arrows narrowed | **3**: error.rs:610, change_handler.rs:29, progress/entry/mod.rs:33 |
| Evidence lines added | **2**: log_pointers.md:31 and log_pointers.md:27 in MatchWithinLeaderLog |
| Evidence lines removed outright | 0 |
| Clause lines changed | 1 split: MatchWithinLeaderLog `leader-progress` → `target-progress` + `self-progress` |
| `note:` sentences moved to concerns.md | 0 (every note line was evidence-only) |

### Status matrix (old → new), 13 full blocks

| old \ new | requirement | mixed | model-internal | impl-abstraction | unknown |
|---|---|---|---|---|---|
| requirement | 9 | 0 | 0 | 0 | 0 |
| mixed | 0 | 2 | 0 | 0 | 0 |
| model-internal | 0 | 0 | 2 | 0 | 0 |

The 12 alias blocks carry no status field; each still points to its target.

## The five blocks I was least sure about

1. **TypeOK**: I kept `model-internal` because `ANNOTATION-RULES.md` puts type invariants there. But four of its conjunct groups coincide with requirement properties (MembershipWellFormed, LearnersExcluded, MembershipOrder, MatchWithinLeaderLog). A strict use of the granularity check would make it `mixed` with clauses. I only rewrote the intent, which had claimed "every model variable", and added a note pointing to the blocks that hold the evidence.
2. **MatchWithinLeaderLog**: the new `self-progress` clause rests on reading log_pointers.md:31 ("committed means a quorum flushed the log entry") as covering the leader's own recorded match, chained with :27 and :24. The more conservative alternative was to narrow the intent to replication targets and mark the self entry `unknown`. The history search (340ec16d, a9f696a9) found no direct statement I was willing to cite.
3. **DurableStateBounded**: the saved-committed bound is not stated anywhere. It is inferred from 942ec78b, storage/v2.rs:34-35 and log_pointers.md:34 together, and the note says so. I kept `requirement` because the chain is direct: committed ≤ submitted when saved, and writes are serialized. A stricter reviewer might split this into a `requirement` clause for the vote and an `unknown` clause for the committed bound.
4. **CandidateGrantSound**: the intent says "granted by a quorum" without naming the config. The formula counts the quorum in `leaderConfigs`, and the note says which config is used is found only in impl. I treated that as a detail the intent does not claim and kept `requirement`. Retyping engine_impl.rs:642 to `impl` is also a judgment call: it is a one-line summary of what the function does, not a rule.
5. **LeaderVoteCommitted**: once vote_handler/mod.rs:178 was retyped to `impl`, the leader-state half rests on a design-description commit message (36d2c115), the leading-state doc in leader.rs:18-27, and assertions in a single election-path test. I judged that enough for `requirement`, but no source states "a Leader always has leader state" as a rule.
