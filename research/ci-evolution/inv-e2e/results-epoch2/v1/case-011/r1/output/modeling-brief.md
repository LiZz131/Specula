# Modeling Brief — OpenRaft election, incremental revision (Pre-Vote)

> **Incremental run (case-011).** Prior suite: `/work/previous/.specula-output`
> (V0, exact-old `1adc857` "baseline"). Current source: `artifact/` commit
> `3ab6cdd` "update". Disposition: **MODEL_CHANGE_REQUIRED** (Section 0).
> Sections 1–7 below are the V0 brief, kept where still valid and annotated
> where the update or a repair changed them; Section 8 holds the update
> Scenarios, properties and code-review candidates.

## 0. Update decision gate (Chapter 1)

The update adds an optional **Pre-Vote** phase in front of the real election.
Every changed behavioural branch was projected onto the V0 vocabulary
(vote, role, candidate state, effective config, last log, messages,
persistence flags, crash state):

| Changed branch (new source) | Projected effect on V0 vocabulary | Same post-state set? |
|---|---|---|
| `Engine::pre_elect` (`engine/engine_impl.rs:297-322`) | new per-node pre-candidate state; new `PreVoteReq` messages; single-voter self-quorum calls `elect()` | **No** – new messages/state; the tick no longer always reaches `StartElection` |
| `RaftCore::handle_tick_election` (`core/raft_core.rs:1958-2036`) | with `enable_pre_vote` and >1 voter the tick calls `pre_elect` instead of `elect` | **No** – changes enablement of the term bump |
| `Engine::handle_pre_vote_req` + `RaftCore::handle_pre_vote_request` (`engine_impl.rs:414-447`, `raft_core.rs:1551-1562`) | new `PreVoteResp` with lease/log/vote verdict; no local mutation | **No** – new message kind |
| `Engine::handle_pre_vote_resp` + `Notification::PreVoteResponse` (`engine_impl.rs:516-554`, `raft_core.rs:1803-1820,2066-2090`) | quorum of grants runs `elect()` (term bump, SaveVote, SendVote) | **No** – new path into the real election |
| `Engine::do_elect` (`engine_impl.rs:262-264`) | clears `pre_candidate` | **No** (new state) |
| `VoteHandler::become_following` (`vote_handler/mod.rs:242-244`) | clears `pre_candidate` | **No** (new state) |
| `ExternalCommand::Elect { pre_vote }`, `Trigger::elect(bool)` (`raft_core.rs:1683-1696`, `raft/trigger.rs:61-63`) | operator may start either path | **No** |
| `spawn_parallel_vote_requests(kind)` Vote path (`raft_core.rs:1385-1478`) | identical targets, timeout, notification for `Vote` | yes (log text only) |
| election-timeout arithmetic hoisted out of the multi-voter branch (`raft_core.rs:1981-1986`) | same value used by the same check | yes |
| `Config::enable_pre_vote`, `RuntimeConfig`, `RuntimeConfigHandle::pre_vote` | selects the tick branch (modeled as constant set `TickPreVoteModes`) | n/a (setup) |
| `RaftNetworkV2::pre_vote` default impl (`network/v2/network.rs:157-162`) | synthesised **grant** when the transport lacks `pre_vote` | excluded: the model assumes the RPC is implemented (see 8.5) |
| `Candidate::starting_time` (`proposer/candidate.rs:93-99`) | accessor for the timing rate limit | timing abstracted |
| command/notification/message names, metrics, docs, test API renames | none | yes |

Result: **MODEL_CHANGE_REQUIRED** – the update changes modeled behaviour
(new messages, new state, new enablement of the term bump) and introduces
new correctness requirements (Section 8.3).


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


## 8. Incremental update (Pre-Vote) — Scenarios, properties, candidates

### 8.1 Model changes (reference suite)

* New state `preActive/preVote/preConfig/preGrants` (= `Engine.pre_candidate`),
  message kinds `PreVoteReq/PreVoteResp`, message field `round` (the
  `candidate_vote` carried by `Notification::PreVoteResponse`).
* New actions `PreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`;
  `TickElect(i, pv)` chooses the Pre-Vote branch; `ExternalPreElect`;
  `StartElection` split into the entry guard plus `DoElect` (Engine::do_elect).
* `pre_candidate` cleared exactly where the source clears it: `DoElect`,
  every `become_following` (granting `HandleVoteRequest`, `HandleAppendEntries`
  from another leader, adopting `HandleVoteResponse`, non-leading
  `RefreshServerState`), and `Restart`. It is **kept** by `establish_leader`
  (`become_leader`) and by a candidate's own vote updates.
* Repairs of inherited V0 defects needed to verify the update (changelog R-1..R-4):
  follower log adoption on AppendEntries (R-1), log submission FIFO behind a
  pending SaveVote (R-2), tick only after the leader lease expired (R-3),
  leader lease installed at establishment (R-4).

### 8.2 Update Scenarios

**U-S1 — Pre-Vote gates the term bump.** old producer (election tick) →
affected `PreElect` / `HandlePreVoteRequest` / `HandlePreVoteResponse` → old
consumer (`DoElect`, `PersistVote`, `SendVoteRequest`).
Code: `raft_core.rs:2010-2035`, `engine_impl.rs:297-322,414-447,516-554`.
Uncertainty: does a quorum elect at the probed term; is the pre-candidate
correlated and cleared correctly. Properties: `PreCandidateProbesNextTerm`,
reference persistence/role invariants. Traces U-T1, U-T2, U-T7.

**U-S2 — Pre-Vote rejection never propagates a higher vote (liveness).**
old context (log recency from AppendEntries, an interrupted real election,
crash) → affected `HandlePreVoteResponse` (rejection ignores `resp.vote`) and
`HandlePreVoteRequest` (never updates the local vote) → no progress.
Code: `engine_impl.rs:542-553` ("A Pre-Vote response never updates the local
vote"), `engine_impl.rs:441-446`; contrast `handle_vote_resp`
`engine_impl.rs:485-509`, which adopts the higher vote. Plausible consequence:
a live voter majority in which the most up-to-date voter has the lowest term
can never assemble a Pre-Vote quorum. Requirement evidence:
`tests/tests/elect/t12_pre_vote.rs:188-197` ("Pre-Vote makes elections
*cautious*, not *impossible*: this is the core liveness requirement"),
`docs/protocol/pre_vote.md:47-49`; the documented responder rule is "lease, then
log, *otherwise it would grant*" (`docs/protocol/pre_vote.md:33-39`), whereas the
code additionally rejects a Pre-Vote whose vote is below the responder's
(`engine_impl.rs:441-446`). Property: `NoPermanentPreVoteLivelock`
with closure obligation `LivelockClosed`; hunt `MC_hunt_prevote_livelock.cfg`.
Trace U-T2 (requester ignores higher vote), U-T3 (responder rejects by vote
and by log without mutation).

**U-S3 — Stale pre-candidate survives leader establishment.** old
`HandleVoteResponse` (`establish_leader` → `become_leader`, which does not
clear `pre_candidate`) → affected `HandlePreVoteResponse` → `DoElect` on a
Leader. Code: `engine_impl.rs:855-881`, `vote_handler/mod.rs:154-230`,
`raft_core.rs:1966-1969,2010-2035` (a Candidate's tick runs `pre_elect`).
Plausible consequence: the newly established leader abandons leadership and
bumps the term. Requirement evidence: `docs/protocol/pre_vote.md:3-6,13-24`,
`config/config.rs:397-405`, tick never elects on a Leader
(`raft_core.rs:1966-1969`). Property `PreVoteQuorumNeverDemotesLeader`; hunt
`MC_hunt_prevote_leader_demote.cfg`; trace U-T4.

**U-S4 — Pre-candidate cancellation by old consumers.** old
`HandleAppendEntries` / granting `HandleVoteRequest` / adopting
`HandleVoteResponse` / `RefreshServerState` / `Restart` → `become_following`
clears `pre_candidate`. Traces U-T5, U-T6; canary `CanaryNoPreCandidateCleared`.

**U-S5 — Responder guards.** lease from AppendEntries/establishment (R-3/R-4)
and log recency (R-1) → affected `HandlePreVoteRequest`. Traces U-T3, U-T3d.

**U-S6 — Membership context.** effective-config evolution changes the voter
set read by `TickElect`/`PreElect` and frozen in `preConfig`. Omitted from the
concrete focused model; covered by `EnvUpdate` + `DischargeContext` and by the
full `MCNext` checks.

### 8.3 Update properties (Update.tla)

| Property | Kind | Scenario | Requirement evidence |
|---|---|---|---|
| `PreCandidateProbesNextTerm` | state, structural/update | U-S1 | `pre_vote.md:28-33,47-49` |
| `PreVoteQuorumNeverDemotesLeader` | action property | U-S3 | `pre_vote.md:3-6,13-24`; `config.rs:397-405`; `raft_core.rs:1966-1969` |
| `NoPermanentPreVoteLivelock` (+ `LivelockClosed`) | liveness witness encoded as safety + closure | U-S2 | `t12_pre_vote.rs:188-197`; `pre_vote.md:47-49` |

Reference properties kept (decisions in `spec/invariant-evidence.json`):
`VoteRequestAfterDurable`, `GrantedResponseAfterDurable` (Pre-Vote messages
deliberately not covered: `command.rs:138-142` says Pre-Vote persists
nothing), role/persistence invariants, `CertifiedLeaderHasFrozenQuorum`
(unaffected control). `TypeOK` modified (representation).

### 8.4 Code-review candidates

* **CR-A (documentation)** `docs/protocol/pre_vote.md:55-63` says the default
  `pre_vote` returns `Unreachable` and that `Unreachable` counts as a grant;
  the code (`network/v2/network.rs:143-162`, `raft_core.rs:1377-1384,1461-1470`)
  synthesises a grant and does not count transport errors, and the test
  `t12_pre_vote.rs:230-271` asserts the code's behaviour. Documentation-only;
  no protocol consequence in the model.
* Model-checking findings are listed in `spec/findings.json` / `spec/bug-report.md`.

### 8.5 Update exclusions

* Pre-Vote timing (`starting_time` rate limit, `election_timeout`,
  `smaller_log_timeout`): abstracted as "a later tick may restart a round".
* Default `RaftNetworkV2::pre_vote` synthesised grant: the model assumes the
  RPC is implemented. With the default, a peer always grants, which only
  makes Pre-Vote weaker (closer to the old behaviour).
* Transport errors / RPC timeouts: modeled as message loss (`DropMessage`).
* Metrics, names, logging, config parsing (`config_clap_test.rs`).
