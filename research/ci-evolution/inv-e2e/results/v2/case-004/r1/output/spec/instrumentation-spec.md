# Instrumentation specification

## Event envelope

Every line is one JSON object:

```text
{"tag":"trace","ts":<unix-nanoseconds>,"event":{"name":<action>,"node":<u64>,"args":{...},"state":{...}}}
```

`ts` is a real monotonic-in-file observation timestamp derived from `SystemTime`; TLA+ does not use
it for behavior. A file begins with `Bootstrap`, which captures the pre-state and is consumed by
`TraceInit`; each later line is the post-state after one named real Engine call.

## Captured state (all events)

- `node_id`
- `vote_term`, `vote_node`, `vote_committed`
- `last_seen_term`, `last_seen_node`, `last_seen_committed`
- `role`: `Learner`, `Follower`, `Candidate`, or `Leader`
- `logs`: ordered `{term,node,index}` key-log segments exposed by `LogIdList`
- `last_index` and `commit_index` (`-1` means absent)
- `effective_index`, `committed_membership_index` (`-1` means absent)
- `effective_configs`: ordered JSON arrays representing each voter child
- `learners`
- `candidate`, `granters`, and `leader`
- `matches`: peer-to-matching-index records (`-1` means absent)
- `accepted_index`: last accepted log I/O index, or `-1`
- `accepted_kind` (update rebase): `none` (no accepted IO), `vote` (vote-only IOId, no log
  position — e.g. right after a vote change), or `log`. `Trace.tla::AcceptedMatches` compares
  `accepted_index` for `log`/`none` and requires an unchanged model `acceptedIndex` for `vote`.
- `commands`: the set of queued command kinds (the production queue remains FIFO; repeated
  per-target `Replicate` commands are intentionally collapsed by this capture)

Every listed field has an unconditional check in `Trace.tla::ValidatePostState`; no captured state
field is ignored. Trace validation intentionally covers the Engine post-state boundary. Durable
store contents and callback completion are modeled and model checked, but not claimed as observed
by this unit-level harness.

## Action mapping

| Trace action | Exact-old call | Base action |
|---|---|---|
| `Elect` | `Engine::elect` | `Elect` (Engine part; the RaftCore voter guard is `StartElection`) |
| `TransferLeader` | `RaftCore::handle_api_msg` arm `RaftMsg::TransferLeader` (raft_core.rs:1190-1202) | `TransferLeader` |
| `VoteResponse` | `Engine::handle_vote_resp` (unit) / `Notification::VoteResponse` arm (core, candidate grant only) | `ReceiveVoteResponse` |
| `VoteRequest` | `Engine::handle_vote_req` (unit) / `RaftCore::handle_vote_request` (core, grant only) | `ReceiveVoteRequest` (args add `last_term`, `last_node`) |
| `FollowerAppend` | `Engine::append_entries` | `ReceiveAppendDirect` |
| `LeaderAppend` | `LeaderHandler::leader_append_entries` | `LeaderAppend` |
| `AckReplication` | `ReplicationHandler::update_matching` | `AcknowledgeReplication` |
| `Startup` | `Engine::startup` | `RestartFromRecovered` |

Arguments contain the peer/vote/log/membership values required to select the base transition.

## Placement and synchronization

Instrumentation is confined to `openraft/src/engine/specula_trace_tests.rs` plus the test-only
module declaration in `/work/work-source`. It calls the production Engine methods directly and
observes immediately after each synchronous call. The writer is a per-test `Mutex<BufWriter<File>>`;
each write is one serialized object plus newline followed by flush. `run.sh` executes scenarios
serially and supplies one explicit file per test. There is no background process.


## Update: RaftCore-level probes (artifact commit d7176ef)

File `openraft/src/core/specula_core_trace.rs` (copy: `harness/src/specula_core_trace.rs`),
runtime-gated by `SPECULA_CORE_TRACE_DIR`; one NDJSON *session* per node and occurrence.

| Event | Location | Trigger | Args |
|---|---|---|---|
| `Bootstrap` | entry of the `RaftMsg::TransferLeader` arm (`raft_core.rs:1190`) | pre-state; opens a session when none is live or the live one is not contiguous | `{}` |
| `TransferLeader` | end of the same arm | post-state after `disable_lease` / `elect()` | `from_term, from_node, from_committed, to` |
| `VoteRequest` | `RaftCore::handle_vote_request`, right after `engine.handle_vote_req` (before the flush-gated `Respond` is queued) | only when the vote was granted (post vote == request vote) | `candidate, term, committed, last_term, last_node, last_index` |
| `VoteResponse` | `Notification::VoteResponse` arm, after `engine.handle_vote_resp` (inside `does_vote_match`) | only for a candidate grant (`!sender_vote.committed && resp.vote == sender_vote`) | `peer, term, owner, committed` |

Node ids are mapped `impl id + 1` (model `NoNode = 0`); vote/log leader ids with term 0 map to
`NoNode`. The state object has the same fields as the unit harness. `commands` lists only the
commands queued by the current handler (RaftCore keeps condition-blocked commands queued across
inputs). A session continues only while the next instrumented handler's pre-state equals the
last emitted post-state, ignoring `commands` (drained by RaftCore between inputs); otherwise
the session closes, so each file is a contiguous sequence of real transitions of one node.
Rejections (lease, log, vote) and the leader's committed SaveVote echo are not modeled
transitions and are not emitted; if they changed captured state, contiguity closes the
session.

Field consumption: every state field is compared by `ValidatePostState`; every event arg is an
argument of the base action. Evidence that the comparisons are active:
`spec/evidence/trace-mutation/README.md`.
