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

# Update brief: Pre-Vote revision

Category remains **A (distributed/message-passing)**. Disposition:
**`MODEL_CHANGE_REQUIRED`** (evidence: `analysis-report.md` §U.1–U.2). The
V0 sections above remain valid except where amended here. No fairness is
assumed; no liveness property is claimed.

## U-Scenarios

### Scenario U1: Pre-Vote round lifecycle
**Mechanism**: a voter probes `(term+1, self)` with no state change, peers
answer with the vote-request lease/log/vote rules without state change, and a
frozen-membership quorum of grants triggers `Engine::elect()`.
**Evidence**: `engine/engine_impl.rs:291-322,406-447,512-554`;
`core/raft_core.rs:1385-1478,1551-1562,1803-1820,2010-2036`;
`pre_vote.md:28-49`; tests `pre_elect_test.rs`, `handle_pre_vote_req_test.rs`,
`handle_pre_vote_resp_test.rs`.
**Model**: `preCandidate*`/`preGrants` variables; `PreElect` (atomic
SendPreVote broadcast), `TickPreVote`, `ExternalPreElect`,
`HandlePreVoteRequest`, `HandlePreVoteResponse{Ignored,Grant,Elect,Reject}`,
`DoElect`. **Priority**: High.

### Scenario U2: Stale Pre-Vote round outlives the node's own election win
**Mechanism**: `pre_elect` on a timed-out Candidate keeps its real candidate;
a late real vote quorum makes it Leader via `establish_leader`/`become_leader`
which never drop `pre_candidate`; later Pre-Vote grants for that round still
pass the leader-id filter and `handle_pre_vote_resp` calls `elect()`.
Sub-case U2b: rounds restarted at an unchanged term share the probe leader id,
so earlier-round grants count.
**Evidence**: `engine_impl.rs:298-322,534-540,855-881`;
`vote_handler/mod.rs:154-162,173-229,234-249`; `raft_core.rs:2010-2036,
2040-2090`. **Model**: `HandleVoteResponse` keeps `preVars` on `wins`;
history bit `preRoundFromLeader`. **Property**:
`Update!PreVoteRoundNotOutlivedByOwnLeadership`. **Priority**: High.

### Scenario U3: Frozen pre-candidate membership vs. current membership
**Mechanism**: voter check happens when the round starts; `elect()` after the
quorum re-reads the effective membership without re-checking. Only a node
whose vote names itself can change membership while holding a round.
**Evidence**: `raft_core.rs:1683-1696,1971-1974`; `engine_impl.rs:149-165,
262-289,534-540`. **Properties**: `Update!PreVoteElectionByVoter` (status
unknown), `Update!PreVoteGrantFromTrackedVoter` (diagnostic).
**Priority**: Medium.

### Scenario U4: Old actions cancel the round (become_following)
**Mechanism**: real vote grant to another node, adopted higher response vote,
AppendEntries/heartbeat contact, refresh to follower/learner, restart, and
`do_elect` drop `pre_candidate`; Pre-Vote requests and rejected requests do
not. **Evidence**: `vote_handler/mod.rs:106-162,234-249`;
`engine_impl.rs:262-264,586-600`. **Properties**:
`Update!PreVoteElectionAtProbedVote`, V0 role/vote properties.
**Priority**: High.

### Scenario U5: Network default grant and single-voter shortcut
**Mechanism**: a network without `pre_vote` synthesizes grants; a single
voter's self-grant elects at once (`pre_elect` → `elect`).
**Evidence**: `network/v2/network.rs:141-161`; `engine_impl.rs:309-315`;
`raft_core.rs:2010-2012`. **Model**: `DefaultPreVoteRpcGrant`
(`PreVoteRpcDefaultGrant`), `PreElect` quorum branch. **Priority**: Medium.

## U-Modeling recommendations

Model: everything in U1–U5 at the V0 granularity (one engine call = one
action; SendPreVote fan-out atomic with `pre_elect` because it executes in
the same command batch and persists nothing). Tick mode is the constant
`PreVoteTickModes` (`{FALSE}` default, `{TRUE}` enabled, `{FALSE,TRUE}`
runtime toggle). Do not model: round rate-limit timing, RPC timeouts,
randomized timeouts, metrics, runtime-config memory ordering, `RaftNetwork`
v1 adapter.

## U-Proposed invariants / properties (Update.tla)

| Property | Kind | Status | Scenario |
|---|---|---|---|
| `PreVoteRoundNotOutlivedByOwnLeadership` | action | requirement | U2 |
| `PreVoteElectionByVoter` | action | unknown | U3 |
| `PreVoteElectionAtProbedVote` | action | requirement | U1, U4 |
| `PreVoteRequestIsPure` | action | requirement | U1 |
| `PreVoteStartIsPure` | action | requirement | U1 |
| `PreVoteGrantFromTrackedVoter` | action | model-internal (diagnostic) | U2b, U3 |
| V0 safety set (`DurableVoteNotAhead` … `CertifiedLeaderHasFrozenQuorum`) | invariant | kept (controls) | all |

## U-Defect ledger

| ID | Location | Trigger | Wrong behavior | Evidence | Category | Verification | Scenario | Known |
|----|----------|---------|----------------|----------|----------|--------------|----------|-------|
| D-1 (→ MC-1, confirmed) | `openraft/src/engine/engine_impl.rs:855-881,534-540`; `vote_handler/mod.rs:173-229` | Candidate's tick starts a Pre-Vote round; a late real vote quorum makes it Leader; Pre-Vote grants for that round then arrive | `handle_pre_vote_resp` calls `elect()` on the established Leader: it abandons its term, bumps to `term+1`, becomes Candidate while followers hold its lease | §U.4; `establish_leader`/`become_leader` never clear `pre_candidate` | protocol | MC | U2 | none |
| D-2 | `openraft/src/engine/engine_impl.rs:534-540`; `core/raft_core.rs:1683-1696` | node holding a round (leader path) is removed from voters before the quorum arrives | `elect()` runs for a non-voter (voter check only at trigger time) | §U.4 | protocol | MC | U3 | none |
| D-3 | `openraft/src/docs/protocol/pre_vote.md:57-63` | reader follows the doc | doc says default `pre_vote` returns `Unreachable` and `Unreachable` counts as a grant; code synthesizes a grant and never counts transport errors | `network/v2/network.rs:141-161`; `raft_core.rs:1459-1471`; `t12_pre_vote.rs:231-272` | low-level | CR | U5 | none |
| D-4 | `openraft/src/core/raft_core.rs:2067-2090`; `proposer/candidate.rs:106-112` | two rounds at an unchanged term (e.g. back-to-back `trigger().elect(true)`), responses of the first arrive during the second | earlier-round grants are counted; a grant from a node not tracked by the later round's membership hits `expect("target not in quorum set")` | leader-id-only filter; RPC ttl bounds delay only relative to tick restarts | protocol | CR | U2b | none |

### U-Defect ledger status after Validation/Model Checking

- D-1 → **MC-1**: model-checking counterexample + validated trace + real-runtime reproduction (debug panic / release demotion). See `spec/bug-report.md`.
- D-2: `PreVoteElectionByVoter` (status `unknown`) violated in the membership/single-voter hunts (`spec/output/D-2_*.out`); unresolved (no non-implementation requirement evidence).
- D-3: code review only (documentation mismatch); unchanged.
- D-4 → **MC-2**: `PreVoteGrantFromTrackedVoter` violated without crashes (`spec/output/MC-2_cross_round_grant_violation.out`); real-runtime panic at `proposer/candidate.rs:107` (`spec/output/repro-D-4-new.log`).
- CR-PRE-1 (new, pre-existing in both revisions): operator `trigger().elect()` on the Leader keeps a Leader object behind the vote; RaftCore panics (`spec/output/control-elect-on-leader-{old,new}.log`).
