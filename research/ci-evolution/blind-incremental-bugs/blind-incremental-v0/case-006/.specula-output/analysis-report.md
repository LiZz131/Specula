# Code-only analysis report — exact-old etcd Raft

## Boundary and method

Analysis was restricted to `/work/source/`, `/work/scope.md`, and the public
manifest. The supplied source-map files were read as exact-old inputs. Per the
experiment override, archaeology, history, remotes, issue/PR search, papers,
release notes, benchmark labels, external sites, and any new revision were not
consulted. History coverage is therefore intentionally 0 commits beyond the
single neutral baseline and 0 external issues/PRs. No behavioral claim below
depends on build dependencies.

Category: A, distributed/message-passing, crash fault only. The raft object is a
deterministic event-driven state machine. `node.run` serializes proposals,
received messages, ticks, Ready delivery, Advance, and membership updates; the
application and network are asynchronous outside that loop (`node.go:273-390`).

## Structural map and atomicity

| Boundary | Exact-old behavior | Source |
|---|---|---|
| Configuration/bootstrap | Load storage hard/config state, initialize progress, become follower | `raft.go:266-317` |
| Local state-machine step | `raft.Step` performs term handling and dispatches one message atomically | `raft.go:679-781` |
| Election | Candidate increments term/self-votes; vote RPCs carry last index/term; quorum promotes | `raft.go:570-580`, `raft.go:624-677`, `raft.go:986-1027` |
| Leader entry | Reset progress then append a no-op in the current term | `raft.go:597-621` |
| Append send | Read progress, prefix term, entries, commit; optimistically update progress | `raft.go:367-424` |
| Append receive | Match prefix, append only after conflicts beyond commit, clamp commit | `raft.go:1084-1097`, `log.go:74-102` |
| Append response | Back off on rejection; advance Match/Next and current-term commit on success | `raft.go:863-902`, `progress.go:112-153` |
| Heartbeat | Send commit clamped to follower Match; receiver commits monotonically and echoes context | `raft.go:426-443`, `raft.go:1099-1102` |
| CheckQuorum | Count self plus recently active peers, clear peer activity, step down if minority | `raft.go:791-796`, `raft.go:1214-1235` |
| Safe ReadIndex | Context-keyed enqueue, heartbeat context ack, quorum, FIFO-prefix advance | `raft.go:824-838`, `raft.go:915-932`, `read_only.go:48-108` |
| Ready publication | Snapshot current deltas, deliver, clear msgs/readStates; Advance marks stable/applied | `node.go:286-296`, `node.go:355-383`, `node.go:506-525` |
| Storage | MemoryStorage operations are mutex atomic; unstable entries are application-persisted via Ready | `storage.go:72-105`, `storage.go:236-271`, `log_unstable.go:19-123` |

The most important crash boundary is not inside `raft.Step`: state and outbound
messages accumulate until `Ready` tells the application to persist hard state
and entries before sending (`node.go:58-85`). `Advance` acknowledges stability
and application progress later (`node.go:374-383`). The base spec therefore
separates protocol transitions from Ready publication and Advance.

## Deep behavior analysis

### Elections

Messages with a higher term normally force follower state, except PreVote and a
granted PreVote response do not mutate the local term (`raft.go:679-711`). With
CheckQuorum, an in-lease node ignores a higher-term Vote/PreVote unless the
campaign is a forced leader transfer (`raft.go:684-695`). A lower-term append or
heartbeat under CheckQuorum receives an append response to help the stale
leader advance; other lower-term messages are ignored (`raft.go:713-734`).
Voting requires no prior conflicting vote (or a repeated same-candidate vote)
and a candidate log at least as up-to-date (`raft.go:759-775`,
`log.go:261-277`). Candidate quorum success and rejection quorum are separate
branches (`raft.go:986-1024`).

### Logs and commit

Log indexes are sequence positions above a retained dummy/snapshot boundary.
Follower append matching first checks the preceding `(index,term)`, locates the
first conflict, refuses conflicts at or below commit, appends the remaining
suffix, and commits only through `min(leaderCommit,lastNewIndex)`
(`log.go:74-102`). Leader commit sorts Match indexes, takes the majority index,
and advances only if that entry belongs to the current term
(`raft.go:475-486`, `log.go:279-285`). `commitTo` is monotonic and bounded by
last index; `appliedTo` enforces `applied <= committed` (`log.go:187-205`).

### Heartbeats and CheckQuorum

A heartbeat carries `min(progress.Match, leaderCommit)`, preventing a lagging
follower from committing beyond its known match (`raft.go:426-443`). A follower
commits monotonically and echoes the context (`raft.go:1099-1102`). Any append
or heartbeat response marks the peer recently active (`raft.go:863-864`,
`raft.go:903-905`). Each quorum check counts the leader itself, observes and
then clears peer activity, and requires `floor(n/2)+1` (`raft.go:332`,
`raft.go:1214-1235`).

### ReadIndex identity and lifecycle

There is deliberately no internal read identifier. `ReadState.RequestCtx` is
the caller-supplied byte string, and caller uniqueness is explicitly a caller
duty (`read_only.go:19-27`). `addRequest` uses `string(Entries[0].Data)` as both
map key and queue value; an already-pending duplicate is silently ignored
(`read_only.go:48-59`). A follower forwards MsgReadIndex to its known leader
without attaching a term (`raft.go:356-360`, `raft.go:1068-1075`). A leader of a
multi-node group first requires a committed entry from its own term. In safe
mode it captures the current commit index and broadcasts the caller context on
heartbeats (`raft.go:824-838`). `recvAck` records unique remote node IDs and
adds one implicit self acknowledgement (`read_only.go:61-73`). Once a context
reaches quorum, `advance` removes and returns the entire queue prefix ending at
that context (`read_only.go:75-108`), and the leader produces either a local
ReadState or a MsgReadIndexResp using each stored original request
(`raft.go:924-932`). Exact-old cleanup calls `delete` with
`string(rs.req.Context)` (`read_only.go:100-104`) although public requests put
the key in `Entries[0].Data` (`node.go:502-504`); the V0 preserves the stale
pending-map entry rather than silently repairing it. The Node's next Ready contains those local ReadStates and
clears the internal slice after delivery (`node.go:355-373`, `node.go:521-523`).

The model must therefore keep context, captured index, acknowledgement set,
original requester, and FIFO position separate, but must not synthesize a new
identity or reject duplicate caller contexts beyond the exact-old behavior.

## Failure assumptions

- Crash-stop/restart loses volatile raft state and resumes from the last
  application-persisted HardState/log represented at a Ready boundary.
- Messages can be delayed, reordered, or lost; they are not corrupted or
  forged. The supplied `rafttest` transport drops on disconnect, configured
  probability, or full queue and may delay before delivery
  (`rafttest/network.go:81-119`).
- No Byzantine behavior, disk corruption, unbounded clock-skew proof, snapshot
  contents, or dynamic membership is modeled.
- Logical election/heartbeat timeouts are nondeterministic MC triggers, bounded
  only in the MC wrapper.

## Properties and non-vacuity obligations

The neutral properties are TypeOK, ElectionSafety, LogMatching,
CommittedPrefixAgreement, bounded LeaderCompleteness, CommitWithinLog,
MessagesWellFormed, ReadDeliveryJustified, and ReadyNoInvention. Reachability
operators/counters must show at least one election, leader, proposal, append
delivery, commit, safe-read enqueue, read quorum, Ready read publication,
heartbeat, loss, crash, and restart in the relevant bounded configurations.

## Exclusions and reviewed signals

Source TODOs around buffering config proposals, storage error handling,
snapshot retry, and container growth were reviewed but are outside this neutral
scope or not protocol-level findings (`node.go:313-316`, `storage.go:236-238`,
`raft.go:385-402`, `progress.go:224-237`). Protobuf marshal/unmarshal code is
generated representation machinery. PreVote, snapshots, membership changes,
and leader transfer are present in the source but excluded from the compact V0
model by the binding protocol boundary; their message tags remain recognized as
out of model, not repurposed.

## Build witness

The source predates modules. The reproducible GOPATH overlay pins
`github.com/golang/protobuf` v1.3.5 and `golang.org/x/net` v0.7.0. The supplied
subset also references `github.com/coreos/etcd/pkg/testutil` from an unrelated
node test; because that package is absent from the immutable input, the overlay
contains a documented minimal scheduler-only shim. It is not used by the
focused V0 tests. Go 1.23 vet rejects an old printf forwarding idiom in
`logger.go`, so old tests run with `-vet=off`; compilation and execution are
otherwise unmodified.
