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
- `commands`: the set of queued command kinds (the production queue remains FIFO; repeated
  per-target `Replicate` commands are intentionally collapsed by this capture)

Every listed field has an unconditional check in `Trace.tla::ValidatePostState`; no captured state
field is ignored. Trace validation intentionally covers the Engine post-state boundary. Durable
store contents and callback completion are modeled and model checked, but not claimed as observed
by this unit-level harness.

## Action mapping

| Trace action | Exact-old call | Base action |
|---|---|---|
| `Elect` | `Engine::elect` | `StartElection` |
| `VoteResponse` | `Engine::handle_vote_resp` | `ReceiveVoteResponse` |
| `VoteRequest` | `Engine::handle_vote_req` | `ReceiveVoteRequest` |
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
