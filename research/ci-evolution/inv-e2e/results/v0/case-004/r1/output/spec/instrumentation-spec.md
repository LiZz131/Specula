# Instrumentation specification (update revision)

Two producers write the same event envelope; `Trace.tla` consumes both.

## Event envelope

```text
{"tag":"trace","ts":<unix-ns string>,"event":{"name":<action>,"node":<id>,"args":{...},"state":{...}}}
```

A file begins with `Bootstrap` (pre-state, consumed by `TraceInit`); every later line is the
post-state after one real handler call. RaftCore raw events additionally carry `pre`; the
splitter (`harness/split_core_trace.py`) turns them into chains whose pre-state equals the
previous post-state, so no unrecorded transition is ever assumed inside a trace.

Node ids: unit traces use ids 1..3 verbatim. RaftCore traces come from integration tests whose
node ids start at 0 and are renamed k → k+1; a `(term, node)` pair with term 0 (the default
leader id) maps to `NoNode = 0`.

## Captured state (all events) — every field is checked by `ValidatePostState`

`node_id`; `vote_term/vote_node/vote_committed`; `last_seen_term/node/committed`; `role`;
`logs` (`{term,node,index}` for every index); `last_index`; `commit_index`;
`effective_index`; `committed_membership_index`; `effective_configs`; `learners`;
`candidate`; `granters`; `leader`; `matches` (leader progress `{peer,index}`);
`accepted_vote_io` (**new**, `accepted_io` is `IOId::Vote`) and `accepted_index` (compared
when `accepted_vote_io` is false: a vote I/O has no log id); `commands` (kinds emitted by this
handler; RaftCore hook excludes commands already queued before the call);
`lease_enabled` (**new**, `Leased::lease_enabled`, read through an added read-only accessor).

## Action mapping

| Trace action | Producer / real call | Base action(s) |
|---|---|---|
| `Elect` | unit: `Engine::elect` | `StartElection` |
| `VoteResponse` | unit: `Engine::handle_vote_resp`; core: `Notification::VoteResponse` → `handle_vote_resp` (`raft_core.rs:1260`) | `ReceiveVoteResponse` ∨ `ReceiveVoteResponseOther` |
| `VoteResponsePanic` | core: unwinding guard around the same call | `ReceiveVoteResponse` (panic branch) |
| `VoteRequest` | unit: `Engine::handle_vote_req`; core: `RaftCore::handle_vote_request` around `handle_vote_req` (`raft_core.rs:1112-1123`) | `ReceiveVoteRequest` ∨ `RejectVoteRequest` |
| `TransferLeader` (**update**) | core: `RaftMsg::TransferLeader` arm (`raft_core.rs:1190-1202`), whole arm | `TransferLeader` ∨ `TransferLeaderIgnored` |
| `FollowerAppend` | unit: `Engine::append_entries` | `ReceiveAppendDirect` |
| `LeaderAppend` | unit: `LeaderHandler::leader_append_entries` | `LeaderAppend` |
| `AckReplication` | unit: `ReplicationHandler::update_matching` | `AcknowledgeReplication` |
| `Startup` | unit: `Engine::startup` | `RestartFromRecovered` |

Args: `TransferLeader {from_term, from_node, from_committed, to}`;
`VoteRequest {candidate, term, committed, last_term, last_node, last_index}` (**last log id is
new**; `last_index = -1` encodes `None`); `VoteResponse {peer, term, owner, committed}`;
others unchanged from V0.

## Placement and synchronization

- Unit: `openraft/src/engine/specula_trace_tests.rs` (test-only module); no-op unless
  `SPECULA_TRACE_FILE` is set.
- Core: `openraft/src/specula_core_trace.rs` + three call sites in `core/raft_core.rs`; inert
  unless `SPECULA_CORE_TRACE_FILE` is set (a `OnceLock` checked before any capture). One
  mutex-serialized append per event line. Hooks only read Engine state; the panic guard writes
  only during unwinding.
- Read-only accessor `Leased::lease_enabled()` in `utime.rs`.
- Behavior neutrality evidence: 199/199 openraft lib tests pass on the instrumented tree
  (`spec/output/source-tests.log`); `t14_transfer_leader` passes instrumented
  (`spec/output/scenario-core-t14.log`); the MC-1 reproduction runs on an uninstrumented tree.
