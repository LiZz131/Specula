# Harness operation (rebased onto the update revision d7176ef9)

Run `./run.sh` from anywhere. It applies `instrumentation.patch` to `../artifact` (idempotent),
builds with the installed `stable` toolchain (the artifact pins `nightly-2024-03-20`, which cannot
be installed in this environment; override with `SPECULA_TOOLCHAIN`), runs every scenario under a
15-minute outer `timeout`, and writes fresh traces:

- `../traces/<name>.ndjson` -- Engine unit layer (`openraft/src/engine/specula_trace_tests.rs`):
  the 8 prior V0 scenarios unchanged except two argument additions, plus 4 update scenarios
  (`elect-learner`, `elect-absent`, `follower-membership`, `vote-request-logid`).
- `../traces/window/<scenario>/*.ndjson` -- RaftCore window layer (`openraft/src/specula_trace.rs`,
  cargo feature `specula-trace`, hooks in `core/raft_core.rs`): the neutral update test
  `t14_transfer_leader::transfer_leader` and the diff-derived scenario
  `t99_specula_transfer_leader::specula_transfer_leader_to_learner` (asserts nothing; writes
  `observations.json`).

Changed points relative to the V0 harness (`instrumentation-v0.patch`, which still applies):

- `capture()` moved to `openraft/src/specula_trace.rs` (shared), adds `candidate_last_{term,node,index}`
  and reports only commands pushed by the observed step.
- `VoteRequest` args add `last_term`, `last_node` (full LogId, repair R1); `FollowerAppend` args add
  the real `entries` (repair R3).
- New RaftCore probes around the `TransferLeader` branch, `handle_vote_request`, and the
  `Notification::VoteResponse` engine call (pending `VoteResponsePanic` file records a panic).

Validation: `../scripts/validate_traces.sh <label>` (TLC, `TraceMatched`, full post-state checks),
`../scripts/field_consumption_check.py ..` (mutation negative control).
