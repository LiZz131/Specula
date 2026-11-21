# Modeling Brief: Exact-old OpenRaft Engine and RaftCore

## 1. System Overview

- The system is OpenRaft 0.10.0, implemented in Rust as a replicated-state-machine library; the twelve principal boundary files total 6,034 lines.
- This is Category A (distributed/message-passing): nodes exchange vote and append RPCs, while local storage work completes asynchronously.
- The selected boundary is the deterministic `Engine`, the `RaftCore` event loop, election, replication, commit, initialization, and public log-storage lifecycle.
- The Engine mutates a shadow protocol state and emits ordered `Command` values; RaftCore executes those commands and later feeds notifications back into the Engine.
- The concurrency model is a single RaftCore event loop combined with spawned RPC tasks and storage work whose completion returns through a notification channel.
- The model preserves vote identity and committed status, log and commit cursors, membership role, per-peer replication progress, messages, and accepted/submitted/flushed IO identity.
- Rust ownership, allocation, payload bytes, serialization, application semantics, and storage implementation internals are intentionally collapsed.
- The sole behavioral authority is the exact-old tree at `/work/source`; the scope file's obsolete `/work/old-tree` label is resolved by the explicit task and input manifest naming `/work/source`.

## 2. Scenarios

### Scenario 1: Initialization and election command sequencing

**Mechanism**: One atomic Engine transition can create several runtime obligations whose order is observable at storage and network boundaries.

**Evidence**:

- Code analysis: `openraft/src/engine/engine_impl.rs:190-233` installs the initial membership log, starts an election, accepts the new vote IO, and queues vote-related commands.
- Code analysis: `openraft/src/engine/handler/vote_handler/mod.rs:104-139` persists only a strictly newer vote and changes the internal server state from vote identity.
- Code analysis: `openraft/src/core/raft_core.rs:906-967` drains Engine commands in order and separately polls progress-driven commands.
- Code analysis: `openraft/src/core/raft_core.rs:1864-1887` submits SaveVote, waits for storage, then queues LocalIO and a successful local VoteResponse.

**Affected code paths**: `Engine::initialize`, `Engine::elect`, `VoteHandler::update_vote`, `RaftCore::run_engine_commands`, `RaftRuntime::run_command`.

**Suggested modeling approach**:

- Variables: term, vote node, committed bit, role, candidate presence, grant set, voter count, IO identity, and messages.
- Actions: split the Engine election state change from submit, flush, local response delivery, and remote request delivery.
- Granularity: initialization/election are atomic Engine steps; each command or notification boundary is a separate transition.

**Priority**: High

**Rationale**: These steps seed every later leadership and replication path and expose concrete ordering boundaries.

### Scenario 2: Delayed vote responses and leader establishment

**Mechanism**: A candidate becomes leader only after unique matching grants form a quorum; the transition commits its vote and appends a blank entry.

**Evidence**:

- Code analysis: `openraft/src/engine/engine_impl.rs:340-403` ignores nonmatching responses, records matching grants, and establishes leadership on quorum.
- Code analysis: `openraft/src/engine/engine_impl.rs:708-735` rebuilds replication, commits the vote, accepts log IO, and appends the leader blank entry.
- Code analysis: `openraft/src/proposer/candidate.rs:93-104` records grants by voter identity.
- Code analysis: `openraft/src/core/raft_core.rs:1442-1464` filters queued vote notifications against the current candidate vote before calling the Engine.

**Affected code paths**: `Engine::handle_vote_resp`, `Candidate::grant_by`, `Engine::establish_leader`, `RaftCore::handle_notification`.

**Suggested modeling approach**:

- Variables: candidate vote, unique grant set, in-flight vote requests/responses, role, log cursor, and IO accepted cursor.
- Actions: send, delay/drop, deliver request, deliver response, deliver local response, and establish leader.
- Granularity: notification delivery and the subsequent Engine establishment step remain distinct in the ordinary model; the direct Engine trace action reflects the tested atomic handler call.

**Priority**: High

**Rationale**: The path links message nondeterminism to the election-safety state and the first leader log entry.

### Scenario 3: Append acceptance, replication, and commit

**Mechanism**: A follower validates the incoming vote and prefix, replaces a conflicting suffix, accepts log IO, and a leader commits only a quorum-accepted current-term position.

**Evidence**:

- Code analysis: `openraft/src/engine/engine_impl.rs:405-457` separates vote rejection, prefix rejection, append mutation, and response generation.
- Code analysis: `openraft/src/engine/handler/following_handler/mod.rs:63-173` truncates conflicts, appends the remaining suffix, updates effective membership, and recalculates role.
- Code analysis: `openraft/src/engine/handler/leader_handler/mod.rs:53-100` assigns leader log identities, accepts IO, and queues replication.
- Code analysis: `openraft/src/engine/handler/replication_handler/mod.rs:139-197` derives quorum progress and commits a granted position only in the active leader term.

**Affected code paths**: `Engine::append_entries`, `FollowingHandler::append_entries`, `LeaderHandler::leader_append_entries`, `ReplicationHandler::try_commit_quorum_accepted`.

**Suggested modeling approach**:

- Variables: log length, commit length, role/membership projection, per-peer match length, and AppendEntries messages.
- Actions: leader append, send/delay/drop, follower delivery, replication acknowledgement abstraction, and commit advance.
- Granularity: follower prefix replacement is one deterministic Engine step; transport and commit progress are separate.

**Priority**: High

**Rationale**: This is the central log-safety and commit path inside the binding boundary.

### Scenario 4: Accepted, submitted, and flushed IO lifecycle

**Mechanism**: Protocol acceptance, runtime submission, and successful completion are three monotonic stages with an identity-preserving order.

**Evidence**:

- Code analysis: `openraft/src/raft_state/io_state/io_progress.rs:86-145` advances accepted, submitted, and flushed values monotonically.
- Code analysis: `openraft/src/core/raft_core.rs:1812-1877` marks append or vote IO submitted before or while invoking storage.
- Code analysis: `openraft/src/core/raft_core.rs:1848-1861` updates submitted before `append` because a callback may run before the storage call returns.
- Code analysis: `openraft/src/storage/callback.rs:79-111` converts a successful callback into a LocalIO notification.
- Code analysis: `openraft/src/core/raft_core.rs:1540-1557` advances flushed progress when that notification is handled.

**Affected code paths**: `IOProgress::accept`, `IOProgress::submit`, `IOProgress::flush`, `RaftRuntime::run_command`, `IOFlushed`, `RaftCore::handle_notification`.

**Suggested modeling approach**:

- Variables: accepted/submitted/flushed term and log cursor for each node.
- Actions: accept, submit, storage completion delivery, and notification handling.
- Granularity: keep all three stages separate because the implementation explicitly permits callbacks and unrelated event-loop work between them.

**Priority**: High

**Rationale**: The ordering is implementation-specific, traceable, and relied on by conditioned Engine commands.

### Scenario 5: Crash, restart, and message nondeterminism

**Mechanism**: Node availability changes only between Engine/runtime steps, while messages may be delayed, reordered, or lost without inventing storage-internal behavior.

**Evidence**:

- Code analysis: `openraft/src/core/raft_core.rs:242-495` treats shutdown as an event-loop boundary.
- Code analysis: `openraft/src/raft/mod.rs:1337-1349` exposes shutdown through the public Raft handle.
- Code analysis: `openraft/src/core/raft_core.rs:1151-1220` runs vote RPCs as spawned tasks and reports results through notifications.

**Affected code paths**: RaftCore main loop, spawned vote/append RPC tasks, notification handling, public shutdown.

**Suggested modeling approach**:

- Variables: alive flag and a finite set of in-flight protocol messages.
- Actions: crash, restart with retained abstract durable cursors, message send, delivery, and loss.
- Granularity: faults occur only between listed atomic transitions; no partial mutation inside an Engine call.

**Priority**: Medium

**Rationale**: It supplies neutral Category-A interleavings without claiming guarantees absent from the exact-old interfaces.

## 3. Modeling Recommendations

### 3.1 Model (with rationale)

- Model Engine state mutation separately from command execution, because Scenarios 1 and 4 show explicit queue and IO boundaries.
- Preserve vote term, node, and committed status, because Scenarios 1 and 2 use all three to determine candidate/leader behavior.
- Preserve candidate grants as a set, because Scenario 2 relies on uniqueness and quorum cardinality.
- Preserve log, commit, and match cursors, because Scenario 3 derives commit from quorum replication progress.
- Preserve accepted/submitted/flushed identities as ordered term/cursor pairs, because Scenario 4 exposes them independently.
- Model finite messages with arbitrary delivery/loss and node crash/restart between steps, as justified by Scenario 5.

### 3.2 Do Not Model (with rationale)

- Do not model application command values or state-machine contents; only commit/log positions cross this boundary.
- Do not model a particular async runtime scheduler or wall-clock throughput; only observable event ordering matters.
- Do not model disk files, serialization bytes, or storage-engine internals; the old public storage/callback interface is the boundary.
- Do not model Rust allocation, ownership, Arc layout, or generic type machinery; these do not change protocol transitions.
- Do not add APIs, behaviors, or assumptions from any other revision.

## 4. Proposed Extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Engine/runtime split | IO stage variables, messages | Expose ordered commands and later notifications | 1, 4 |
| Local persisted-vote response | grantSet, IO terms/cursors | Count the self vote only after SaveVote completion | 1, 2 |
| Candidate quorum state | candidate, grantSet, voters | Represent unique delayed grants and establishment | 2 |
| Replication progress | matchLen, logLen, commitLen | Represent quorum replication and commit | 3 |
| Availability and transport | alive, messages | Explore crashes and delay/loss at code-backed boundaries | 5 |

## 5. Proposed Invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| TypeOK / MCTypeOK | Safety | Every variable and bound counter remains in its declared domain | All |
| IOOrdered | Safety | flushed identity is not ahead of submitted, which is not ahead of accepted | 1, 4 |
| CommittedWithinLog | Safety | A node never commits beyond its local log | 3 |
| LeaderHasCommittedVote | Safety | Every modeled leader carries a committed vote | 2 |
| CandidateHasOwnVote | Safety | Every candidate has its own noncommitted vote in the active term | 1, 2 |
| MatchWithinLog | Safety | A leader's peer match cursor never exceeds its local log | 3 |
| ElectionSafety | Safety | Two different nodes cannot both be leaders in one term | 2, 5 |
| TraceMatched | Liveness over finite replay | Every supplied implementation event is consumed by its mapped action | 1-4 |

## 6. Findings Pending Verification

### 6.1 Model-Checkable

None. This V0 is a neutral pre-update prior; the binding scope excludes targeted findings, expected violations, and hunt configurations. `MC.cfg` instead checks the source-derived invariants across all bounded neutral actions.

### 6.2 Test-Verifiable

None recorded. The harness uses existing ordinary exact-old tests only.

### 6.3 Code-Review-Only

None recorded. This task performs structural and deep code analysis, not incident investigation.

## 7. Reference Pointers

- Full analysis: `/work/prior/.specula-output/analysis-report.md`
- Base specification: `/work/prior/.specula-output/spec/base.tla`
- Model-checking wrapper: `/work/prior/.specula-output/spec/MC.tla`
- Trace replay wrapper: `/work/prior/.specula-output/spec/Trace.tla`
- Instrumentation map: `/work/prior/.specula-output/instrumentation-spec.md`
- Engine transition source: `/work/source/openraft/src/engine/engine_impl.rs:190`
- Runtime command source: `/work/source/openraft/src/core/raft_core.rs:906`
- IO progress source: `/work/source/openraft/src/raft_state/io_state/io_progress.rs:86`
