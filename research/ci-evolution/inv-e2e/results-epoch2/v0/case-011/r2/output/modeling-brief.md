# Modeling Brief — OpenRaft election model, updated for the Pre-Vote revision

> Incremental update (run incr-b919e9f909ea): disposition **MODEL_CHANGE_REQUIRED**. Sections 1–7 are the prior V0 brief (still valid except where §8 revises them); §8 adds the update Scenarios, model changes, and properties. Detailed evidence: `analysis-report.md` §U.

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


## 8. Update: Pre-Vote (MODEL_CHANGE_REQUIRED)

### Scenario U1: Pre-Vote round start is side-effect free
**Mechanism**: `pre_elect` builds a pre-candidate for `(term+1, self)` and queues `SendPreVote`; no vote, role, lease, candidate or leader change. Single voter elects immediately.
**Evidence**: `engine_impl.rs: pre_elect, new_pre_candidate`; `raft_core.rs: handle_tick_election`; `engine/tests/pre_elect_test.rs`.
**Model**: `base!PreElect`, `TickPreElect`, `ExternalPreElect`; property `Update!PreVoteStepIsSideEffectFree`, `Update!PreCandidateTracksNextTerm`. **Priority**: High.

### Scenario U2: Pre-Vote grant rule honors the lease
**Mechanism**: lease (no transfer bypass) → last log → `req.vote >= local`; reply immediately, no state change.
**Evidence**: `engine_impl.rs: handle_pre_vote_req`; `raft_core.rs: handle_pre_vote_request`.
**Model**: `base!HandlePreVoteRequest`. **Priority**: High.

### Scenario U3: Pre-Vote round survives leader establishment (interaction)
**Mechanism**: a timed-out Candidate keeps its real election while pre-voting; winning it (`establish_leader`) keeps `pre_candidate`; a later granted Pre-Vote response passes the runtime gate and `handle_pre_vote_resp` calls `elect()` on the Leader; `do_elect` keeps the Leader object.
**Evidence**: `raft_core.rs: handle_tick_election` (skips only `ServerState::Leader`), `engine_impl.rs: pre_elect` (candidate untouched), `establish_leader` (takes only `candidate`), `handle_pre_vote_resp` (no role check), `do_elect`, `vote_handler/mod.rs: update_internal_server_state`, `engine_impl.rs: try_leader_handler` (debug_assert leader vote >= state vote).
**Model**: `base!HandleVoteResponse` (keeps `preCandidateActive`), `base!HandlePreVoteResponse`, `base!ElectEffect`; property `Update!LeaderVoteCoversLocalVote`; witness canaries `CanaryCandidateWithPreVoteRound`, `CanaryLeaderWithPreVoteRound`. **Priority**: High.

### Scenario U4: Cancellation by old consumers
**Mechanism**: `become_following` (vote grant to another node, AppendEntries from another leader, role refresh) and `Engine::new` (restart) drop the round; the runtime drops responses for an absent/different round.
**Model**: `HandleVoteRequest`, `HandleAppendEntries`, `RefreshServerState`, `HandleVoteResponse` adopt, `Restart`, gate in `HandlePreVoteResponse`. **Priority**: Medium.

### Scenario U5: Membership change during a round
**Model**: open spec `Update!OpenUpdateSpec` with `EnvUpdate` (coherent membership evolution on any node) + discharge `Update!DischargeEnv`. **Priority**: Medium.

### 8.1 Model changes
New variables `preCandidateActive/Vote/Config`, `preGrants`; message kinds `PreVoteReq`/`PreVoteResp` (response carries the request vote for correlation); constant `PreVoteSetting`; MC constants `MaxPreElectCount`, `AllowAdminElect`. Repairs of prior defects: `LogLE` on absent logs; leader lease on establishment.

### 8.2 Properties
| Property | Kind | Scenario | Where |
|---|---|---|---|
| `LeaderVoteCoversLocalVote` | interaction safety (implementation assertion) | U3 | `Update.tla`, `Update*.cfg` |
| `PreCandidateTracksNextTerm` | structural | U1 | `Update.tla` |
| `PreVoteStepIsSideEffectFree` | action property | U1, U2 | `Update.tla` |
| all prior invariants | preserved | — | `MC.cfg`, `Update*.cfg` |

### 8.3 Code-review Scenarios (no separate counterexample)
- CR-doc: `docs/protocol/pre_vote.md` claims `Unreachable` counts as a grant; code and tests treat transport errors as non-grants. Documentation-only.
