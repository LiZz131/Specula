# Incremental analysis — `update` revision (V1)

## Inputs and identity

- Old: `/work/old-source/` (= artifact commit `7289d1c5` `baseline`), prior suite
  `/work/previous/.specula-output/` (V0, unresolved errors: none; coverage
  limited by bounds/timeouts as recorded there).
- New: `/work/new-source/` (= artifact commit `c780d355` `update`).
- Diff: `read_only.go` one line (advance delete key); `raft_test.go` adds
  `TestRaftFreesReadOnlyMem`. No other file changed (`git diff --stat`).
- Category unchanged: A (distributed/message-passing, crash faults).

## Changed behaviour (Chapter 1 projection)

`readOnly.advance` (read_only.go:78-109) releases the queue prefix ending at the
acknowledged context. Old line 103 deleted `pendingReadIndex[string(rs.req.Context)]`;
new line 103 deletes `pendingReadIndex[string(rs.req.Entries[0].Data)]`.
`addRequest` keys requests by `string(m.Entries[0].Data)` (read_only.go:52-58) and
every MsgReadIndex built by `node.ReadIndex`/`RawNode.ReadIndex`
(node.go:502-504, rawnode.go:262-264) and forwarded by `stepFollower`
(raft.go:1068-1074) carries no `Context`, so the old delete removed key `""`
(no entry in the modeled domain) and released requests stayed in the map.

Projection on the existing vocabulary (`pendingReads`, `readQueue`, acks,
messages, produced/published reads):

| Changed branch / consumer | Old post-state | New post-state | Modeled? |
|---|---|---|---|
| `HandleHeartbeatResponse` quorum release (read_only.go:100-104) | released ctx stays `active` (stale) | released ctx `EmptyPending` | yes, `pendingReads`, trace `pendingCount` |
| later ack for a released ctx (`recvAck`, read_only.go:64-73) | stale entry gains ack; `advance` finds nothing | `recvAck` returns 0, nothing changes | yes |
| `ProcessReadIndex` dedup (read_only.go:53-56) for a released ctx | request ignored (never served) | request enqueued again with a new index | yes |
| ack from the earlier instance's heartbeat round | cannot match (ctx never re-enqueued in a term) | counts toward the re-enqueued instance | yes |

The projected post-state sets differ, so the disposition is
**MODEL_CHANGE_REQUIRED**. All callers of the changed function were checked:
`advance` has one caller (raft.go:924); `pendingReadIndex` is read only by
`addRequest`, `recvAck`, `advance`; `reset()` (raft.go:510) replaces the whole
struct. No other call site implements the same mechanism.

## Existing model defects found while rechecking the changed mechanism

These are repairs of the reference (source delta disposition unchanged):

1. **readOnly reset (raft.go:489-511).** `reset()` assigns
   `r.readOnly = newReadOnly(...)` and is called by `becomeFollower`,
   `becomeCandidate`, `becomeLeader` (raft.go:561-603). V0 cleared read state
   only on `Restart`, so a stepped-down/re-elected leader kept stale pending
   reads and queue. Repaired in `Campaign`, `BecomeLeader`,
   `HandleVoteRequest`/`HandleAppendEntries`/`HandleHeartbeat` (higher term, or
   same-term candidate), `CheckQuorum` step-down, and higher-term
   `HandleReadIndexResponse`. Directly affects the update's pending-map lifecycle.
2. **Forwarded read response (raft.go:1075-1080, 679-734).** V0 accepted
   `MsgReadIndexResp` at any term/role and took its justification from the
   leader's *live* pending map, which only worked because exact-old entries were
   never deleted. Repaired to the Step term rules and to a ghost release log
   (`readReleases`).
3. Ghost-only additions for properties (no enabledness effect): `floor` (global
   commit watermark at request acceptance), `fresh` (peers that processed a
   heartbeat for the context while this instance was pending), `readReleases`.

Recorded but **not** repaired (independent of the update, outside its
interactions): `reset()` also re-creates leader `Progress` (Match/Next/
RecentActive) which V0's `BecomeLeader` keeps; no append retransmission after a
rejection; lower-term heartbeats/appends are answered with a higher-term response
instead of the checkQuorum `MsgAppResp`/ignore branches; higher-term responses do
not step a leader down. None of these changes read-request lifecycle semantics
used by the update properties.

## Update-focused deep analysis (Chapter 3)

Interaction paths (code-backed):

- *old producer → changed Action → old consumer*: `ClientReadIndex`/forwarded
  `HandleReadIndexRequest` → `HandleHeartbeatResponse` release+delete →
  `ReadyPublish` / `MsgReadIndexResp` → follower `HandleReadIndexResponse`.
- *changed Action → old producer → changed Action*: after a release the same
  context is admitted again (read_only.go:53-58) in the same term; any
  `MsgHeartbeatResp` still in flight from the earlier instance's heartbeat round
  carries the same `Context` and is counted by `recvAck` for the new instance
  (read_only.go:64-73), which can satisfy `ackCount >= quorum` (raft.go:919-924)
  without any acknowledgement produced after the new request was accepted.
- *+ leadership change*: if, between the first instance's heartbeat round and
  the re-request, the acknowledging follower moved to a newer term and a newer
  leader committed entries, the old leader (still leader in its term) releases
  the re-enqueued request at its stale commit index. The API promises that the
  read index covers reads/writes completed before the request
  (node.go:154-157, rawnode.go:258-261, README.md:27-29); this path breaks it.
- *reset sites*: step-down/candidacy/re-election discard pending reads
  (raft.go:510); acknowledgements from a previous term never match (term check
  raft.go:713-734 / model `m.term = term[i]`).
- *crash/restart*: `Restart` rebuilds readOnly (`newRaft`, raft.go:297); covered
  by EnvUpdate/discharge.

Old-revision contrast: with stale entries, a same-term re-request of a released
context is silently dropped (liveness defect: the caller waits forever), but no
stale acknowledgement can be attributed to a new instance. The update fixes the
memory/liveness side and introduces the cross-instance acknowledgement hazard.
Requirement evidence that same-context requests are legitimate API use: the
`ReadIndex` API places no uniqueness precondition (node.go:154-158,
rawnode.go:258-264); the uniqueness remark in read_only.go:19-23 is about the
caller *differentiating* returned states; `TestReadOnlyForNewLeader`
(raft_test.go:1949-1970) issues the same `wctx` twice and expects the second to
be served.

Properties and decisions: see `spec/invariant-evidence.json`
(PendingMatchesQueue/ReadQueueDistinct added; ReadDeliveryJustified revised to
ReadDeliveryJustifiedFresh; ReadIndexFreshness added; TypeOK representation
change; ReadyNoInvention kept). No property was weakened.

---

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
