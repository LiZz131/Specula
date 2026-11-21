# Modeling Brief — OpenRaft exact-old election prior

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

---

# V1 update (Pre-Vote revision) — incremental modeling brief

Disposition: **MODEL_CHANGE_REQUIRED** (see `analysis-report.md` §U.2-U.3).
Category unchanged (A). Granularity unchanged: one Engine event per action;
runtime command completion (vote persistence, RPC dispatch) stays split.

## Update scenarios

### U-S1: Pre-Vote request purity and guard order
- **Mechanism**: `handle_pre_vote_req` judges lease (no transfer bypass), last
  log, then `req.vote >= vote`, mutates nothing; RaftCore answers at once.
- **Evidence**: `engine_impl.rs:406-447`, `raft_core.rs:1551-1562`,
  `pre_vote.md:31-38`, `handle_pre_vote_req_test.rs`.
- **Model**: `HandlePreVoteRequest`; property `Update!PreVoteRequestPure`.
- **Traces**: `pre_vote_req_{grant,reject_lease,reject_log,reject_vote}`.

### U-S2: Pre-Vote quorum starts the real election
- **Mechanism**: `pre_elect` (self grant, self-quorum shortcut) → `SendPreVote`
  → `PreVoteResponse` correlation → `grant_by` → `elect()`.
- **Evidence**: `engine_impl.rs:298-322,516-554`, `raft_core.rs:1803-1820,2066-2090`.
- **Model**: `PreElect`, `SendPreVoteRequest`, `HandlePreVoteResponse`, `DoElect`;
  properties `PreCandidateVoteIsNextTerm`, `PreVoteElectsProbedVote`.
- **Traces**: `pre_elect_{multi,single}`, `pre_vote_resp_quorum`,
  `pre_vote_resp_reject_greater_log`.

### U-S3: Cancellation of the round by old context
- **Mechanism**: `do_elect` and `become_following` clear `pre_candidate`
  (vote-request grant, AppendEntries, rejected-vote adoption, refresh);
  restart rebuilds the Engine; the runtime drops responses with no matching
  pre-candidate.
- **Model**: `PreVoteCleared(If)` in `DoElect`, `HandleVoteRequest`,
  `HandleVoteResponse`, `HandleAppendEntries`, `RefreshServerState`, `Restart`.
- **Traces**: `pre_vote_superseded_by_{vote_req,append,elect}`.

### U-S4: Pre-Vote round × leader establishment (interaction)
- **Mechanism**: tick fires on a Candidate (tick skips only Leaders) →
  `pre_elect` keeps the live candidate; the candidacy then wins
  (`establish_leader` keeps `pre_candidate`) → the stale round's quorum calls
  `elect()` on the Leader; the leader object survives with a lower committed
  vote than `state.vote`.
- **Evidence**: `raft_core.rs:1964-2035`, `engine_impl.rs:298-322,516-554,855-881,968-982`,
  `vote_handler/mod.rs:154-162`; requirements `pre_vote.md:3-5,14-20`,
  `trigger.rs:47-56`, `raft_core.rs:1964-1969`.
- **Model**: `PreVoteNeverDemotesLeader` (consequence), `NoStalePreCandidateAtLeader`
  (precursor); hunt `Update-hunt-stale-precandidate.cfg`.
- **Trace**: `candidate_pre_vote_then_leader` (5 engine events + debug-assert
  observation).
- **Priority**: High (only update interaction that changes an existing role
  invariant boundary).

## Proposed update properties

| Property | Kind | Scenario | Decision |
|---|---|---|---|
| `PreCandidateVoteIsNextTerm` | state | U-S2/U-S3 | add |
| `PreVoteElectsProbedVote` | action | U-S2 | add |
| `PreVoteRequestPure` | action | U-S1 | add |
| `PreVoteNeverDemotesLeader` | action | U-S4 | add (bug candidate) |
| `NoStalePreCandidateAtLeader` | state | U-S4 | add (precursor) |
| `TypeOK` | structural | all | modify (new state/message kinds) |
| `VoteRequestAfterDurable`, `GrantedResponseAfterDurable`, `CandidateRoleHasPendingSelfVote`, `LeaderRoleHasCommittedSelfVote`, `NoForgedMessageEndpoints`, `DurableLogNotAhead` | safety | affected (new message kinds / helper repair) | keep |

Evidence: `spec/invariant-evidence.json`.

## Code-review scenarios (no MC counterexample)

- CR-review-1 (dismissed): same-term pre-vote rounds share a leader id, so a
  delayed earlier-round grant is counted; judged equivalent to a delayed
  in-round grant (analysis-report §U.5). No finding.
- CR-review-2 (documentation only): `pre_vote.md` backward-compatibility text
  contradicts the implemented `Unreachable`-is-not-a-grant rule. No
  behavioural finding.

## Exclusions (update)

Tick rate limiting and RPC timeouts (timing), metrics/name tables, config
parsing, the default network `pre_vote` synthesized grant (transport),
serialization.

## V1 outcome

- U-S4 produced model-checking finding **MC-1** (`spec/bug-report.md`,
  `spec/findings.json`); the precursor and consequence are reached over the
  complete `MCNext`, and the same sequence was executed and validated on the
  real Engine (`traces/candidate_pre_vote_then_leader.ndjson`).
- U-S1..U-S3: no violation within the bounded campaigns (LIMITED_COVERAGE).
