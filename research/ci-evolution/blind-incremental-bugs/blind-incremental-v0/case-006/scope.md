# V0 scope: etcd Raft core and existing ReadIndex behavior

## Objective

Generate a pre-update TLA+ reference model from the supplied old tree only.
Model the deterministic Raft state machine, including the read-request behavior
already present in that tree, at protocol rather than Go-container granularity.

This is Category A distributed/message-passing behavior under crash faults,
message delay/loss, and leader changes. No Byzantine behavior is in scope.

## Source map to establish

Read these old-tree paths completely before writing the model:

- `raft.go`: roles, elections, replication, heartbeats, quorum checking,
  request handling, and response generation.
- `node.go`: public requests and `Ready`/`Advance` delivery.
- `log.go` and `log_unstable.go`: log and commit boundaries.
- `progress.go`: peer replication progress.
- `storage.go`: durable storage interface and in-memory implementation.
- `read_only.go`: pending read requests, heartbeat acknowledgements, queue
  advancement, and completed request delivery.
- `raftpb/raft.proto` and `raftpb/raft.pb.go`: message fields and meanings.
- `raft_test.go`, `raft_paper_test.go`, and `rafttest/network.go`: executable
  examples of the old state-machine and network semantics.

Derive request identity and lifecycle only from these exact-old structures and
message fields; do not assume a later internal identifier.

## Model boundary

Represent at least:

- per-node role, term, vote, leader identity, log, and commit index;
- leader progress for a small fixed cluster;
- in-flight messages with the old-tree fields relevant to vote, append,
  heartbeat, and read requests/responses;
- election and heartbeat ticks at logical-event granularity;
- pending read state, caller context, acknowledgement membership, queue order,
  and the old-tree read state delivered through `Ready`;
- optional quorum checking and the existing relationship between leader state
  and read response index.

Represent elections, proposal/replication, append handling, heartbeat handling,
leader step-down, read request forwarding/processing, and `Ready` publication.
Message delay, loss, and reordering may be modeled generically.

Do not model protobuf encoding, allocation, goroutines, logging, benchmarks,
snapshot byte contents, or implementation containers.

## Neutral V0 properties

Use standard Raft and old-tree interface properties:

- type correctness;
- election safety;
- log matching and committed-prefix agreement;
- leader completeness within the modeled bounds;
- commit indexes do not exceed local logs;
- emitted messages and delivered read states are well formed for the old-tree
  API;
- a delivered read index is justified by quorum acknowledgement for the
  corresponding pending request represented by the exact-old implementation;
- `Ready` publication does not invent a state-machine result that was not
  produced by an old-tree transition.

Do not add a request-identity scheme or validation rule absent from the old
tree.

## Old-only validation evidence

Focused existing tests:

- `TestNodeReadIndex`
- `TestReadyContainUpdates`
- `TestHandleHeartbeat`
- `TestHandleHeartbeatResp`
- `TestReadIndexWithCheckQuorum`
- `TestReadIndexWithoutCheckQuorum`
- `TestLeaderStepdownWhenQuorumActive`
- `TestLeaderStepdownWhenQuorumLost`
- `TestLeaderElection`
- `TestLogReplication`
- `rafttest.TestNetworkDrop`
- `rafttest.TestNetworkDelay`

The old tree has no native NDJSON trace emitter. Use these tests only as
old-behavior witnesses unless separately generated instrumentation is trace
validated.

## Build dependency boundary

The old tree predates `go.mod` and imports itself as
`github.com/coreos/etcd/raft`. It also imports `github.com/golang/protobuf/proto`
and `golang.org/x/net/context`. Prepare a read-only GOPATH-style dependency
overlay outside the visible source tree. Do not add modern source files or
history-derived compatibility code to the V0 input.

## Acceptance gates

- SANY parses `base.tla` and the configured model.
- A small bounded TLC run completes with the neutral V0 invariants enabled.
- The source mapping cites only supplied old-tree paths and functions.
- Focused old-only tests pass in the prepared GOPATH environment, or the exact
  dependency limitation is recorded.
- The suite contains no external or historical references.
