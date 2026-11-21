# Exact-old structural and deep analysis report

## Purpose and authority

This report analyzes the neutral subsystem selected by `/work/scope.md` for a fresh Specula V0 prior. The only implementation authority used for behavioral conclusions was `/work/source`. The task and `/work/input-manifest.json` explicitly identify that tree as the pristine exact-old source, resolving the scope document's obsolete `/work/old-tree` path label.

No upstream history, remotes, tags, issues, pull requests, advisories, release notes, papers, benchmark labels, internet research, fixed revision, or incremental diff was inspected. Build dependency access did not contribute behavioral information. The analysis is therefore code-derived and intentionally contains no incident theory, reproduction target, or expected finding.

The source identity recorded by the input manifest is SHA-256 `9821ab1a408ba844c747ab563cb400a4dadd4f501bc9cd9250b35c8f18d7cd4b`. Its single neutral local commit is the patch baseline. `/work/source` remained clean and unmodified.

## Boundary and coverage

The boundary contains:

- deterministic protocol mutation in `Engine`;
- ordered Engine commands and progress-driven commands;
- the RaftCore event loop and notification handling;
- election request/response and candidate quorum state;
- leader establishment, append replication, and commit advancement;
- public log-storage submission, callback completion, and IO progress;
- initialization plus node/message nondeterminism at code-backed boundaries.

The twelve principal boundary files contain 6,034 lines. Deep analysis covered those files, directly invoked election/following/leader/replication handlers, candidate quorum tracking, and the neutral tests used by the harness. The complete 770-file repository was not line-audited because application semantics, unrelated APIs, and storage implementations are outside the selected subsystem.

Excluded from behavioral modeling are application command values, state-machine contents, snapshot bytes, disk layout, serialization, runtime-specific scheduling, wall-clock performance, allocation, and Rust generic/ownership machinery.

## Architecture

`Engine<C>` owns the deterministic protocol projection. Callers invoke a public-to-core operation, the Engine mutates its state synchronously, and it appends `Command<C>` values to `EngineOutput`. `RaftCore` later drains that queue in order (`core/raft_core.rs:906-967`). It also asks the Engine for progress-driven work after the explicit queue is empty (`engine/engine_impl.rs:649-704`).

`RaftRuntime::run_command` bridges deterministic state to side effects (`core/raft_core.rs:1812-1900`). Vote writes are awaited. Log append submission creates a callback and updates the submitted cursor before calling the storage trait. RPC work is spawned and later reports through `Notification` values. RaftCore handles notifications, calls the Engine, then drains any resulting commands again.

This design produces four distinct categories of step:

1. an atomic Engine mutation;
2. ordered command execution/submission;
3. independent storage or network completion;
4. notification delivery and the next Engine mutation.

The model does not merge these categories when the code allows interleaving.

## State and identity mapping

| Implementation concept | Model representation | Evidence |
|---|---|---|
| local node identity | `Nodes`, indexed functions | `EngineConfig.id`, `engine_impl.rs:84-101` |
| accepted vote | `term`, `voteNode`, `voteCommitted` | `vote_handler/mod.rs:104-139` |
| server state | `role` | `vote_handler/mod.rs:141-176` and server-state handler |
| pending campaign | `candidate`, `grantSet`, `voters` | `proposer/candidate.rs:20-111` |
| effective membership projection | `voters`, `selfVoter` | `engine_impl.rs:119-132`, following handler |
| local log tail | `logLen` | RaftState log ID list and `engine_impl.rs:443-457` |
| committed position | `commitLen` | `replication_handler/mod.rs:186-205` |
| peer replication | `matchLen[leader][peer]` | leader replication progress handlers |
| accepted IO identity | `ioAcceptedTerm`, `ioAccepted` | `io_progress.rs:86-104` |
| submitted IO identity | `ioSubmittedTerm`, `ioSubmitted` | `io_progress.rs:106-125` |
| flushed IO identity | `ioFlushedTerm`, `ioFlushed` | `io_progress.rs:127-190` |
| RPCs in flight | finite `messages` set | spawned RPC paths and notifications |
| process availability | `alive` | RaftCore shutdown/public stop boundary |

Log IDs are abstracted to a prefix length. IO identity retains both vote term and log length because vote-only writes have no log ID and must remain distinguishable from log writes. Node IDs and terms in the neutral harness use the numeric `UTConfig`; the model intentionally does not encode application-defined node types.

## Engine transition analysis

### Initialization

`Engine::initialize` checks that the node has the zero vote and an empty log (`engine_impl.rs:190-210`). It appends the membership entry at index zero under the committed term-zero identity, then calls `elect`. The observable post-state of that one Engine call is a term-one candidate with one log entry and a pending vote IO. Commands representing append, vote persistence, and vote sending remain ordered in `EngineOutput`.

The `EngineInitialize` action models the complete synchronous post-state. It does not claim the append or vote is already durable. Subsequent IO actions represent runtime progress.

### Election and self vote

`Engine::elect` constructs the next-term noncommitted self vote, creates a fresh `Candidate`, applies the vote through `VoteHandler::update_vote`, queues `SendVote`, and recalculates server state (`engine_impl.rs:213-233`). `Candidate::new` begins with an empty grant-progress vector (`proposer/candidate.rs:51-72`), which agrees with the election trace's grant count of zero.

The local grant arrives later from the runtime. `Command::SaveVote` submits and saves the vote, queues `Notification::LocalIO`, and then queues a successful `Notification::VoteResponse` from the local node (`core/raft_core.rs:1864-1887`). RaftCore validates that notification against the current candidate and invokes `handle_vote_resp` (`core/raft_core.rs:1442-1464`). This required a separate `DeliverLocalVoteResponse` action; adding it during reachability review was a fidelity correction to the initial abstraction.

Remote vote requests are sent only after SaveVote has returned because RaftCore drains the ordered command queue. The model therefore requires the vote identity to reach submitted before it can create a remote request message.

### Vote request and response

`Engine::handle_vote_req` first compares last-log identity and then attempts to update the vote (`engine_impl.rs:286-337`). A grant can accept a newer noncommitted vote, change role to follower/learner, and queue persistence. The model keeps the material guards: candidate term, last-log prefix, existing vote, and destination liveness.

`Engine::handle_vote_resp` ignores stale candidate responses, records a matching grant by target identity, and calls leader establishment only once the effective membership quorum is satisfied (`engine_impl.rs:340-403`). The model represents grants as a set, so delayed duplicates cannot add quorum weight.

`establish_leader` consumes the candidate, creates the leader state, commits the vote, rebuilds replication streams, accepts log IO, and appends a blank entry (`engine_impl.rs:708-735`). The ordinary model splits grant delivery from `BecomeLeader` to expose scheduling. The direct `HandleVoteResponse` trace action matches the real synchronous handler boundary and includes both effects in one validated event.

### Append and following state

`Engine::append_entries` applies the message vote guard before forwarding to the following handler (`engine_impl.rs:443-457`). The following handler checks the preceding log ID, removes already-matching entries, truncates a conflicting suffix, accepts the remaining entries, updates effective membership, and changes the server role if membership removes or adds the node (`following_handler/mod.rs:63-173`).

The direct trace action captures an accepted nonempty suffix with the validated previous-prefix length. It treats suffix replacement and resulting membership projection as one atomic Engine step because no runtime await or callback occurs inside the handler. Rejection variants are present in the code analysis but are not emitted by the neutral acceptance trace.

### Leader append, replication, and commit

`LeaderHandler::leader_append_entries` assigns current-leader log identities, appends to the Engine log state, accepts the corresponding IO, updates local replication progress, and queues storage/replication work (`leader_handler/mod.rs:53-100`). The ordinary model represents this as `LeaderAppend`, followed by IO submission and independent AppendEntries messages.

Follower delivery updates its accepted vote/log projection and the leader's abstract peer match cursor. The detailed callback response path is collapsed because the property-relevant outcome is match progress, not response allocation.

`ReplicationHandler::try_commit_quorum_accepted` only converts a quorum-granted log position to committed state when the log leader term equals the current leader term (`replication_handler/mod.rs:139-205`). `AdvanceCommit` therefore requires leader role, a quorum of `matchLen`, and a target within the local log.

## IO lifecycle and ordering

`IOProgress<T>` maintains three monotonic values (`io_progress.rs:34-83`):

- accepted: deterministic state has accepted work;
- submitted: RaftCore has submitted that work to storage;
- flushed: a successful completion notification has been handled.

`accept`, `submit`, and `flush` each reject a backward move and otherwise advance their respective cursor (`io_progress.rs:86-145`). Completion code explicitly tolerates delayed or already-covered notifications (`io_progress.rs:127-190`). The model uses lexicographic term/log identity and checks `flushed <= submitted <= accepted`.

For AppendEntries commands, RaftCore updates submitted before invoking `log_store.append` because the storage implementation may invoke the callback before `append` returns (`core/raft_core.rs:1848-1861`). The callback sends LocalIO only on successful completion (`storage/callback.rs:79-111`). RaftCore then calls the IO-state completion update while handling that notification (`core/raft_core.rs:1540-1557`).

No stronger guarantee is assumed. In particular, the model does not claim a disk write order beyond identities exposed by the old interfaces, and it does not equate storage callback execution with notification delivery.

## Atomicity table

| Boundary | Atomic in model | May interleave after it | Code basis |
|---|---|---|---|
| Engine initialize/elect | yes | queued append/save/send commands | `engine_impl.rs:190-233` |
| Engine vote handler | yes | persistence/network commands | `engine_impl.rs:286-403` |
| Engine append handler | yes | append submission/response gating | `engine_impl.rs:405-457` |
| leader establishment | yes in direct trace; separate from grant in MC | append submission and replication | `engine_impl.rs:708-735` |
| command dequeue | one command | storage/RPC work and later commands | `raft_core.rs:906-967` |
| storage submission | yes | callback can occur before call returns | `raft_core.rs:1848-1861` |
| storage callback | yes | notification delivery | `storage/callback.rs:79-111` |
| notification handling | yes | resulting command drain | `raft_core.rs:1442-1557` |
| message send | yes | delay, delivery, loss, other steps | spawned RPC paths |
| crash/restart | between steps only | retained abstract durable state | event-loop/public stop boundary |

## Failure and environment assumptions

- Nodes are crash-stop during a modeled outage and may restart between actions.
- Restart retains the abstract vote/log/IO cursors already represented as durable; volatile candidate grants are cleared on crash.
- Messages may be delayed, reordered, or lost. The model makes no fairness claim for network delivery.
- Storage work is independent after submission. Only a successful callback produces the LocalIO completion event modeled here.
- Engine calls do not partially interleave because they contain no await point and mutate through one exclusive Engine reference.
- No Byzantine behavior, data corruption, clock drift, or application nondeterminism is introduced; none is in the selected exact-old boundary.

## Property derivation

`TypeOK`/`MCTypeOK` guard the abstraction itself. `IOOrdered` is directly derived from `IOProgress` and the pre-append submission rule. `CommittedWithinLog` follows from commit advancement being selected within the local log. `LeaderHasCommittedVote` and `CandidateHasOwnVote` encode the server-state derivation in vote handling. `MatchWithinLog` constrains leader peer progress to its local tail. `ElectionSafety` checks that different nodes do not simultaneously hold leader role in one term.

`TraceMatched` is a finite-replay temporal property: the replay cursor must advance past every supplied implementation event. It is not satisfied by parsing alone; every event action also requires every captured post-state field to match.

No liveness property over an unbounded unreliable network is claimed. The only temporal replay obligation terminates over a concrete finite file.

## Neutral scenarios selected for traces

1. Single-node initialization: existing `test_initialize_single_node`, event `EngineInitialize`.
2. Multi-node election entry: existing `test_elect_multi_node_enter_candidate`, event `EngineElect`.
3. Matching quorum vote response: existing `test_handle_vote_resp_equal_vote`, event `HandleVoteResponse`.
4. Accepted append with committed prefix and membership update: existing `test_append_entries_prev_log_id_is_committed`, event `EngineAppendEntries`.
5. Generic monotonic IO lifecycle: existing `test_monotonic_updates`, events `IOAccept`, `IOSubmit`, `IOFlush`.

These are ordinary unit scenarios already in the exact-old tree. No special schedule, source mutation beyond tracing, or suspected failure trigger was introduced.

## Validation implications and limits

The five trace files contain seven real instrumented events. They cover initialization, election, leader establishment, accepted append, and all three IO stages. They do not cover rejection branches, multi-event network conversations, crash/restart, or an end-to-end storage-backed cluster execution. Those omissions limit dynamic coverage but do not invalidate the fully consumed traces.

The bounded ordinary model contains two nodes, terms through two, logs through length three, at most two in-flight messages, and finite counters for initialization, election, vote/append sends, crash, and message loss. It explores all actions under those bounds and checks every configured invariant. A prior wider three-node run reached all key paths but exhausted its five-minute outer budget before its queue emptied. Neither run constitutes proof of the unbounded system.

## Handoff

- Modeling decisions: `/work/prior/.specula-output/modeling-brief.md`
- TLA+ base/MC/trace modules: `/work/prior/.specula-output/spec/`
- Instrumentation map: `/work/prior/.specula-output/instrumentation-spec.md`
- Trace harness and baseline patch: `/work/prior/.specula-output/harness/`
- Preserved run logs: `/work/prior/.specula-output/spec/output/`
