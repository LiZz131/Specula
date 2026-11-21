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

---

# V1 incremental analysis — updated source

## Inputs and identity

| Item | Identity |
|---|---|
| Old source | neutral commit `baseline` 7289d1c5e049933b90a9692bbf508714bee02fce; changed files equal `/work/old-source` |
| New source | neutral commit `update` c780d355cfeae6ee6be52c50c1f0bd7d30c6657a; changed files equal `/work/new-source` |
| Prior suite | `/work/previous/.specula-output` (V0, exact-old; trace + bounded MC, 0 findings, limited coverage) |
| Diff | `read_only.go:103` delete key `string(rs.req.Context)` -> `string(rs.req.Entries[0].Data)`; `raft_test.go` adds `TestRaftFreesReadOnlyMem` |

Category stays A (no concurrency/communication change). No history, issue, or
external research was performed (blind run); all evidence below is from the
two supplied revisions and executions of them.

## Changed function in context

`readOnly.advance` (read_only.go:78-109) is called only from
`stepLeader(MsgHeartbeatResp)` after `recvAck` reaches quorum
(raft.go:915-932). Its producers/consumers:

- key producer `addRequest` (read_only.go:52-58): key `string(m.Entries[0].Data)`,
  duplicate guard `if _, ok := pendingReadIndex[ctx]; ok { return }`;
- request sources: `node.ReadIndex` (node.go:502-504) and `RawNode.ReadIndex`
  (rawnode.go:262-263) build `{Type: MsgReadIndex, Entries: [{Data: rctx}]}`
  with no `Context`; a follower forwards the same message (raft.go:1068-1074),
  and `send` does not add a Context (raft.go:343-365);
- acknowledgement path: `bcastHeartbeatWithCtx(m.Entries[0].Data)` at enqueue
  (raft.go:836-837) and MsgBeat heartbeats carrying `lastPendingRequestCtx`
  (raft.go:457-464, read_only.go:111-118); followers echo `Context`
  (raft.go:1099-1102); `recvAck` matches by `string(m.Context)` only
  (read_only.go:64-73);
- release consumers: local `readStates` -> `Ready.ReadStates`
  (raft.go:926-929, node.go:521-523) and remote `MsgReadIndexResp`
  (raft.go:930, 1075-1080);
- lifecycle reset: `raft.reset` replaces `readOnly` (raft.go:510) on every
  becomeFollower/becomeCandidate/becomeLeader.

## Projection of each changed branch onto the model vocabulary

| Branch | Exact-old | Updated | Model effect |
|---|---|---|---|
| Release of FIFO prefix | `delete(…, string(req.Context))` = `delete(…, "")` for every real request: released entries stay in `pendingReadIndex` | released entries deleted | `pendingReads[i][c].active` after release: TRUE -> FALSE (**differs**) |
| Later request with a released context | duplicate guard hits stale entry: ignored, never answered (heartbeats still broadcast) | enqueued again, served after quorum | enablement of enqueue in `ProcessReadIndex` (**differs**) |
| Later response echoing a released context | `recvAck` updates the stale entry; `advance` finds nothing; no effect | no entry: `recvAck` returns 0; if re-enqueued, counted for the newest request | new reachable release path (**differs**) |
| Response generated before re-enqueue, delivered after | impossible (no re-enqueue) | counted toward the new request's quorum | new: acknowledgement that predates the request (**differs**) |
| Empty request context `""` queued behind a released request | old delete of `""` orphans the queued empty-context entry; next advance panics "cannot find corresponding read state from pending map" | no orphaning | outside model domain (`ReadContexts` non-empty; empty-context responses are never acked, raft.go:915) — recorded, not modeled |
| `lastPendingRequestCtx`, queue order, index capture | unchanged | unchanged | unchanged |

Executable confirmation (`harness/controls.sh`, `spec/output/controls.log`):
on the baseline a reused context is never answered and the stale entry
remains (pending=1); on the update it is re-enqueued and answered; a delayed
first-round response releases the second request on the update only; the
empty-context sequence panics on the baseline only; the updated upstream test
`TestRaftFreesReadOnlyMem` fails on the baseline source
(`len(pendingReadIndex) = 1, want 0`).

**Decision: MODEL_CHANGE_REQUIRED.** The update changes modeled state
(`pendingReads` after release), enablement (enqueue of a released context)
and the set of acknowledgements that can justify a release. Same scope and
granularity as V0; no new variables are needed for behavior.

## Existing V0 model defects repaired (source unchanged)

1. `raft.reset` (raft.go:489-511) installs a new `readOnly`; V0 kept
   `pendingReads`/`readQueue` across Campaign, BecomeLeader, higher-term
   vote/append/heartbeat, same-term candidate append/heartbeat
   (raft.go:1002-1007) and CheckQuorum step-down (raft.go:794). This affects
   the update directly (a stale entry kept by the model would block reuse the
   code allows, and stale queue entries could be released in a later term).
   Validated by fresh traces `step_down_reads` and `higher_term_reads`; the V0
   model rejects both at the reset event.
2. `BecomeLeader` must rebuild progress (raft.go:501-508); V0 kept stale
   `matchIndex` (fed into `CommitCandidate`), votes and RecentActive.
3. V0 `HandleReadIndexResponse` read its ghost justification from the
   leader's (stale) pending entry; now from a ghost release history.

Independent limitations recorded, not changed: higher-term responses are not
consumed (only delayed/lost), vote-rejection quorum step-down is not modeled,
`HandleReadIndexResponse` accepts any role/term, rejected appends are not
retried. None adds behavior on the update path; they can only hide behavior.

## Update Scenarios (Chapter 3)

- **S6a reuse lifecycle** — old producer (heartbeat acks) -> affected
  advance/delete -> old consumer (duplicate guard) admits the same context
  again. Expectation: the pending map equals the queue; reuse is served.
- **S6b delayed acknowledgement across reuse** — a response generated for the
  earlier request is delivered after the context is enqueued again
  (message delay is in the fault model, rafttest/network.go:81-119). `recvAck`
  correlates by context only, so it is counted for the new request. Question:
  can the new release be justified only by acknowledgements that predate it,
  and can that produce a read index below an index another leader already
  committed (stale read) once a partition lets a newer leader commit?
- **S6c forwarded reuse** — follower-forwarded requests use the same key and
  delete; remote `MsgReadIndexResp` consumer.
- **S6d reset interaction** — step-down/re-election clears pending reads; stale
  previous-term responses are filtered by the term check (raft.go:713-734).

Properties: `UpdPendingQueueAgreement` (new), `UpdQueueNoDuplicates`
(structural), `UpdReadAckAfterEnqueue` (revised form of the V0 read-justification
property: a quorum of acknowledgements generated after the request was
accepted), `UpdReadIndexLinearizable` (interaction/consumer-visible),
`UpdPublishedFromRelease` (old consumers publish only released reads); V0
properties retained.

Finding lineage: V0 had no findings. V0 CR1 (caller context is the only key;
uniqueness is a caller duty) is the relevant premise. ReadState's comment
(read_only.go:19-23) makes differentiating returned states by `RequestCtx` a
caller duty "eg. given a unique id"; it does not forbid using a context again
after its ReadState was delivered. In the exact-old code such a reuse was
silently ignored (a liveness gap), which also masked S6b; the update removes
that mask.

## V1 model-checking classification (Part 3)

| Counterexample | Property | Classification | Evidence |
|---|---|---|---|
| `superseded-hunt-s6-stale-ack-r1` | `UpdReadAckFreshness` (r1) | Case A: property demanded responses to heartbeats *sent* for the incarnation; a delayed first-round heartbeat processed after re-enqueue still confirms leadership after acceptance. Revised to `UpdReadAckAfterEnqueue`. | `spec/changelog.md` |
| `superseded-update-focused-nk-precrashfix` | `MCLeaderCompleteness` | Case B (V0 defect, not update-related): an unpersisted `MsgAppResp` survived the sender's crash and later passed a length-only durability gate. Code loses unsent `r.msgs` on crash. `Crash` repaired. | `spec/changelog.md` |
| `hunt-s6-stale-ack`, `update-full`, `update-focused` | `UpdReadAckAfterEnqueue` | Case C candidate (MC-1 mechanism) | `spec/bug-report.md` |
| `hunt-s6-linearizable-guided-v2` | `UpdReadIndexLinearizable` | Case C candidate (MC-1 consequence) | `spec/bug-report.md` |

MC-1 fidelity check (tla-checking-workflow spec-fidelity checklist): every
precondition was compared with the implementation —
(1) the reused context is accepted: `addRequest` guard only consults
`pendingReadIndex`, now cleared by `advance` (read_only.go:54-56, 100-105);
(2) the delayed response is accepted: same term (raft.go:679-736 drops only
other terms), `recvAck` matches by context only (read_only.go:64-73), no
round/sequence check exists; (3) the stale leader still serves: no lease or
quorum check gates `stepLeader(MsgReadIndex)` besides the current-term commit
(raft.go:825-829), CheckQuorum is periodic (raft.go:535-559) and the model's
nondeterministic CheckQuorum is never forced; (4) message delay/reordering is
in the fault model (rafttest/network.go:81-119). A real updated-code
execution of the same schedule conforms to the model (`stale_read_reuse`
trace) and returns `ReadState{Index: 2}` after index 4 was committed in term 2;
the baseline never answers the reused read. Attribution: update-related —
the update removed the exact-old mask (stale map entry) that silently dropped
reused contexts. Premise: caller reuse of a RequestCtx after its previous
ReadState was produced (not forbidden by read_only.go:19-23; unreachable with
globally unique contexts). Formal confirmation (Part 4) was not run in this
task.
