# Concerns

Things that look wrong in the model, or source evidence that contradicts a property, found while
annotating. None of them were fixed: `spec-annotated/` only adds comments. Ordered most-important first.
Line numbers refer to `spec-original/` (the annotated copy is shifted by the inserted comment lines).

## C1. `DurableVoteNotAhead`: the source deliberately breaks it when `enable_leader_restore = false`

**Contradicting evidence (base revision, newest commit `f4b5f61d`):**

- `source/openraft/src/engine/engine_impl.rs:148-166` (`Engine::startup`). If leader restore is
  disabled, a restarted leader's committed self-vote is lowered to the non-committed form **in memory only**:
  "Demote the vote in memory only; do not persist it." (l.153). The comment then argues this is safe:
  "Keeping the committed vote in storage is safe ... the next `SaveVote` automatically heals the divergence" (l.159-162).
- `source/openraft/src/engine/tests/startup_test.rs:243-271` `test_startup_as_leader_leader_restore_disabled`
  asserts `eng.state.vote_ref() == &Vote::new(2, 2)` (non-committed) and says at l.267: "the committed vote stays in storage".
- Commit `f4b5f61d` (message): "the committed vote intentionally stays in storage".
- `source/tests/tests/life_cycle/t50_leader_restart_leader_restore_disabled.rs` exercises this path end-to-end.

With that setting, after a restart the stored vote `(t, n, committed)` is greater than the in-memory
vote `(t, n, non-committed)`, so `VoteLE(durableVote[i], vote[i])` is **false** for `RaftState.vote`.
The source treats this as correct behaviour, so a counterexample here would not be a code bug.

**Why the model does not see it:** `Restart` (base.tla:509-543) always sets `vote' = durableVote[i]` and
gives the `"Leader"` role to a committed self-vote. That is only the `enable_leader_restore = true`
behaviour (the default: `Config::enable_leader_restore()` returns `unwrap_or(true)`, shown in the
`f4b5f61d` diff), although the comment above `Restart` (l.535-537) mentions the flag. `Trace.tla`
`TraceInit` also sets `durableVote = vote` for the focus node (l.28), so a trace taken with the flag off
cannot start from the demoted state.

**What still holds:** the documented invariant is about the IOProgress cursors (`flushed <= submitted <= accepted`,
`io_progress.rs:12`). The demotion leaves those alone, because `IOState` is built from the stored vote
(`storage/helper.rs:192-198`) before `startup()` runs. The annotation's intent was narrowed to that
I/O-progress reading. To check the property for both settings, the model would need to restate it over an
accepted-I/O variable and add a `Restart` variant for the disabled flag.

## C2. `CertifiedLeaderHasFrozenQuorum` holds by construction and does not cover other leader paths

- `leaderCertified`, `leaderConfig` and `leaderGrants` are written only in `Init`, in `HandleVoteResponse`
  when `wins` (l.343-345) and in `Restart` (l.526-528). No guard of any action reads them.
  `HandleVoteResponse` gives them exactly the `candidateConfig[i]` and `ng` for which `wins` already
  requires `IsQuorum(candidateConfig[i], ng)`. So the invariant can fail only if that one action is
  edited inconsistently. It checks the action's own bookkeeping, not a behaviour that emerges from the model.
- A node can also become leader in these ways, none of which sets `leaderCertified`:
  - `Restart` gives `leaderActive` and the `"Leader"` role from a durable committed self-vote.
  - `HandleVoteRequest` (l.300-304) and `HandleAppendEntries` (l.471-474) accept a committed vote naming `i`;
    this matches the source's `become_leader` path (`vote_handler/mod.rs:163-171`).

  The property says nothing about these leaders.
- The "frozen" part, counting grants against the membership copied at election start, has only impl
  support (`engine_impl.rs:121-127`). It is recorded as an `impl-abstraction` clause.

## C3. `DurableLogNotAhead`: raw last-log-id comparison; the model has no truncation or follower append

- The documented invariant is stated over `IOId` (ordered by leader vote first, then log id; `docs/data/io_id.md:100-111`),
  not over the bare last log id.
- In the source, follower truncation updates the in-memory log before the storage I/O runs:
  `following_handler/mod.rs:177-178` (`self.state.log_ids.truncate(since);` then `push_command(Command::TruncateLog { after })`).
  Until `TruncateLog` executes, the stored last log id is greater than `state.last_log_id()`. The raw-LogId
  form of the property would be false there; the IOId form would not.
- The model cannot reach that case:
  - `HandleAppendEntries` leaves `logVars` and `configVars` unchanged (l.476-479): no entries, no truncation.
  - There is no snapshot install and no `allow_log_reversion`.
  - `lastLog` changes only through the leader's own appends and `Restart`.

  So the property is never checked where the two forms differ.

## C4. `VoteRequestAfterDurable` mostly restates a guard

- `SendVoteRequest` (l.243-255) sends `candidateVote[i]` only under `VoteLE(candidateVote[i], durableVote[i])`.
  The invariant therefore mostly restates that guard; only `Restart` interacts with it.
- In the source, the ordering comes from running commands one at a time with `save_vote` awaited
  (`raft_core.rs:1104-1112`, `:2145`, `:2204`). No doc or comment requires it. Two commit messages
  point the other way:
  - `36d2c115` says `SaveVote` is expected to become callback-based, and makes only the *voting state*
    wait for persistence.
  - `88754e09` says "Command execution can be reordered or batched for performance."

  If that change lands, vote requests may go out before the vote is durable. Both this property and the
  guard would then stop matching the code. The rule the history does record, that the self-grant waits
  for persistence, is covered by `GrantedResponseAfterDurable`.

## C5. `MembershipAtMostOneOutstanding`: follows from the append guards; commit is unconstrained; followers never learn configs

- The append guards make the property structural:
  - `AppendJointConfig` and `AppendUniformConfig` require `committedConfigIndex[i] = effectiveConfigIndex[i]`
    and add 1 to the effective index.
  - `CommitMembership` copies effective to committed.
  - `Restart` sets both from the durable copy.

  Both clauses therefore follow from the guards by construction.
- `CommitMembership` (l.411-418) has no quorum or commit-index guard, so any node can "commit" its
  effective config at any time.
- Followers never learn a config, because `HandleAppendEntries` carries none. These source paths are
  therefore not modelled, and the property is only checked against leader-local append and commit:
  - `FollowingHandler::append_membership`, which keeps the last two configs found in a batch;
  - `MembershipState::truncate`, which reverts effective to committed;
  - `MembershipState::install_membership_snapshot`.
- The model counts configs with an abstract index that goes up by 1 per config. The source compares
  membership `log_id`s (`membership_state/mod.rs:277-278`), so "+1" means "one more config", not "the next log index".

## C6. `NoForgedMessageEndpoints` duplicates a `TypeOK` conjunct

`TypeOK` already contains `m.source \in Server /\ m.dest \in Server` (base.tla:594). Every cfg that
checks `NoForgedMessageEndpoints` also checks `TypeOK`, `MCTypeOK` or `TraceTypeOK`, so it adds nothing.
The source states nothing about message endpoints: a search for byzantine/forged/authentication found nothing.

## C7. `Trace.tla` start state and omitted invariants

- `TraceInit` sets `durableVote = vote` and `durableLastLog = lastLog` for the focus node (l.28, l.51),
  even when the snapshot has `save_vote_pending` or `append_pending` set. A trace that starts with a
  pending `SaveVote` therefore begins with the unsaved vote already counted as durable. Two consequences:
  - `DurableVoteNotAhead` and `DurableLogNotAhead` hold trivially at the start.
  - `PersistVote`, which requires `VoteLT(durableVote[i], vote[i])`, can never fire for that pending
    save, so `votePersistPending` stays `TRUE`.
- `Trace.cfg` does not check `VoteRequestAfterDurable` or `GrantedResponseAfterDurable`. This may be
  intentional, since `TraceInit` starts with `messages = {}`, but it means the trace run never checks the
  message-ordering properties.

## C8. Leader or candidate that is a non-voter member (scope)

`vote.md:74-79` and `RaftState::is_leading` (`raft_state/mod.rs:453-455`, `membership_state.contains(id)`)
make a node with a self-vote leader or candidate whenever it is *present* in the membership, voter or not.
The model's `RoleFrom` and `Restart` use `InConfig`, which is voters only, and configs have no learners.
The role properties are unaffected because they are stated role-to-vote, but this source case is not modelled.

## C9. Evidence nuance: the `vote.md` table is not an equivalence for the cached role

`vote.md:77` says a node holding its own uncommitted vote and present in the config is a *candidate*.
`Engine::startup` (`engine_impl.rs:169-175`) nevertheless sets `server_state = Follower` for such a node,
as the comment above `Restart` (base.tla:535-537) also says. The server state is cached, not a pure function
of the vote. `LeaderRoleHasCommittedSelfVote` and `CandidateRoleHasPendingSelfVote` read the table
role-to-vote, which this does not contradict, but the table should not be read as "self-vote implies Candidate".
