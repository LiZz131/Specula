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
