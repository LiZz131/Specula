# Concerns

## Sentences moved out of `note:` lines

**None.** I read every `note:` line in the annotated model, in `base.tla` (TypeOK, CommitWithinAccepted, MembershipWellFormed, CandidateGrantSound, LeaderVoteCommitted, DurableStateBounded, CurrentTermCommit) and `Trace.tla` (TraceMatched). Each one describes only the evidence search: what was searched, which commit a `log -S` led to, why a source was or was not counted, and how the evidence relates to the intent. None describes the model's actions or helpers, whether the model matches the code, where it is weaker, stronger or a proxy, or what might be wrong. So nothing was moved and no note sentence was deleted. No line in the model referred to `concerns.md`, before or after the review.

I also checked the `clause` lines that justify `model-internal` (MembershipWellFormed `node-domain`, MatchWithinLeaderLog `non-leader-records`). They say why no source evidence exists for that part of the formula, which is the evidence summary a clause line is meant to give. I left them in place.

## Reviewer observations about the model (not moved from any note; not referenced in the model)

These came up while I checked whether each intent describes its formula. They are about the model, not the evidence, so they are recorded here rather than in any `note:` line.

- **TypeOK**: several conjuncts are not type checks. `ValidConfigs(configs[n])` is MembershipWellFormed, `learners[n] \subseteq Server \ Voters(configs[n])` is LearnersExcluded, `committedMembershipIndex[n] \in 0..effectiveIndex[n]` contains MembershipOrder, and `match[n][p] \in -1..LastIndex(n)` contains MatchWithinLeaderLog. A violation of those requirements would therefore also show up under a property marked `model-internal`.
- **CandidateGrantSound**: `Restart` and `RestartFromRecovered` set `leaderGrants[n]` to `Voters(configs)` and `leaderConfigs[n]` to the same config. For a leader re-created on startup, the quorum conjunct therefore holds by construction rather than from recorded grants.
- **DurableStateBounded**: `FlushLog` sets `durableLogs[n]` to the whole of `logs[n]`, including entries beyond `submittedIndex[n]`. The first conjunct therefore compares the saved committed index with a persisted log that can be longer than what has actually been flushed.
- **IOOrder / DurableStateBounded**: `storage/v2.rs:82-85` and 942ec78b make `save_committed` optional, with a default that saves nothing. The model's `SaveCommit` always updates `durableCommit`, so `durableCommit` stands for "the committed id handed to `save_committed`", not necessarily a value the storage keeps.
