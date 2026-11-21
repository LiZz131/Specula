# Concerns

## 1. Model observations moved out of `note:` lines

Each sentence is quoted unchanged, with the property it came from.

| Property | Moved sentence (unchanged) |
|---|---|
| MembershipAtMostOneOutstanding | "the sources count outstanding membership logs ordered by log id, not log indexes; the bound is read here as a count of membership configs" |

No other `note:` line described the model. The notes of DurableVoteNotAhead and DurableLogNotAhead were rewritten because their evidence claims were wrong (see `decisions.md`), not because they described the model. Nothing was moved from those two.

## 2. Reviewer observations (not moved from notes)

These came up during the review. They are kept here and not in the model because they describe the model or contradict a property. None of them changed a definition.

- **DurableVoteNotAhead: contradicting evidence.** `source/openraft/src/engine/engine_impl.rs:153-162` and commit f4b5f61d (message) cover `Config::enable_leader_restore = false`. In that case `Engine::startup()` demotes a committed self-vote to non-committed in memory only, and "the committed vote intentionally stays in storage". Then the stored vote orders strictly above the in-memory vote, which is the opposite of what `DurableVoteNotAhead` checks. The model's `Restart` sets `vote' = durableVote` and restores `Leader` for a committed self-vote. It therefore follows only the leader-restore-enabled path, which is the default (`config.rs:582`, `unwrap_or(true)`). The property would fail by design if the disabled path were modelled.
- **TypeOK** does not constrain `replyMessage`. It is the only state variable missing from `TypeOK`.
- **CertifiedLeaderHasFrozenQuorum.** `source/raft-essentials.md:103` says "a server always uses the latest configuration in its log, regardless of whether the entry is committed". The formula counts grants against the config captured at election start (`leaderConfig` ← `candidateConfig`). The two agree only while the candidate's effective config does not change during its election. I did not check whether that can happen in the code or the model.
- **MembershipAtMostOneOutstanding (open question, not verified).** `Trace.tla` sets `committedConfigIndex` / `effectiveConfigIndex` from the trace fields `committed_config_index` / `effective_config_index`. In `base`/`MC` those variables go up by 1 per appended config. If the trace fields are log indexes, the `+ 1` bound in trace validation means something different from "one outstanding config". I did not look at the trace format.
