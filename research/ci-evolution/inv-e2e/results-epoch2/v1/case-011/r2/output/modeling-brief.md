# Modeling Brief — OpenRaft election model, updated for the Pre-Vote revision

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

# Update: Pre-Vote revision (incremental run `incr-315482ff25a1`)

## U.0 Inputs and disposition

- Old source: `/work/old-source` (changed-file snapshot) = artifact commit `1adc857` (`baseline`).
  New source: `/work/new-source` = artifact commit `3ab6cdd` (`update`); 39 changed files, 1283+/80-.
- Category: unchanged, **Category A** (single-mutator engine, asynchronous RPC/storage). The update adds
  one RPC kind and one engine-side round object; it does not change the concurrency architecture.
- **Disposition: `MODEL_CHANGE_REQUIRED`.** The update adds modeled state (`Engine.pre_candidate`),
  two message kinds (Pre-Vote request/response), new Actions (`pre_elect`, `handle_pre_vote_req`,
  `handle_pre_vote_resp`), changes the guard of the existing election tick, and changes the effects of
  existing Actions (`do_elect` and `become_following` now drop the round). Projection evidence is in
  `analysis-report.md` §U.

## U.1 Scenarios

### Scenario U-1: Pre-Vote is a side-effect-free probe
**Mechanism**: `pre_elect` builds a hypothetical `(term+1, self, uncommitted)` vote, freezes effective
membership and last log in a `Candidate` stored in `pre_candidate`, self-grants, and queues only
`SendPreVote`; peers answer with the real-vote rules (lease, last-log, vote order) without any state
change; the requester tallies grants.
**Evidence**: `openraft/src/engine/engine_impl.rs:144-165,291-322,406-447,511-554`;
`openraft/src/core/raft_core.rs:1385-1478,1551-1562,1803-1820,2066-2090`; docs
`openraft/src/docs/protocol/pre_vote.md:1-50`; tests `engine/tests/pre_elect_test.rs`,
`handle_pre_vote_req_test.rs`, `handle_pre_vote_resp_test.rs`.
**Model**: `PreElect`, `TickPreElect`, `ExternalPreElect`, `HandlePreVoteRequest`,
`HandlePreVoteResponse{Elect,Tally,Reject,Stale}`. Properties `PreCandidateTermUnbumped`,
`PreVoteMessagesWellFormed`; trace checks of purity (post = pre) on every query.
**Priority**: High.

### Scenario U-2: Pre-Vote round lifetime across elections and leadership
**Mechanism**: the round is dropped by `do_elect` (`engine_impl.rs:263-264`), by
`become_following` (`vote_handler/mod.rs:241-244`), and by restart; it is **not** dropped by
`establish_leader`/`become_leader` (`engine_impl.rs:855-881`, `vote_handler/mod.rs:171-229`). A Candidate
whose election timer fires starts a round (`raft_core.rs:1966` only skips a Leader) while its real
election is still in flight; if that election wins, the Leader keeps the round, and a later granted
Pre-Vote response makes it call `elect()` (`engine_impl.rs:534-539`).
**Path**: old context (Candidate) -> `PreElect` -> old consumer `HandleVoteResponse` (wins) ->
affected `HandlePreVoteResponseElect` -> `DoElect` from a Leader.
**Uncertainty**: whether this is reachable through the runtime and whether a property promised by the
source is violated.
**Model**: interaction actions `MCDeliverVoteResponse`, `MCDeliverVoteRequest`,
`MCDeliverAppendEntries`, `MCRefreshServerState`, `MCRestart`; properties
`PreVoteElectionPremiseCurrent`, `PreVoteNeverDisplacesLeader`, `EstablishedLeaderHasNoInheritedPreVote`.
**Priority**: High.

### Scenario U-3: Pre-Vote quorum feeds the unchanged real election
**Mechanism**: a quorum runs the ordinary `elect()` from the *current* vote and *current* effective
membership; single-voter self-quorum short-circuits to `elect()`.
**Evidence**: `engine_impl.rs:308-315,534-539,262-289`.
**Model**: `DoElect` shared by `StartElection`, `PreElect` (self quorum) and
`HandlePreVoteResponseElect`; old properties `CandidateRoleHasPendingSelfVote`,
`VoteRequestAfterDurable`, `GrantedResponseAfterDurable`, `DurableVoteNotAhead` keep checking the
election it starts.
**Priority**: Medium.

### Scenario U-4: Trigger, runtime flag, and transport semantics
**Mechanism**: the tick runs Pre-Vote only for multi-voter nodes with the runtime flag set (togglable at
runtime); `Trigger::elect(true)` runs it for any voter, any role; a transport error is not a grant, and
the default `pre_vote` network implementation synthesizes a grant.
**Evidence**: `raft_core.rs:1959-2036,1683-1695,1385-1478`; `network/v2/network.rs:141-161`;
`config/config.rs:397-427`; `raft/runtime_config_handle.rs:46-53`.
**Model**: `TickPreVoteModes = {FALSE, TRUE}` (per-tick choice over-approximates runtime toggling);
`TickPreElect` requires the vote lease to be expired (the tick's election-timeout check implies it);
transport errors are message loss (`DropMessage`); default-grant networks are an environment choice
outside the bounded model (a responder still answers through `HandlePreVoteRequest`).
**Priority**: Medium.

### Scenario U-5: Round identity across rounds started from the same vote
**Mechanism**: RaftCore correlates a Pre-Vote response only by the pre-candidate leader id
(`raft_core.rs:2067-2090`), which is identical for every round started from the same local vote, while each
round freezes its own voter set (`engine_impl.rs:149-165`, `proposer/candidate.rs:66-82`).
`handle_pre_vote_resp` passes any matching grant to `grant_by`, which `expect`s the granter to be in the
round's quorum set (`proposer/candidate.rs:106-107`).
**Path**: changed Action (round 1) -> old Action (membership change; follower: AppendEntries drops round 1)
-> changed Action (round 2, same key, new voters) -> stale round-1 grant from a removed voter.
**Model**: `HandlePreVoteResponseNonMember` (RaftCore panic = node stops), property
`PreVoteGrantFromRoundMember` / `NoPanicOnStalePreVoteGrant`; hunts `Update_hunt_stale_membership*.cfg`.
**Priority**: High.

## U.2 Modeling recommendations

- Model: pre-candidate vote/config/grants; Pre-Vote request/response messages whose `vote` field is the
  requester's pre-vote (the runtime correlation key; the responder's own vote in the RPC body is never
  consumed); pre-candidate clearing at every `do_elect`/`become_following`/restart site.
- Atomicity: `SendPreVote` needs no I/O wait and is executed in the same command drain, so request
  emission is atomic with `pre_elect`; delivery delay/loss is the network's.
- Do not model: precise timeouts and the in-flight-round rate limiter (time abstracted), metrics, the
  `RaftMsgName`/`CommandName` index renumbering, tracing spans, clap parsing.

## U.3 Update properties

| Property | Kind | Scenario | Location |
|---|---|---|---|
| `PreVoteElectionPremiseCurrent` | action safety | U-2 | `Update.tla` |
| `PreVoteNeverDisplacesLeader` | action safety (consequence) | U-2 | `Update.tla` |
| `EstablishedLeaderHasNoInheritedPreVote` | state safety (early form) | U-2 | `Update.tla` hunt |
| `PreCandidateTermUnbumped` | state safety | U-1 | `Update.tla` |
| `PreVoteMessagesWellFormed` | structural | U-1 | `Update.tla` |
| `PreVoteGrantFromRoundMember` / `NoPanicOnStalePreVoteGrant` | state / action safety | U-5 | `Update.tla` |
| reachability canaries | witness | U-1..U-3 | `Update_canary_*.cfg` |

## U.4 Defect ledger (update)

| ID | Description | Verification | Status |
|---|---|---|---|
| D-U1 | A Pre-Vote round started while Candidate survives leader establishment; a later granted Pre-Vote response makes the freshly established Leader run `elect()` at term+1 | MC (`Update_full.cfg`, `Update_hunt_stale_round.cfg`) + engine trace `traces/pre_vote_after_establish.ndjson` | MC-1 REPRODUCED (`spec/confirmation-MC-1.md`) |
| D-U2 | `docs/protocol/pre_vote.md` "Backward compatibility" says the default `pre_vote` returns `Unreachable` and that `Unreachable` counts as a grant; code returns `Ok(granted)` by default and never counts an `Err` as a grant (`network/v2/network.rs:141-161`, `raft_core.rs:1459-1471`, test `t12_pre_vote.rs::pre_vote_unreachable_peer_is_not_a_grant`) | CR (documentation only; no protocol consequence) | FALSE POSITIVE as an implementation defect (`spec/confirmation-CR-1.md`); doc fix recommended |
| D-U3 | A delayed Pre-Vote grant for an earlier round from a node that is not a voter of the current round (same correlation key, voter set changed) reaches `grant_by`'s `expect` and panics RaftCore | MC hunt `Update_hunt_stale_membership*.cfg` + integration reproduction | MC-2 REPRODUCED (`spec/confirmation-MC-2.md`) |
