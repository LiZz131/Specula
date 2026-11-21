# Concerns about the model and the evidence

These are observations only; the model was not changed. "base Spec" means `Spec` in `base.tla`, as checked by `base.cfg`. "MC" means `MCSpec` with `MC.cfg`. TLC scratch runs live in `/work/out/tmp/` and used copies of `base.tla`; their exact steps are listed under each concern.

## C1. `CommittedLogAgreement` is violated by the base Spec: split brain through unconstrained vote responses and acks (confirmed with TLC)

`ReceiveVoteResponse(n, peer, t, owner, FALSE)` counts any `peer \in Server` as a grant. It never looks at that peer's `voteTerm/voteNode` and has no matching vote request. `AcknowledgeReplication(n, peer, idx)` accepts any `idx` up to the leader's own `LastIndex(n)`, whether or not `peer` holds that entry. Together these let two nodes become leader in the same term, with each counting the other as a granter, and each commit its own blank entry at index 1.

TLC counterexample (`tmp/tlc1/SplitBrain.tla`, 13 states). Every step is an instance of a base `Next` disjunct within `base.cfg` bounds (MaxTerm=2, MaxIndex=3):

`StartElection(1)`, `StartElection(2)`, `ReceiveVoteResponse(1,1,1,1,F)`, `ReceiveVoteResponse(1,2,1,1,F)`, `ReceiveVoteResponse(2,1,1,2,F)`, `ReceiveVoteResponse(2,2,1,2,F)`, `SubmitLog(1)`, `SubmitLog(2)`, `FlushLog(1)`, `FlushLog(2)`, `AcknowledgeReplication(1,2,1)`, `AcknowledgeReplication(2,1,1)`

→ `commitIndex = <<1,1,0>>`, `EntryAt(1,1) = (term 1, node 1)` and `EntryAt(2,1) = (term 1, node 2)`.

In the source, node 2 grants a vote only if it is ≥ its own vote (`docs/data/vote.md:16`; `engine/handler/vote_handler/mod.rs:126-137`). A grant is recognised only when the responded vote equals the candidate's vote (`engine/engine_impl.rs:373-376`). Matching is updated only from real AppendEntries responses (`replication_handler/mod.rs:186-216`). The base Spec has none of these links.

## C2. `DurableStateBounded` (saved-committed clause) is violated by the base Spec, and so is `CommitWithinAccepted` after a restart (confirmed with TLC)

`AcknowledgeReplication` lets a follower ack entries the leader has not yet submitted, so `commitIndex` can run ahead of `submittedIndex`/`flushedIndex`. `SaveCommit` is not ordered after `FlushLog`. When the leader is outside the voter config (allowed: `{{1,2}} → {{1,2},{2,3}} → {{2,3}}`), commit reaches index 3 while the leader has only submitted index 2.

TLC counterexample (`tmp/tlc2/DurableProbe.tla`, 13 states):

`StartElection(1)`, two `ReceiveVoteResponse`, `LeaderAppend(1,"joint",{{1,2},{2,3}},{})`, `SubmitLog(1)`, `FlushLog(1)`, `AcknowledgeReplication(1,2,2)`, `AcknowledgeReplication(1,3,2)`, `LeaderAppend(1,"uniform",{{2,3}},{})`, `AcknowledgeReplication(1,2,3)`, `AcknowledgeReplication(1,3,3)`, `SaveCommit(1)`

→ `durableCommit[1] = 3` while `Len(durableLogs[1]) - 1 = 2`.

Adding `Crash(1)` and `Restart(1)` (`tmp/tlc2/DurableProbe2.tla`) gives `commitIndex[1] = 3 > acceptedIndex[1] = 2`, which violates `CommitWithinAccepted` at state 15.

Source counter-evidence:

- `core/raft_core.rs:1644-1648`: "`Replicate` command can not run until this IO request is submitted";
- `docs/data/log_pointers.md:34-35`: "`committed` ≤ `submitted` always hold only because the replication mod needs to read log entries from local storage";
- `storage/v2.rs:34-36`: log-store write IO is serialized, so `save_committed` follows the appends issued before it.

The model checks neither `committed ≤ submitted` (`log_pointers.md:28`) nor the submit-before-replicate ordering.

Not reachable in MC. `MembershipLimit = 1` allows only one membership entry, so the joint→uniform path cannot happen.

## C3. MC passes, but exercises several properties only trivially

`MC.cfg` completes with no error: 286,148 distinct states, depth 25. `MCNext` uses canonical identities:

- only node 1 can elect, append, ack, save-commit, apply, crash or restart;
- node 2 can persist a vote, grant node 1, append and respond;
- node 3 is passive.

Consequences:

- **`CommittedLogAgreement`.** `commitIndex` changes only on node 1. No action in the model advances a follower's commit index: there is no counterpart of `FollowingHandler::commit_entries` / `Engine::handle_commit_entries`. So for any pair of distinct nodes, MC compares only index 0. The property is effectively unexercised in MC, and C1 shows the base Spec violates it.
- **`CandidateGrantSound`, `LeaderVoteCommitted`, `CurrentTermCommit`, `MatchWithinLeaderLog`.** Only node 1 can ever be leader in MC.
- **`CommitWithinAccepted` on followers is vacuous** (follower commit stays 0). The follower clamp `min(accepted, leader_committed)` (`following_handler/mod.rs:164`, introduced by 90c29ccb for exactly this property) has no counterpart in the model.

## C4. No log truncation or replication of membership entries to followers

`ReceiveAppendDirect` requires `prev = LastIndex(n)` and appends fresh `"data"` entries built from the follower's own `configs[n]/learners[n]`. Consequences:

- conflicting suffixes are never truncated (`FollowingHandler::ensure_log_consecutive`, `truncate_logs`);
- membership entries never reach followers (`membershipVars` is UNCHANGED in `ReceiveAppendDirect`);
- the effective-membership revert (`MembershipState::truncate`, `docs/data/effective-membership.md`) is never exercised.

`MembershipOrder`, `MembershipWellFormed` and `LearnersExcluded` are therefore checked only on the leader's own appends and on restart. On followers they only ever see the initial config. `CommittedLogAgreement` also cannot see the overwrite-of-uncommitted-entries scenarios that `docs/protocol/log_replication.md` describes.

## C5. `CurrentTermCommit` is weaker than its name

The formula checks only `EntryAt(n, commitIndex[n]).term <= voteTerm[n]` on a leader. That bound holds for any entry in a leader's log: entries are appended with a term ≤ the node's monotone vote term. The rule the name refers to is "a leader commits only entries proposed by its own leader id":

- `replication_handler/mod.rs:221-228`;
- `raft_state/mod.rs:56-57`;
- `docs/data/log_pointers.md:17`.

That rule is enforced as a guard inside `NewCommitAfter`, but no property checks it. If the guard were removed or broken, `CurrentTermCommit` would still pass. A checkable form: whenever `commitIndex[n]` increases on a leader, the newly committed entry has `term = voteTerm[n]` and `node = voteNode[n]`. That is an action property, or an invariant over a history variable.

## C6. `CandidateGrantSound` holds partly by construction

`leaderGrants` is ghost state written by the same actions that set `role = "Leader"`:

- `Restart` sets `leaderGrants := Voters(em.cfg)` when `selfLeader`, so after a restart the quorum clause holds by definition;
- `RestartFromRecovered` (used by Trace) does the same;
- together with C1, `ReceiveVoteResponse` can put any node into `granters`.

So the property shows that the bookkeeping is consistent. It does not show that real voters granted the vote. The source allows leadership without a fresh election in two cases:

- `vote_handler/mod.rs:184-185`: "node-a electing for node-b";
- 36d2c115 (message): "re-creating the Leader upon startup".

The model represents neither, except through Restart's fiat grant set.

## C7. Freshness check in `ReceiveVoteRequest` compares only indexes

The model grants when `reqLast >= LastIndex(n)`. The source compares full log ids, term first: `engine_impl.rs:319`, `req.last_log_id.as_ref() >= self.state.last_log_id()`. A candidate with a longer log from an older term would be granted in the model but rejected by the code. The leader-lease rejection (`engine_impl.rs:305-315`) is also abstracted away; the model's own comment says so.

## C8. Self-grant ordering differs between base `Next` and MC

`MCVoteResponse(n, n)` requires the durable vote to equal the candidate vote before the self-grant. That matches `core/raft_core.rs:1657-1668`, where the self `VoteResponse` is sent after `save_vote`, and 36d2c115: "The `Voting` state is now updated only after `SaveVote` is successfully persisted". The base `Next` has no such guard, so a candidate can count its own grant before persisting its vote.

## C9. `Restart` restores Leader without the membership check the code uses

`selfLeader == durableVoteCommitted[n] /\ durableVoteNode[n] = n` ignores membership. The source requires `membership_state.contains(id)` (`raft_state/mod.rs:369-371`), and `docs/data/vote.md:74` lists such a node as `learner` when absent from the config. A leader removed from the config restarts as Leader in the model but as Learner in the code.

## C10. `TypeOK` contains semantic constraints that duplicate other invariants

`TypeOK` includes:

- `committedMembershipIndex[n] \in 0..effectiveIndex[n]` (= `MembershipOrder`);
- `ValidConfigs(configs[n])` (= `MembershipWellFormed`);
- learner/voter disjointness (= `LearnersExcluded`);
- `commitIndex[n] \in 0..LastIndex(n)`;
- `match[n][p] \in -1..LastIndex(n)` (⊇ `MatchWithinLeaderLog`).

Because `TypeOK` is listed first, violations of these will be reported as `TypeOK` rather than as the named property. Several variables have no domain clause at all: the durable vote, durable logs, `durableCommit`, candidate fields, `granters`, `leaderGrants`, `pendingVote*`.

## C11. `IOOrder` and `log_pointers.md` differ

`docs/data/log_pointers.md:27-28` states `flushed ≤ submitted ≤ accepted` and `applied ≤ committed ≤ submitted`. `IOOrder` checks `applied ≤ durableCommit` (the saved committed) instead of `applied ≤ committed`. It omits `committed ≤ submitted`, which C2 shows the base Spec can violate. `io_state.rs:93` notes "Applied does not have to be flushed in local store"; the model is consistent with that.

## C12. The baseline commit named in `base.tla` is not in the history

The `base.tla` header says "Baseline 955ebf13f9c4acf88240775db2b51832c9cbb6a9". `tools/hist.sh log --oneline | grep 955ebf1` finds nothing. The history base is `7fa0f9b77b37c4bf2e63c8601160a3e10c3e17e3`. The line ranges cited inside `base.tla` match the present tree, for example `engine_impl.rs:122-140,221-249` (`new_candidate`, `elect`) and `293-343` (`handle_vote_req`). The content is therefore probably the same, but the identifier should be corrected or explained.

## C13. `TraceMatched` cannot be checked in /work

`Trace.tla` reads `../traces/election.ndjson` by default and validates fields emitted by a `capture()` instrumentation. Neither the traces nor any trace emitter is present: searching `source/` for `ndjson`, `TraceLog` and `tla` found nothing. `TraceMatched` therefore depends on artefacts outside this revision of the source.

## C14. Stale-response path has no property

`DropStaleResponse` only sets the observer `staleResponseSeen`, and no invariant or property reads it. Whether a stale replication response can change `match` or `commitIndex` (`Command::RebuildReplicationStreams` doc, `engine/command.rs:91-95`) is not checked.

## Evidence that weakens or qualifies a property

- **`DurableStateBounded`.** `docs/data/log_pointers.md:30-32` says "`committed` ≤ `flushed` does not have to hold". That sentence is about the in-memory committed index, but it shows the bound on the *saved* committed index depends on the storage write-ordering contract (`storage/v2.rs:34-36`) and on submit-before-replicate. No source states the bound directly.
- **`MembershipWellFormed`.** `Membership` derives `Default` (`membership/membership.rs:20`), which is an empty joint config, and uninitialised nodes start with it. The model starts from an initialised cluster (`configs = {InitialVoters}`), so this does not contradict the property as modelled. It does mean "at least one config" is not a universal code invariant.
- **`LeaderVoteCommitted` / `CandidateGrantSound` and voters.** `docs/data/vote.md:59` and `raft_state/mod.rs:341-342` say a Leader does not have to be a voter. The model's `StartElection` requires `IsVoter(n, n)`. That narrows the reachable states but does not conflict with the properties.
