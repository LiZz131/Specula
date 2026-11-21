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

# Update section — Pre-Vote revision (incremental run)

## U.0 Inputs and identity

- Old source: `/work/old-source` (changed-file snapshot) = artifact commit `baseline` (1adc857).
- New source: `/work/new-source` (changed-file snapshot) = artifact commit `update` (3ab6cdd), the
  writable tree under `artifact/`.
- Prior suite: `/work/previous/.specula-output` (V0, exact-old), immutable. No prior findings,
  reproductions or unresolved warnings; prior coverage was `LIMITED_COVERAGE`.
- Category unchanged: **A (distributed / message-passing)**. The update adds one RPC kind and
  one engine state but no new concurrency or communication architecture.

## U.1 Decision gate (Chapter 1)

**Disposition: `MODEL_CHANGE_REQUIRED`.**

The update adds an optional Pre-Vote phase before elections. Projected onto the existing model
vocabulary, the following post-state sets change (old vs new):

| Changed branch | Old projected effect | New projected effect | Evidence |
|---|---|---|---|
| Election timer, multi-voter, `enable_pre_vote` observed true | `elect()`: vote := (t+1,self), SaveVote, SendVote, Candidate | `pre_elect()`: new pre-candidate (frozen vote/log/membership, self grant) and a `SendPreVote` broadcast; vote, role, lease, persistence unchanged | `core/raft_core.rs:2010-2035`, `engine/engine_impl.rs:297-322` |
| `ExternalCommand::Elect { pre_vote: true }` | (no such command) | `pre_elect()` after the `is_voter` check only | `core/raft_core.rs:1683-1696` |
| Incoming `RequestPreVote` | (no such message) | lease/log/vote checks, immediate response, **no state change** | `engine/engine_impl.rs:414-447`, `core/raft_core.rs:1551-1562` |
| `Notification::PreVoteResponse` | (none) | correlation by probed leader id; grant → tally → `elect()` at quorum; reject → greater-log flag | `core/raft_core.rs:1803-1820,2067-2090`, `engine/engine_impl.rs:516-554` |
| `do_elect` | — | additionally clears `pre_candidate` | `engine/engine_impl.rs:264` |
| `become_following` (all vote-update paths that follow another node, refresh) | clears leader/candidate | additionally clears `pre_candidate` | `engine/handler/vote_handler/mod.rs:244` |
| default `RaftNetworkV2::pre_vote` | — | synthesizes a granting response | `network/v2/network.rs:158-161` |

Changes outside the model scope (projection is unchanged): `Config`/clap parsing
(`config.rs`, `config_clap_test.rs`), name/index tables (`*_name.rs`), tracing spans, docs,
`Candidate::starting_time` accessor (used only by the timer rate limit, a timing abstraction),
test-fixture network plumbing, and the `Trigger::elect(bool)` signature change in tests.

## U.2 Update Scenarios

### Scenario U1: Pre-Vote round is side-effect free on both sides
**Mechanism**: `pre_elect` installs only `pre_candidate` and queues `SendPreVote`; `handle_pre_vote_req`
answers with the lease/log/vote rules of a real vote but mutates nothing and emits no command.
**Evidence**: `engine_impl.rs:297-322,414-447`; `docs/protocol/pre_vote.md:40-44`; tests
`pre_elect_test.rs:33-67`, `handle_pre_vote_req_test.rs:43-109`.
**Model**: `PreElect`, `TickPreElect`, `ExternalPreElect`, `HandlePreVoteRequest`. **Property**:
`Update!PreVoteRoundPersistsNothing`; old `VoteRequestAfterDurable` / `GrantedResponseAfterDurable`
kept with Pre-Vote kinds deliberately outside their quantifier. **Priority**: High.

### Scenario U2: A timer Pre-Vote round outlives the node's own leader establishment
**Mechanism**: the election timer fires on a *Candidate* whose election is still in flight
(`handle_tick_election` only skips `Leader` and non-voters, `raft_core.rs:1966-1974`) and, with
Pre-Vote enabled, calls `pre_elect` without touching the running candidate. If the original
election then wins, `establish_leader` / `become_leader` do **not** clear `pre_candidate`
(`engine_impl.rs:855-881`, `vote_handler/mod.rs:172-228`; only `do_elect` and `become_following`
clear it). Late Pre-Vote grants (granted while peers still held the uncommitted candidate vote)
pass the leader-id correlation (`raft_core.rs:1815-1816`) and `handle_pre_vote_resp` calls
`elect()` (`engine_impl.rs:534-539`) on the established Leader with no leader/voter re-check.
`do_elect` → `update_vote` → `is_leading` branch keeps the `Leader` object
(`vote_handler/mod.rs:154-161`), so the node becomes Candidate at term+1 while a Leader object at
the old term remains; `try_leader_handler` asserts `leader.vote >= state.vote`
(`engine_impl.rs:977-982`), and the heartbeat tick uses that path (`raft_core.rs:1851-1857,2126`).
**Model**: `TickPreElect` on Candidate, `HandleVoteResponse` (wins keeps pre-candidate),
`HandlePreVoteResponse` quorum → `ElectEffects` (keeps `leaderActive`). **Property**:
`Update!TimerPreVoteElectsOnlyNonLeader`. **Hunt**: `MC_hunt_U2_prevote_leader.cfg`. **Priority**: High.

### Scenario U3: Pre-Vote quorum hands over to the unchanged real election
**Mechanism**: the quorum calls `elect()`, whose vote is `vote.term + 1`; durability, vote request
ordering, self-grant and frozen candidate quorum are the old election path.
**Model**: `HandlePreVoteResponse` quorum → `ElectEffects`; old `PersistVote`, `SendVoteRequest`,
`HandleVoteResponse`. **Properties**: `Update!PreVoteProbeMatchesElection`,
`Update!PreCandidateProbeIsNextTerm`, all prior safety invariants as controls. **Priority**: High.

### Scenario U4: Round identity is the probed leader id only
**Mechanism**: a Pre-Vote round does not change the vote, so a later round (timer restart after
`election_timeout`, `raft_core.rs:2014-2023`; a new round after a follow/cancel; an operator round)
probes the **same** `(term+1, self)` leader id. `does_pre_candidate_vote_match` compares only that
leader id (`raft_core.rs:2067-2090`), although its own comment requires responses of a previous
round to be ignored (`raft_core.rs:2066`). An earlier round's grants therefore count toward the
current round. If the membership changed between the rounds, a stale grant from a node outside the
new frozen quorum set reaches `grant_by`, which `expect`s membership and panics
(`proposer/candidate.rs:107`). **Model**: history field `round` on Pre-Vote messages and `preRound`.
**Properties**: `Update!StalePreVoteResponseIgnored`, `Update!PreVoteResponseNeverPanics`.
**Hunt**: `MC_hunt_U4_prevote_stale_round.cfg`. **Priority**: Medium-High.

### Scenario U5: Configuration surfaces — runtime toggle and unimplemented network
**Mechanism**: `enable_pre_vote` is an `AtomicBool` toggled at runtime (`runtime_config_handle.rs:51`),
so a timer can take either branch; a network without `pre_vote` synthesizes a grant
(`network/v2/network.rs:158-161`). **Model**: `TickPreVoteModes`, `PreVoteFallbackPeers`.
**Hunt**: `MC_hunt_U5_prevote_fallback.cfg`. **Priority**: Medium.

### Scenario U6: Cancellation paths and crash/restart of a Pre-Vote round
**Mechanism**: granting another node's vote, accepting AppendEntries from another leader, adopting
a higher vote from a vote response, `refresh_server_state` to a follower/learner role, `do_elect`
and restart all drop the round; a stale response then is ignored (`raft_core.rs:1815`).
**Model**: `PreCandidateCleared` in `HandleVoteRequest`, `HandleAppendEntries`,
`HandleVoteResponse` (adopt), `RefreshServerState`, `ElectEffects`, `Restart`.
**Evidence/coverage**: trace `prevote_cancelled_by_vote_grant`; Update/focused campaigns. **Priority**: Medium.

## U.3 Model changes (summary; details in `spec/changelog.md`)

- New state `preCandidateActive/Vote/Config/preGrants`, history `preCandidateByTimer`, `preRound`;
  new message kinds `PreVoteReq`, `PreVoteResp` (+history field `round`).
- New actions `PreElect` (`TickPreElect`, `ExternalPreElect`), `HandlePreVoteRequest`,
  `HandlePreVoteResponse` (ignore / grant / quorum→elect / reject / panic branches).
- `StartElection` split into `ElectEffects` (do_elect) + member guard; Pre-Vote quorum calls
  `ElectEffects` without trigger guards, exactly as `handle_pre_vote_resp` calls `elect()`.
- Repairs of prior abstractions needed by the update: role/leader handling of do_elect for
  non-members, `seenGreaterLog` reset only on the timer path.

## U.4 Exclusions (update)

- Election-timeout arithmetic and the "round in flight" rate limit (`raft_core.rs:2014-2023`):
  timing abstraction, any tick may fire or restart a round.
- `enable_elect` runtime switch: not modeled before; a Pre-Vote quorum also ignores it
  (`engine_impl.rs:534-539`), recorded as code-review note, not modeled.
- RPC transport errors (`Unreachable`, timeouts): equivalent to message loss (`DropMessage`).
- Follower-side membership change via replication is not modeled (prior abstraction: AppendEntries
  carries no payload). The U4 panic variant through a follower is therefore code-review/test
  evidence, while the model reaches it through leader-local membership change.
- Liveness / "no term inflation while a leader holds leases" is not claimed: no fairness.

## U.5 Proposed update properties

| Property | Kind | Scenario |
|---|---|---|
| `TimerPreVoteElectsOnlyNonLeader` | action | U2 |
| `StalePreVoteResponseIgnored` | action | U4 |
| `PreVoteResponseNeverPanics` | action | U4 |
| `PreVoteProbeMatchesElection` | action | U3 |
| `PreCandidateProbeIsNextTerm` | state | U3 |
| `PreVoteRoundPersistsNothing` | action | U1 |

## U.6 Findings (status after model checking and reproduction)

- **MC-1 (U2)** — `TimerPreVoteElectsOnlyNonLeader` violated; reproduced end-to-end
  (`spec/confirmation-MC-1.md`).
- **MC-2 (U4)** — `StalePreVoteResponseIgnored` violated through operator rounds; panic consequence
  reproduced end-to-end (`spec/confirmation-MC-2.md`). Timer-only rounds are protected by the RPC timeout
  (modeled after the Case B repair).
- Code-review note (no separate finding): a Pre-Vote quorum also bypasses `enable_elect` and the voter check
  that every other `elect()` caller performs; with followers' rounds cancelled by AppendEntries this is
  reachable only on own-vote (candidate/leader) nodes, i.e. through MC-1/MC-2.
- Prior-model defect repaired (not a source finding): `LogLE` compared absent logs by a don't-care node, which
  made every multi-voter election unreachable in the prior 3-voter `MC.cfg`.
