# Review decisions

One row per `REQ-EVIDENCE` block (13 blocks: 10 in `base.tla`, 1 in `MC.tla`, 2 in `Trace.tla`).
"Retyped / removed" lists only evidence lines whose type changed or that were dropped. Narrowed arrows, added evidence and note edits appear under "reason".

| Property | Old status | New status | Intent changed | Evidence retyped or removed | Reason |
|---|---|---|---|---|---|
| TypeOK | model-internal | model-internal | yes | — | The formula leaves `replyMessage` unconstrained, so "every model variable" overclaims. The intent now names the exception. |
| DurableVoteNotAhead | requirement | impl-abstraction | yes | — (3 non-impl arrows narrowed; watch adds `Config::enable_leader_restore`) | The formula compares the stored vote with the in-memory vote, but the cited invariant orders only the I/O cursors. `engine_impl.rs:153-162` and f4b5f61d say the stored committed vote is deliberately left ahead of the demoted in-memory vote when leader restore is disabled. The old note's "none found" was wrong. |
| DurableLogNotAhead | requirement | requirement | yes | removed `contract raft_log_storage.rs:98` | The intent was in I/O-id terms (vote first); the formula compares bare last log ids. `log_pointers.md:19/24/27` states that order directly (added), so the status holds and the old note's "none found" was wrong. :98's arrow ("part of the log before reported flushed") is contradicted by :103 (the callback may come before the return). I/O-id and :101 arrows narrowed. |
| VoteRequestAfterDurable | impl-abstraction | impl-abstraction | no | — | ok. Quotes are present, and the test and contract arrows already say they cover only queue order and save durability. No source requires sending to wait for the save; 88754e09 allows reordering. |
| GrantedResponseAfterDurable | requirement | requirement | no | — | ok. ee460f37 (a Fix commit) states the reply waits on the SaveVote flush. The 36d2c115 diff confirms the local self-grant is sent after `save_vote`. The contract and elect test cover the rest. The impl IOFlushed condition is still present. |
| LeaderRoleHasCommittedSelfVote | requirement | requirement | no | retyped `vote_handler/mod.rs:163` comment → impl | The line is the doc line of `become_leader()`. It restates the calling condition and what the function does; :165-167 say it is not called on election, so it states no rule about the Leader role. vote.md:61/48, raft_state/mod.rs:459 and the test still support the intent. |
| CandidateRoleHasPendingSelfVote | requirement | requirement | no | — (arrow on `raft_state/mod.rs:446` narrowed) | The arrow added "i.e. not committed", which is not in the quote; narrowed to "leadership not yet granted by a quorum". vote.md:65 and two tests still support the intent. |
| CertifiedLeaderHasFrozenQuorum | mixed | mixed | no | — (clause summary corrected; note extended) | The quorum-granted clause said the tests show "a majority of every constituent config", but both tests use uniform configs. raft-essentials.md:103 (use the latest configuration) is now recorded in the note as found and not counted for frozen-config. |
| MembershipAtMostOneOutstanding | requirement | requirement | no | retyped `change_handler.rs:50` comment → impl | The line is the doc line of `ensure_committed()` and restates what it checks. One note sentence about how the formula's index bound is read describes the model; moved unchanged to concerns.md and replaced with an evidence-only note. The other comments, docs, history and tests still support the intent. |
| NoForgedMessageEndpoints | model-internal | model-internal | no | — | ok. The intent matches the formula. I re-ran the note's search and found no matches; the :1374 quote is present. |
| MCTypeOK | model-internal | model-internal | no | — | ok. The intent matches `TypeOK /\ faultCounters ∈ [...]`. |
| TraceConsumed | model-internal | model-internal | no | — | ok. The cursor advances only through validated `TraceStep`s, so reaching `Len+1` means every event matched. |
| TraceTypeOK | model-internal | model-internal | no | — | ok. The intent matches `TypeOK /\ cursor ∈ 1..Len+1`. |

## Note text replaced (for traceability)

These note lines were about evidence, not the model, so they were not moved to concerns.md. They were replaced because they were factually wrong or no longer matched the block.

- **DurableVoteNotAhead**, old note: "the documented invariant is stated for the IOProgress cursors (IOId, ordered by vote first), not for RaftState.vote itself; searched docs/, vote_handler, raft_core, storage/helper.rs and history (log -S'flushed <= submitted <= accepted' -> 2666d3d3, ee460f37) for a rule written directly over the in-memory vote and the stored vote; none found". It is wrong: `engine/engine_impl.rs:153-162` (inside `Engine::startup`, which the block's own watch line lists) and commit f4b5f61d both speak directly about the in-memory vote versus the stored vote.
- **DurableLogNotAhead**, old note: "the documented invariant is stated over IOId, which orders by leader vote before log id; no doc, comment or commit found states it over the bare last log id". It is wrong: `docs/data/log_pointers.md:19-27` states `flushed ≤ submitted ≤ accepted` over log entries, with `accepted` = `last_log`.
- **MembershipAtMostOneOutstanding**, old note: moved unchanged to `concerns.md` (it describes the model).
