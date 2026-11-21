# Modeling Brief — exact-old etcd Raft core

## 1. System overview

The supplied Go tree implements the deterministic core of etcd's Raft state
machine plus a channel-based `Node` facade. It is Category A
(distributed/message-passing): one raft event loop processes logical ticks and
messages while the application persists `Ready` before sending messages
(`node.go:49-89`, `node.go:273-390`). The V0 boundary is the three-node
crash-fault protocol: election, replication, heartbeat/quorum checking,
context-keyed ReadIndex, and Ready publication. Protobuf encoding, snapshots,
membership change, leader transfer, allocation, and goroutine scheduling are
excluded. The model follows only the supplied source and has no historical or
external evidence.

## 2. Scenarios

### Scenario 1: Election and current-term commit

**Mechanism**: Terms, one vote per term, log freshness, and a leader's no-op
entry jointly constrain which values can become committed.

**Evidence**:
- Code-only: candidate transition increments term and self-votes
  (`raft.go:570-580`); vote grant checks both vote eligibility and log freshness
  (`raft.go:759-775`); leader transition appends a current-term no-op
  (`raft.go:597-621`); quorum commit accepts only an entry from the leader's
  current term (`raft.go:475-486`, `log.go:279-285`).

**Affected code paths**: `campaign`, `Step`, `stepCandidate`, `becomeLeader`,
`maybeCommit`, `raftLog.maybeCommit`.

**Suggested modeling approach**: Per-node term/vote/role/log plus granted-vote
sets; split campaign, vote request, vote response, leader transition, proposal,
append response, and Ready publication at their old-tree event boundaries.

**Priority**: High. **Rationale**: This is the safety spine shared by election
safety, log agreement, and leader completeness.

### Scenario 2: Replication under delay, rejection, and loss

**Mechanism**: A leader's per-follower Match/Next view drives append messages;
followers accept only a matching previous term and never overwrite committed
entries.

**Evidence**:
- Code-only: `sendAppend` chooses `Index`, `LogTerm`, entries, and commit from
  progress (`raft.go:367-424`); `maybeAppend` rejects a mismatched prefix and
  panics rather than replacing a committed conflict (`log.go:74-102`);
  response handling advances or backs off progress (`raft.go:863-902`,
  `progress.go:112-153`). The supplied test network explicitly drops and delays
  messages (`rafttest/network.go:81-119`, `rafttest/network.go:133-150`).

**Affected code paths**: `sendAppend`, `handleAppendEntries`,
`stepLeader(MsgAppResp)`, `Progress.maybeUpdate`, `Progress.maybeDecrTo`.

**Suggested modeling approach**: A finite in-flight message bag, explicit
delivery/loss, one-entry append messages, and bounded client proposals.

**Priority**: High. **Rationale**: Delay, reorder, rejection, and leader change
are the central cross-node interleavings in scope.

### Scenario 3: CheckQuorum heartbeat control loop

**Mechanism**: Heartbeat responses mark peers active; an election-timeout check
counts self plus active peers, clears peer activity, and steps down without a
quorum.

**Evidence**:
- Code-only: the leader's heartbeat/election counters trigger `MsgCheckQuorum`
  and `MsgBeat` (`raft.go:535-559`); response handling sets `RecentActive`
  (`raft.go:903-913`); quorum checking includes self, resets peer flags, and
  requires a majority (`raft.go:1214-1235`); loss causes follower transition
  (`raft.go:791-796`).

**Affected code paths**: `tickHeartbeat`, `stepLeader(MsgCheckQuorum)`,
`stepLeader(MsgHeartbeatResp)`, `checkQuorumActive`.

**Suggested modeling approach**: Boolean recent-active matrix and separate
heartbeat broadcast, heartbeat receipt/response, and quorum-check actions.

**Priority**: Medium. **Rationale**: It connects network faults and leadership
state and gates the lease-based read option.

### Scenario 4: Exact-old context-keyed ReadIndex lifecycle

**Mechanism**: Safe reads are keyed directly by caller context, deduplicated in
a map, ordered in a queue, acknowledged by heartbeat responses, advanced as a
FIFO prefix, then exposed through `Ready`.

**Evidence**:
- Code-only: caller context is explicitly the correlation mechanism and the
  caller must make it unique (`read_only.go:19-27`); duplicate contexts are
  ignored (`read_only.go:48-59`); peer acknowledgements plus the implicit local
  acknowledgement form the count (`read_only.go:61-73`); acknowledging one
  context releases the queued prefix, while exact-old cleanup uses
  `req.Context` although public requests are keyed by `Entries[0].Data`
  (`read_only.go:75-108`, `node.go:502-504`). A safe request is
  rejected until the leader has committed in its term, then broadcast on a
  heartbeat (`raft.go:824-838`); quorum completion produces local ReadState or a
  response (`raft.go:915-932`); `Ready` includes and then clears produced read
  states (`node.go:506-525`, `node.go:355-373`).

**Affected code paths**: `Node.ReadIndex`, `stepFollower(MsgReadIndex)`,
`stepLeader(MsgReadIndex)`, `readOnly.addRequest`, `readOnly.recvAck`,
`readOnly.advance`, `newReady`, `node.run`.

**Suggested modeling approach**: Use only a finite set of caller contexts; map
each pending context to its captured index/requester/ack set; preserve queue
order and published ReadState records. Do not invent another request ID.

**Priority**: High. **Rationale**: It is the implementation-specific behavior
the exact-old V0 must preserve for blind incremental comparison.

## 3. Modeling recommendations

### 3.1 Model

- Model each node's role, term, vote, leader, log-term sequence, commit/applied
  indexes, and a leader's Match/Next view (Scenarios 1-2).
- Model a finite message bag with old protobuf fields needed by votes, append,
  heartbeat, and read request/response (`raftpb/raft.proto:35-70`).
- Model Ready as the application boundary that persists current hard/log state,
  exposes produced reads, and permits later Advance (Scenarios 1-4).
- Model crash/restart as loss of volatile state back to the last Ready-persisted
  state; model loss and reordering by independently losing/delivering messages.
- Model CheckQuorum activity and safe-read acknowledgement membership
  (Scenarios 3-4).

### 3.2 Do not model

- Protobuf encoding and generated marshal code: no protocol-level effect.
- Snapshot contents, compaction, membership change, and leader transfer: outside
  the binding boundary for this compact V0.
- Allocation, logging, benchmarks, goroutine scheduling, and transport buffers:
  implementation/container detail outside logical-event granularity.
- A new read-request identity scheme: absent from the exact-old structures.

## 4. Proposed extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Ready persistence | durableTerm, durableVote, durableLog, readyOutstanding | Capture persist-before-send and crash recovery | 1, 2 |
| Replication progress | matchIndex, nextIndex | Drive append and quorum commit | 2 |
| Quorum activity | recentActive | CheckQuorum step-down | 3 |
| Exact-old reads | pendingReads, readQueue, producedReads, publishedReads | Context/ack/FIFO/Ready lifecycle | 4 |

## 5. Proposed invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| TypeOK | Safety | All modeled values remain well typed | all |
| ElectionSafety | Safety | At most one leader exists per term | Scenario 1 |
| LogMatching | Safety | Equal index/term implies equal prefixes | Scenarios 1-2 |
| CommittedPrefixAgreement | Safety | Committed prefixes agree pairwise | Scenario 2 |
| LeaderCompleteness | Safety | A later leader contains every earlier committed entry within bounds | Scenario 1 |
| CommitWithinLog | Safety | commit/applied do not exceed local log | Scenario 2 |
| MessagesWellFormed | Safety | In-flight old-tree messages have valid endpoints/fields | Scenarios 1-4 |
| ReadDeliveryJustified | Safety | Every published safe read has a recorded quorum justification for its context/index | Scenario 4 |
| ReadyNoInvention | Safety | Every published read came from a produced old-tree transition | Scenario 4 |

## 6. Findings pending verification

### 6.1 Model-checkable

| ID | Description | Expected invariant violation | Scenario |
|---|---|---|---|
| MC1 | Can message loss/reordering and repeated elections produce two leaders in one term or divergent committed prefixes? | ElectionSafety / CommittedPrefixAgreement | 1, 2 |
| MC2 | Can CheckQuorum activity reset/step-down interleave with delayed heartbeat responses while a leader remains incorrectly authoritative? | ElectionSafety / ReadDeliveryJustified | 3, 4 |
| MC3 | Can duplicate contexts or FIFO-prefix advancement publish a read not backed by the pending request's own quorum acknowledgement and captured commit index? | ReadDeliveryJustified / ReadyNoInvention | 4 |

### 6.2 Test-verifiable

| ID | Description | Suggested test approach |
|---|---|---|
| TV1 | Ready exposes and clears ReadStates at the delivery boundary | Instrument `node.run` and exercise `TestNodeReadIndex`-style flow |

### 6.3 Code-review-only

| ID | Description | Suggested action |
|---|---|---|
| CR1 | Caller context is the only old-tree request key, and uniqueness is a caller duty | Preserve exactly; do not add validation absent from source |

## 7. Reference pointers

- Detailed code-only analysis: `analysis-report.md`
- Core state machine: `raft.go:209-1253`
- Read lifecycle: `read_only.go:19-118`
- Ready boundary: `node.go:49-89`, `node.go:273-390`, `node.go:502-525`
- Log/progress: `log.go:24-358`, `progress.go:35-180`
- Message schema: `raftpb/raft.proto:35-75`


## 8. Incremental update V1 (`update` revision)

Disposition: **MODEL_CHANGE_REQUIRED** (see `analysis-report.md`, "Incremental
analysis"). The source change is the delete key in `readOnly.advance`
(read_only.go:100-104); the reference now deletes every released request.
Scenario 4 above is superseded where it says the V0 preserves the stale
pending-map entry.

### Update Scenarios

| ID | Path | Code | Model Actions | Expected / property |
|---|---|---|---|---|
| US1 | release frees request | read_only.go:100-104 | `HandleHeartbeatResponse` | map and queue both empty after release (`PendingMatchesQueue`) |
| US2 | released context admitted again in same term | read_only.go:52-58 | `ClientReadIndex`, `HandleReadIndexRequest` | new instance pending with new index (`HuntReadReenqueue`) |
| US3 | delayed ack from earlier instance releases new instance | read_only.go:64-73, raft.go:915-932 | `HandleHeartbeat`, `HandleHeartbeatResponse` | ack must postdate request (`ReadDeliveryJustifiedFresh`) |
| US4 | US3 after a newer leader committed | raft.go:475-486, 919-931; node.go:154-157 | elections, `HandleAppendResponse`, `ReadyPublish` | read index covers prior commits (`ReadIndexFreshness`) |
| US5 | reset discards pending reads | raft.go:489-511, 561-603, 791-796 | `Campaign`, `BecomeLeader`, step-down handlers, `CheckQuorum` | queue/map cleared (`PendingMatchesQueue`, trace `read_stepdown`) |
| US6 | forwarded read released and consumed | raft.go:926-931, 1068-1080 | `ForwardReadIndex`, `HandleReadIndexRequest`, `HandleReadIndexResponse` | justification preserved after delete (`ReadDeliveryJustified*`) |

### Findings pending verification (update)

| ID | Description | Expected violation | Scenario |
|---|---|---|---|
| MC4 | Same-context re-request after release counts an acknowledgement produced for the earlier instance | `ReadDeliveryJustifiedFresh` | US3 |
| MC5 | Same, with a newer leader having committed: stale ReadState delivered | `ReadIndexFreshness` | US4 |

Code-review note (old revision, resolved by update): exact-old stale entries made
a same-context request after release silently ignored forever (read_only.go:53-56
with old line 103) and leaked memory; the new test `TestRaftFreesReadOnlyMem`
(raft_test.go:1249-1296) asserts the freeing.

### Exclusions retained

ReadOnlyLeaseBased, PreVote, snapshots, membership change, leader transfer, and
the empty-context key `""` (outside `ReadContexts`) remain excluded as in V0.

### Model-checking outcome (V1)

MC4 and MC5 were both found as actual counterexamples (MC-1 in
`spec/findings.json`): `ReadDeliveryJustifiedFresh` in `Update_focused.cfg`
(22 states) and `Update_focused_reset.cfg` (21 states, periodic-heartbeat
variant), `ReadIndexFreshness` in `Update_hunt_us4_guided.cfg` (37 states, full
MCSpec with a search-pruning constraint). Reproduced on the real update revision
(`spec/confirmation-MC-1.md`); not present on the baseline revision.
