# Modeling Brief — OpenRaft election, incremental update: Pre-Vote

## 0. Incremental update summary (this run)

- **Revisions**: old = synthetic `baseline` (`1adc857`), new = synthetic `update`
  (`3ab6cddc34a5bf127747434bb41e20a1b9ef7769`) in `artifact/`. Prior suite:
  `/work/previous/.specula-output` (exact-old V0, LIMITED_COVERAGE, no findings).
- **Category**: unchanged, Category A (distributed / message-passing). The update
  adds a new RPC (`RaftNetworkV2::pre_vote`), a new engine phase (Pre-Vote) and a
  new volatile tracker (`Engine::pre_candidate`); it does not change the
  single-mutator RaftCore / async IO architecture.
- **Decision gate (Chapter 1)**: `MODEL_CHANGE_REQUIRED`. The update changes
  modeled behavior: a new message pair, new enabled transitions that end in the
  existing election action (`elect()`), a new branch of the election timer, and new
  side effects of existing actions (`do_elect` and `become_following` drop the
  tracker; `establish_leader` keeps it). Branch projections are in
  `analysis-report.md` section "Incremental update".
- **Granularity**: the Pre-Vote round is modeled at the same engine/RaftCore event
  granularity as V0. `SendPreVote` is emitted in the same step as `pre_elect`
  (the command has no IO condition and is drained right after the engine event);
  delay/reorder/loss stay in the message set.
- Line numbers in the V0 sections below refer to the exact-old tree; update
  sections cite the new tree (`artifact/` at `3ab6cdd`).

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


### Update Scenario U1: Timer Pre-Vote gates term increase

**Mechanism**: with `enable_pre_vote`, a multi-voter node whose election timer
fires runs `pre_elect` instead of `elect`: no term bump, no SaveVote, no role
change; only a would-grant quorum of its frozen config calls `elect()`.

**Evidence**: `raft_core.rs:1959-2036` (handle_tick_election: Leader/voter/enable_elect
guards, single-voter direct elect, timeout expiry, `pre_vote = flag && voter_count > 1`,
in-flight round skip, reset_greater_log); `engine_impl.rs:291-322` (pre_elect);
`engine_impl.rs:526-541` (quorum -> elect); `config.rs` (`enable_pre_vote`,
default `None` -> disabled); `runtime_config.rs` (AtomicBool, toggled at run time).

**Modeling**: `TickPreElect`, `PreElect`, `PreVoteSetting` in {Disabled, Enabled,
Runtime}; property `SelfTermIncreaseNeedsPreVoteQuorum` (Enabled, no operator
direct elections); `PreElectLeavesVoteUnchanged`.

**Priority**: High (the update's stated purpose).

### Update Scenario U2: Pre-Vote round lifecycle vs real election and leadership

**Mechanism**: the timer skips only a cached Leader. A Candidate whose real election
has outlived the election timeout starts a Pre-Vote round for the next term while
its real election is still live. `do_elect` and `become_following` drop the
tracker, but `establish_leader -> update_vote -> become_leader` does not. A delayed
grant for that round reaches `handle_pre_vote_resp`, which calls `elect()` with no
role check, so a freshly established Leader starts a new election.

**Evidence**: `raft_core.rs:1966-1969` (Leader skip only), `raft_core.rs:2014-2024`
(round skip only while fresh), `engine_impl.rs:262-264` (do_elect clears),
`vote_handler/mod.rs:154-162,172-229,234-249` (become_leader keeps, become_following
clears), `engine_impl.rs:855-881` (establish_leader), `engine_impl.rs:526-541`,
`raft_core.rs:1803-1820,2066-2090` (filter checks only tracker presence and leader id),
`engine_impl.rs:967-982` (try_leader_handler debug_assert leader.vote >= state.vote).

**Modeling**: tracker kept on `HandleVoteResponse` win; `HandlePreVoteResponse`
quorum -> `DoElectCore`; ghost `preCandidateByTick`; property
`TickPreVoteNeverDeposesLeader`; canary `CanaryNoLeaderWithTickPreRound`.

**Priority**: High.

### Update Scenario U3: Responder guards and read-only handling

**Mechanism**: `handle_pre_vote_req` rejects under an unexpired committed lease
(never a transfer), then on a smaller candidate log, then grants iff
`req.vote >= my vote`; no state, lease, or command change; the reply is sent at
once (`Respond { when: None }`).

**Evidence**: `engine_impl.rs:406-447`, `raft_core.rs:1551-1562,1603-1607`.

**Modeling**: `HandlePreVoteRequest`; properties `PreVoteRequestIsReadOnly`;
canaries `CanaryNoLeaseRejectedPreVote`, `CanaryNoRejectedPreVoteResponse`.

**Priority**: Medium-High.

### Update Scenario U4: Cancellation and recovery of the tracker

**Mechanism**: the tracker is dropped by `do_elect` (any real election), by
`become_following` (granting another node's vote, AppendEntries from another
leader, membership-driven refresh, adopting a higher vote from a vote response),
and by crash/restart (`Engine::new`). A later delayed response is then ignored.

**Evidence**: `engine_impl.rs:117,262-264`, `vote_handler/mod.rs:234-249`,
`raft_core.rs:1803-1820`.

**Modeling**: `PreClearIf` in the listed reference Actions; canaries
`CanaryNoPreVoteCancelledByFollowing`, `CanaryNoPreVoteAfterRestart`; invariant
`PreVoteProbeIsNextTerm`.

**Priority**: Medium.

### Update Scenario U5: Frozen Pre-Vote quorum vs membership evolution

**Mechanism**: `new_pre_candidate` freezes the effective (possibly joint)
membership; requests go to the effective voters at dispatch time; a joint quorum
needs a majority in every component. Membership can change while a round runs.

**Evidence**: `engine_impl.rs:144-165`, `raft_core.rs:1384-1394`,
`quorum_set_impl.rs:31-45`.

**Modeling**: `preCandidateConfig`, `IsQuorum`; hunt cfg
`MC_hunt_prevote_membership.cfg`; canary `CanaryNoJointPreVoteRound`; open
focused check with `EnvUpdate` for membership context.

**Priority**: Medium.

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

- Update: the volatile Pre-Vote tracker, `PreVoteReq`/`PreVoteResp` messages, the
  timer/external Pre-Vote branches, and every tracker-clearing path (U1-U5).

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
| Pre-Vote tracker (update) | `preCandidateActive`, `preCandidateVote`, `preCandidateConfig`, `preGrants`, ghost `preCandidateByTick` | model `Engine::pre_candidate` and its lifecycle | U1-U5 |
| Pre-Vote messages (update) | `messages` kinds `PreVoteReq`, `PreVoteResp` | asynchronous Pre-Vote RPC with delay/loss | U1-U3 |
| Runtime flag (update) | constant `PreVoteSetting` | default-disabled, enabled, or runtime-toggled timer branch | U1 |

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
| `TickPreVoteNeverDeposesLeader` (update) | Safety (action) | a timer-started Pre-Vote round never makes a node that is Leader start an election | U2 |
| `SelfTermIncreaseNeedsPreVoteQuorum` (update) | Safety (action) | with Pre-Vote enabled and no operator direct election, a self term increase needs a would-grant quorum or a single voter | U1 |
| `PreVoteRequestIsReadOnly` (update) | Safety (action) | handling a Pre-Vote request changes no vote, durable vote, role, lease, or persistence | U3 |
| `PreElectLeavesVoteUnchanged` (update) | Safety (action) | starting a round changes neither vote nor role | U1 |
| `PreVoteProbeIsNextTerm` (update) | Interaction invariant | a live round always probes `vote.term + 1` of the node's current vote | U2, U4 |
| `PreVoteTrackerWellFormed` (update) | Structural | the tracker contains its own grant and only voters of its frozen config | U5 |

## 6. Findings pending verification

The V0 prior had no findings. This run's defect ledger:

| ID | Defect | Verification | Status in this run |
|---|---|---|---|
| D-1 / MC-1 | A Pre-Vote round started while the node is still a Candidate survives `establish_leader`; a delayed grant makes the new Leader call `elect()`; in debug builds RaftCore then panics (`try_leader_handler` debug_assert) | MC (`TickPreVoteNeverDeposesLeader`) + trace + engine/integration tests | MC counterexample; reproduced on the updated implementation (see `spec/bug-report.md`) |
| D-2 / CR-1 | A rejected Pre-Vote never carries the responder's higher term back to the requester (`handle_pre_vote_resp` never updates the vote). A live majority whose freshest log sits at a stale term cannot pass Pre-Vote while higher-term peers fail the log check: permanent leaderless stall (e.g. 3 of 5 voters alive); the direct-election path adopts the higher term and recovers | CR + engine-level simulation (`specula_repro_pre_vote_term_stall*`, control `specula_control_direct_election_progresses`) + 5-node integration test `t94` with control | Code-review, reproduced end-to-end (`spec/code-review-CR-1.md`); not model-checkable at the current granularity (followers never receive log entries in the model, and AppendEntries rejection / HigherVote step-down are not modeled) |
| D-3 / CR-2 | `docs/protocol/pre_vote.md` says the default `pre_vote` returns `Unreachable` and that `Unreachable` counts as a grant; the code synthesizes a granted response by default and never counts `Err` (incl. `Unreachable`) as a grant | CR (documentation) | Documentation inconsistency; no protocol effect beyond misleading implementors |
| D-4 (lineage) | `do_elect` on a node that holds a Leader object keeps `self.leader` (update_internal_server_state: is_leading -> no-op), after which `try_leader_handler` asserts `leader.vote >= state.vote` | CR | Pre-existing mechanism, reachable before only through an operator `trigger().elect()` on a Leader; D-1 makes it reachable from the election timer |
| D-5 / MC-2 | Pre-Vote rounds at one term reuse the leader id `(term+1, self)` and RaftCore's filter compares only the leader id, so a delayed grant of an earlier round is counted in a later round. If the granter is no longer in the later round's frozen config (membership change in between), `Candidate::grant_by` hits `expect("target not in quorum set")` and RaftCore panics (also in release builds) | MC structural invariant `PreVoteTrackerWellFormed` (leader variant, `MC_hunt_prevote_stale_grant*.cfg`) + engine/integration tests | Reproduced on the updated implementation (engine test and integration test `t93`, follower variant with operator `Trigger::elect(true)` twice across a membership change; the timer cannot reach it because a timer round restarts only after the RPC timeout). MC counterexample over the complete MCNext (simulation of `Update-full-noU2.cfg`). See `spec/reproduction-MC-2.md` |

### 6.1 Model-checkable

D-1 / MC-1 (Scenario U2) and D-5 / MC-2 (Scenario U5, leader variant), with U1/U3/U4 properties as regression guards.

### 6.2 Test-verifiable

D-1 (engine + integration tests, harness `instrumentation.patch`); D-2 (engine-level multi-engine simulation and 5-node integration test `t94`).

### 6.3 Code-review-only

D-2 (outside the model's log abstraction), D-3, D-4 lineage; D-5 follower variant (followers never change config in the model).

### 6.4 Exclusions for the update

- Network adapters without `pre_vote` (default synthesized grant): modeled only as
  an ordinary granted response; transport adapters are out of scope.
- `ExternalCommand::Elect` naming/metrics changes (`raft_msg_name.rs`,
  `notification_name.rs`, `command_name.rs`), clap parsing, docs: no modeled effect.
- Changed integration tests other than `t12_pre_vote.rs` only rename
  `trigger().elect()` to `elect(false)`.

## 7. Reference pointers

- Detailed source audit: `analysis-report.md`
- Spec: `spec/base.tla`, `spec/MC.tla`, `spec/Trace.tla`, `spec/Update.tla`
- Trace mapping: `spec/instrumentation-spec.md`
- Primary sources: `openraft/src/engine/engine_impl.rs`,
  `openraft/src/engine/handler/vote_handler/mod.rs`,
  `openraft/src/core/raft_core.rs`,
  `openraft/src/raft_state/membership_state/mod.rs`, and
  `openraft/src/proposer/candidate.rs`
