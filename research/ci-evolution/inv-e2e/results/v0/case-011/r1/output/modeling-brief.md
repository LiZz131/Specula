# Modeling Brief — OpenRaft election model, incremental update to the Pre-Vote revision

> Incremental run (Specula incremental-modeling). Prior V0 suite:
> `/work/previous/.specula-output` (exact-old election prior, immutable).
> Source delta: neutral synthetic commits `baseline` (1adc857) → `update`
> (3ab6cdd) in `artifact/`; changed-file snapshots verified byte-identical with
> `/work/old-source` and `/work/new-source`. Category unchanged: **Category A**.
> Sections 1–7 below are the prior brief, retained; this preamble and §8 record
> the update analysis and supersede any prior statement they contradict.

## 0. Update disposition: MODEL_CHANGE_REQUIRED

The update adds an optional **Pre-Vote** round (`Config::enable_pre_vote`,
runtime-togglable, default off) and a manual cautious election
(`trigger().elect(true)`). Projected onto the existing model vocabulary it adds
new state (Engine.pre_candidate: probe vote, frozen config, grants), new
messages (PreVote request/response), new enablement for the election tick, and
new clearing effects in old Actions (`do_elect`, `become_following`). Old and new
projected post-state sets differ for TickElect, ExternalElect, the
become_following callers, and Restart, so `NO_MODEL_CHANGE` is not possible.
Details and per-branch projection: `analysis-report.md` §U.

## 8. Update Scenarios (Pre-Vote)

### Scenario U1 — Stale Pre-Vote round survives leader establishment (old producer → affected Action → old consumer)

**Mechanism**: the election tick does not check for an in-flight candidacy, so
a Candidate whose vote expired starts a Pre-Vote round (`pre_elect`) while its
real election is still collecting votes. If the real election then wins,
`establish_leader` consumes only `candidate`; `pre_candidate` survives
(`become_leader`, not `become_following`). A later granting Pre-Vote response
passes the runtime filter (pre_candidate present, same leader id) and
`handle_pre_vote_resp` calls `elect()` on the established leader.

**Evidence**:
- tick skips only `server_state == Leader`, non-voters, disabled elect; no candidate check for multi-voter: `openraft/src/core/raft_core.rs:1959-2036`
- `pre_elect` leaves `candidate` intact: `openraft/src/engine/engine_impl.rs:298-322`
- `establish_leader` takes `candidate` only: `openraft/src/engine/engine_impl.rs:855-881`; `update_vote(committed)` → `become_leader` (no pre_candidate clear): `openraft/src/engine/handler/vote_handler/mod.rs:154-162,172-230`
- runtime filter: `openraft/src/core/raft_core.rs:1803-1820,2067-2090`
- quorum → `elect()`: `openraft/src/engine/engine_impl.rs:530-541`
- `do_elect` on a leader leaves the Leader object while the vote becomes uncommitted: `engine_impl.rs:262-289`; leader handler asserts `leader.vote >= state.vote`: `engine_impl.rs:977-982`

**Model Actions**: `TickElect`/`ExternalPreElect` → `PreElect`, `HandleVoteResponse`
(win), `PersistVote`, `HandlePreVoteRequest`, `HandlePreVoteResponse` (win →
`DoElect`). **Property**: `Update!PreVoteNeverDemotesEstablishedLeader`
(diagnostic precondition `PreVoteRoundNotInheritedByLeader`).
**Priority**: High (the only update path where an automatic action makes a
healthy leader abandon leadership). **Outcome**: model-checking counterexample
(MC-1), engine and runtime reproduction — see `spec/bug-report.md`.

### Scenario U2 — Probe/election agreement (changed Action → old Action)

A Pre-Vote quorum must justify exactly the election it triggers: `do_elect`
recomputes `vote.term + 1` at election time
(`engine_impl.rs:262-289`) while the probe was computed at `pre_elect` time
(`engine_impl.rs:298-322`). Any old Action that changes the local vote while the
round is alive must cancel it (do_elect, become_following) or keep the term
(establish_leader). **Properties**: `PreVoteElectsAtProbedTerm`,
`PreCandidateProbesNextSelfTerm`.

### Scenario U3 — Voter gate (changed Action → old consumer)

Every other route to `do_elect` checks `is_voter` (`raft_core.rs:1683-1686,
1971-1974`); the Pre-Vote win path (`engine_impl.rs:530-541`) does not.
Membership is frozen in the round (`engine_impl.rs:149-165`) while a leader's
effective config can change (`AppendJointConfig`/`AppendUniformConfig`).
**Property**: `PreVoteElectOnlyByVoter`; hunt `MC_hunt_prevote_membership.cfg`.
**Outcome**: model-checking counterexample (MC-2): an operator's
`trigger().elect(true)` on the leader (`raft_core.rs:1683-1691` accepts a leader)
starts a round; the leader removes itself (`StepDownPolicy::Never` or within the
`After` window); the late grant makes the non-voter elect. Also reachable via
MC-1's inherited round. Reproduced; see `spec/confirmation-MC-2.md`.

### Scenario U4 — Pre-Vote request is a pure query (affected Action)

`handle_pre_vote_req` checks lease (never a transfer), last log, then vote order
and changes no state (`engine_impl.rs:405-447`; `raft_core.rs:1551-1562`
responds immediately). **Property**: `PreVoteHandlingIsSideEffectFree`
(structural); trace scenarios cover grant and each of the three reject guards.

### Scenario U5 — Cancellation by contact and faults (old context → affected Action → crash/recovery)

Any accepted vote of another node (vote request grant, AppendEntries heartbeat,
adopted higher vote) runs `become_following`, which now clears
`pre_candidate` (`vote_handler/mod.rs:244`); `do_elect` clears it
(`engine_impl.rs:263-264`); restart rebuilds the engine with `pre_candidate:
None` (`engine_impl.rs:117`). Delayed/dropped/Unreachable Pre-Vote RPCs produce
no notification (`raft_core.rs:1430-1478`) and are modeled by message loss.
**Hunt**: `MC_hunt_prevote_crash.cfg`; traces `heartbeat_cancels_pre_vote`,
`vote_grant_cancels_pre_vote`.

### Modeling decisions for the update

- Pre-Vote requests are dispatched atomically with `pre_elect` (SendPreVote has
  no condition, `engine/command.rs:340-364`, and only spawns RPC tasks); per-RPC
  delay/loss/timeouts are the message set and `DropMessage`.
- The runtime correlation (`does_pre_candidate_vote_match`) is folded into
  `HandlePreVoteResponse`'s `match` (pre-candidate present and equal leader id);
  responses carry the probe vote as `vote` (the notification's candidate_vote).
- Tick mode is the constant `TickPreVoteModes` ({FALSE}, {TRUE}, or
  {FALSE,TRUE} for runtime toggling). The "fresh round in flight" rate limit is
  timing and is abstracted (a stale round may be restarted at any tick).
- A tick only fires for a multi-voter node whose lease is not valid
  (`is_expired(now, election_timeout)` implies lease expiry) and, for a single
  voter, only without an active candidate (`raft_core.rs:1988-2008`).
- `preRoundFromLeader` (MC-layer history) distinguishes administrative rounds
  started on an established leader from rounds inherited by leadership.

### Exclusions (update)

- Network default `pre_vote` implementation that synthesizes a grant for peers
  without Pre-Vote support (`network/v2/network.rs:141-160`): environment
  choice for rolling upgrades; the model assumes peers implement `pre_vote`
  (test fixtures do: `tests/tests/fixtures/mod.rs:973-998`). Effect if modeled:
  Pre-Vote degrades to the historical direct election, which the model already
  contains (`TickPreVoteModes` ∋ FALSE).
- Timing of the round rate limit, election-timeout randomization, RPC ttl.
- Metrics/notification names, CommandName/RaftMsgName index renumbering,
  clap/serde config plumbing, docs: no protocol effect.

### Code-review notes (no model-checking counterexample)

- `docs/protocol/pre_vote.md:55-63` says the default `pre_vote` returns
  `Unreachable` and that an `Unreachable` response counts as a grant; the code
  does the opposite (default returns `Ok(granted)`, `network/v2/network.rs:158-161`;
  transport errors are not grants, `raft_core.rs:1460-1471`). Documentation
  inconsistency only; no protocol consequence in the modeled scope.
- Pre-Vote responses are correlated by leader id only, so grants from an
  earlier round at the same term count in a restarted round
  (`raft_core.rs:2067-2090`). Both rounds probe the identical vote; this is the
  same staleness as a delayed response within one round and is not reported.


---

# Prior V0 brief (retained)


## 1. System overview

The target is the Rust OpenRaft exact-old tree in `/work/source` (921 regular
files; the scoped election, membership, state, and runtime paths are about 7,000
lines). It is **Category A: distributed/message-passing**, because a
single-mutator Raft core drives a synchronous protocol engine while storage and
network commands cross asynchronous durability and RPC boundaries
(`openraft/src/engine/mod.rs:1-28`, `openraft/src/core/raft_core.rs:1088-1148`).
The selected type configuration uses the advanced, totally ordered leader ID
`(term,node)` and a committed bit, so different ordered leaders may exist in one
numeric term (`openraft/src/engine/testing.rs:38-48`,
`openraft/src/vote/leader_id/leader_id_adv.rs:9-25`). The model therefore treats
the full leader ID, not term alone, as the ballot. No fairness is assumed.

## 2. Scenarios

### Scenario 1: Election persistence gates communication

**Mechanism**: engine state advances before runtime I/O, but FIFO command order
requires a candidate vote to become durable before self-grant or remote vote
requests become observable.

**Evidence**:
- `Engine::do_elect` snapshots log/membership, updates the pending self vote,
  then queues `SendVote` (`openraft/src/engine/engine_impl.rs:230-253`).
- A strict vote increase queues `SaveVote`
  (`openraft/src/engine/handler/vote_handler/mod.rs:131-147`).
- Runtime awaits `save_vote`, emits the local granted response, and only later
  runs `SendVote` (`openraft/src/core/raft_core.rs:2138-2166,2203-2205`).

**Affected code paths**: `Engine::do_elect`, `VoteHandler::update_vote`,
`RaftRuntime::run_command`, `spawn_parallel_vote_requests`.

**Suggested modeling approach**: separate projected vote, durable vote,
`PersistVote`, local self-response, and `SendVoteRequest`; preserve FIFO-derived
guards rather than making election atomic.

**Priority**: High. **Rationale**: this is the main crash window and the source
of the self-vote ordering contract.

### Scenario 2: Ordered vote-request guards and durable replies

**Mechanism**: ordinary leader lease and last-log recency are checked before
vote ordering; a response to a strict vote update waits for that vote to flush.

**Evidence**:
- Request processing order is lease, log, then vote update
  (`openraft/src/engine/engine_impl.rs:285-326`).
- Leadership-transfer requests bypass the lease guard only
  (`openraft/src/raft/message/vote.rs:21-29`).
- Strictly greater votes are saved; equal votes only refresh their lease
  (`openraft/src/engine/handler/vote_handler/mod.rs:105-149`).
- Runtime conditions the RPC reply on current vote I/O flush
  (`openraft/src/core/raft_core.rs:1483-1499`).

**Affected code paths**: `Engine::handle_vote_req`,
`VoteHandler::update_vote`, `RaftCore::handle_vote_request`.

**Suggested modeling approach**: split reject/accept cases inside one handler
action, retain a pending reply across `PersistVote`, and model transfer as an
input bit rather than a separate protocol phase.

**Priority**: High. **Rationale**: reordering these checks changes both accepted
votes and crash-visible replies.

### Scenario 3: Frozen effective and joint election quorum

**Mechanism**: a candidate clones the current effective configuration and
counts exact-vote grants against that frozen joint quorum while membership can
later evolve independently.

**Evidence**:
- Candidate creation clones effective membership and last log
  (`openraft/src/engine/engine_impl.rs:113-130`).
- A response counts only when its full vote equals the active candidate vote
  (`openraft/src/engine/engine_impl.rs:329-354`).
- A joint configuration requires a strict majority in every component
  (`openraft/src/membership/membership_impl_quorum_set.rs:8-32`,
  `openraft/src/quorum/quorum_set_impl.rs:31-45`).
- Effective membership is the latest seen membership, committed or not
  (`openraft/src/raft_state/membership_state/mod.rs:24-50,255-263`).

**Affected code paths**: `Engine::new_candidate`, `Candidate::grant_by`,
`MembershipState::{append,commit}`, membership quorum implementations.

**Suggested modeling approach**: represent configurations as one- or two-set
sequences, snapshot them into `candidateConfig`, and make `IsQuorum` require a
majority in every sequence element. Split joint append, commit, and uniform
append.

**Priority**: High. **Rationale**: it is the election/membership interaction
explicitly inside the binding scope.

### Scenario 4: Delayed responses, leader establishment, and contact

**Mechanism**: delayed vote responses are correlated to the current candidate;
a quorum commits the self vote in memory, then runtime persists it before
replication, while committed AppendEntries contact can move another node to
following state.

**Evidence**:
- Candidate notification and response vote equality suppress stale replies
  (`openraft/src/core/raft_core.rs:1710-1729,1928-1953`,
  `openraft/src/engine/engine_impl.rs:340-388`).
- Establishment consumes the candidate, sets a committed vote, rebuilds
  replication, and projects a blank entry
  (`openraft/src/engine/engine_impl.rs:688-716`).
- An accepted AppendEntries vote is updated before follower log work and a
  successful response is flush-gated
  (`openraft/src/engine/engine_impl.rs:395-437`).

**Affected code paths**: `Engine::handle_vote_resp`, `establish_leader`,
`handle_append_entries`, `VoteHandler::become_following`.

**Suggested modeling approach**: consume stale responses without granting,
retain a quorum certificate snapshot for locally established leaders, split
committed-vote persistence from projected no-op log, and permit AppendEntries
delivery/reordering.

**Priority**: High. **Rationale**: this connects election safety to real message
correlation and post-election ordering.

### Scenario 5: Crash/restart reconstruction and cached role

**Mechanism**: crash loses candidate/leader objects, queued commands, leases,
and speculative state; restart reconstructs durable vote/log/membership and may
restore committed self leadership.

**Evidence**:
- storage helper reconstructs vote, log state, and at most two memberships
  (`openraft/src/storage/helper.rs:83-223,313-399`).
- startup restores a committed self leader by default or starts as
  follower/learner (`openraft/src/engine/engine_impl.rs:135-181`).
- membership append retains at most committed/effective records; commit copies
  effective into committed (`openraft/src/raft_state/membership_state/mod.rs:121-147,183-203`).
- a removed leader is recalculated only by a separately fenced refresh
  (`openraft/src/core/raft_core.rs:1660-1685`).

**Affected code paths**: storage helper reconstruction, `Engine::startup`,
`MembershipState`, `refresh_server_state`.

**Suggested modeling approach**: maintain durable vote/log/config separately,
make `Crash` retain only durable variables, make `Restart` clear candidate and
pending work, and keep membership commit separate from cached role refresh.

**Priority**: High. **Rationale**: restart is a binding neutral baseline and
tests the principal failure model without asserting progress.

## 3. Modeling recommendations

### 3.1 Model

- Full advanced ballot `(term,node,committed)` and its lexicographic order,
  because the selected unit configuration uses it (Scenarios 1, 2, 4).
- Projected versus durable vote/log/config plus pending persistence and reply
  state, because commands execute after synchronous engine mutation
  (Scenarios 1, 2, 5).
- Vote request/response and AppendEntries records in an asynchronous set with
  explicit drop, delay, and reorder choices (Scenarios 2, 4).
- One- and two-component effective membership, frozen candidate membership,
  joint-majority calculation, and two-step ordinary evolution (Scenario 3).
- Crash/restart and separately refreshed cached role (Scenario 5).

### 3.2 Do not model

- Precise milliseconds, random timeout selection, metrics, transport framing,
  serialization, payload bytes, snapshot transfer, or replication batching:
  these are excluded by `/work/scope.md` and do not change the selected safety
  boundaries.
- Eventual election or delivery: the exact-old code supplies retry/tick
  mechanisms but no unconditional scheduler, storage, or network fairness.
- Standard single-term leader-ID mode: the neutral scoped engine tests select
  the advanced leader-ID implementation.

## 4. Proposed extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Persistence staging | `durableVote`, `votePersistPending`, `replyPending`, `durableLastLog` | preserve crash and reply/send ordering | 1, 2, 5 |
| Frozen candidate quorum | `candidateConfig`, `grants`, `leaderConfig`, `leaderGrants` | check exact-vote joint certification | 3, 4 |
| Membership staging | `committedConfig`, `effectiveConfig`, indices, durable config | model joint then uniform evolution and restart | 3, 5 |
| Cached roles | `role`, `leaderActive` | represent delayed removal refresh and leader/candidate coexistence | 4, 5 |
| Asynchronous messages | `messages`, `sentVoteReq` | model delay/reorder/drop without forgery | 1, 2, 4 |

## 5. Proposed invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `TypeOK` | Safety/structural | every state is within the declared bounded domains | all |
| `DurableVoteNotAhead` | Safety | durable vote never exceeds projected local vote | 1, 5 |
| `VoteRequestAfterDurable` | Safety | every emitted vote request is backed by at least that durable vote | 1 |
| `GrantedResponseAfterDurable` | Safety | every visible granted response is backed by at least that durable vote | 1, 2 |
| `LeaderRoleHasCommittedSelfVote` | Safety | cached Leader always carries a committed self ballot | 4, 5 |
| `CandidateRoleHasPendingSelfVote` | Safety | cached Candidate carries an uncommitted self ballot | 1, 4 |
| `CertifiedLeaderHasFrozenQuorum` | Safety | locally certified leadership has a majority in every frozen config component | 3, 4 |
| `MembershipAtMostOneOutstanding` | Safety/structural | committed/effective membership positions differ by at most one log | 3, 5 |
| `DurableLogNotAhead` | Safety/structural | durable log cannot exceed projected last log | 4, 5 |

## 6. Findings pending verification

This neutral prior contains no incident-derived or revision-derived findings.
The properties above are general exact-old conformance questions and are checked
by the ordinary bounded reference configuration. Per the V0 completion rule,
no target-specific bug-hunting campaign or expected outcome is included.

### 6.1 Model-checkable

None beyond the neutral property set in section 5.

### 6.2 Test-verifiable

The fresh harness reuses exact engine operations for election start, vote guard
accept/reject, quorum establishment, membership append/commit, and startup.

### 6.3 Code-review-only

None recorded for this neutral prior.

## 7. Reference pointers

- Detailed source audit: `analysis-report.md`
- Spec: `spec/base.tla`, `spec/MC.tla`, `spec/Trace.tla`
- Trace mapping: `spec/instrumentation-spec.md`
- Primary sources: `openraft/src/engine/engine_impl.rs`,
  `openraft/src/engine/handler/vote_handler/mod.rs`,
  `openraft/src/core/raft_core.rs`,
  `openraft/src/raft_state/membership_state/mod.rs`, and
  `openraft/src/proposer/candidate.rs`
