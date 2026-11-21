# Modeling Brief — etcd Raft core (V0 exact-old + incremental update c780d355)

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
  context releases the queued prefix. Exact-old cleanup used `req.Context`
  although public requests are keyed by `Entries[0].Data`; the updated
  revision deletes `string(rs.req.Entries[0].Data)` and therefore frees every
  released request (`read_only.go:100-105`, `node.go:502-504`). See §8. A safe request is
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


## 8. Incremental update c780d355 (baseline 7289d1c5 -> update)

**Category**: unchanged (A, distributed/message-passing, crash faults).

**Source delta** (`git diff 7289d1c c780d35`): one line in `read_only.go`
(`advance`, line 103) plus a new test `TestRaftFreesReadOnlyMem`
(`raft_test.go:1249-1296`).

```diff
-			delete(ro.pendingReadIndex, string(rs.req.Context))
+			delete(ro.pendingReadIndex, string(rs.req.Entries[0].Data))
```

**Disposition: MODEL_CHANGE_REQUIRED.** Every request that reaches
`addRequest` is keyed by `string(m.Entries[0].Data)` (`read_only.go:53`), and
`MsgReadIndex` never carries `Context` (`node.go:502-504`,
`rawnode.go:262-264`, forwarding at `raft.go:1068-1074`). Projected onto the
model, the released contexts' `pendingReads[i][c].active` is TRUE after
`HandleHeartbeatResponse` in the old revision and FALSE in the new one. This
changes a modeled variable and the enablement of two old Actions:
`ProcessReadIndex`'s duplicate guard (`read_only.go:54-56`) and
`recvAck`'s lookup for late acknowledgements (`read_only.go:65-68`).

**Model repairs required to verify the update** (independent V0 defects,
implementation-backed, recorded separately from the source delta):

- R1: `raft.reset()` recreates `readOnly` (`raft.go:510`) in becomeFollower,
  becomeCandidate and becomeLeader; V0 never cleared read state on a role
  change, so a stale queue/pending entry could survive into a later term in
  the model only.
- R2: V0 `HandleReadIndexResponse` derived the forwarded read's evidence from
  the leader's *live* pending map, which only worked because exact-old never
  freed entries. It now uses the leader-side release history.
- R3: `HandleReadIndexResponse` now follows `raft.Step` term handling
  (`raft.go:679-735`) and only a follower appends the ReadState
  (`raft.go:1075-1080`).

### Scenario U1: Release frees pending state (update intent)

**Mechanism**: `advance` now deletes every released request; the pending map
and the FIFO queue name the same contexts.
**Evidence**: `read_only.go:100-105`; new test assertions
`raft_test.go:1286-1295`.
**Model**: `HandleHeartbeatResponse` clears released contexts; property
`Update!UpdPendingMatchesQueue`; canary `HuntReadFreed`.

### Scenario U2: Same-term context reuse meets a delayed earlier acknowledgement

**Mechanism**: after a context is released and freed, the same caller context
can be registered again by the same leader in the same term
(`read_only.go:54-58`). `recvAck` identifies the request only by
`m.Context` (`read_only.go:65`) and heartbeat responses carry only the echoed
context and term (`raft.go:1112-1115`). A heartbeat response produced for the
*earlier* registration, still in flight, is therefore counted for the new
registration (`raft.go:919-924`). In the exact-old revision the stale entry
made the second registration a no-op (the request was never answered), so
this interaction is new with the update.
**Evidence**: code-only (`read_only.go:52-73`, `raft.go:836-837`,
`raft.go:915-932`); the API leaves context choice to the caller
(`read_only.go:19-23`), and in-tree tests reuse one context for different or
repeated requests (`node_test.go:206-230`, `raft_test.go:1948-1970`).
**Model**: ghost registration stamps on pending entries and heartbeat
responses; property `Update!UpdReadAckFresh`; canaries `HuntReadReuse`,
`HuntStaleAck`, `HuntReuseServed`.
**Priority**: High.

### Scenario U3: Consequence — stale read index after a newer-term commit

**Mechanism**: if, between the earlier acknowledgement and the re-registration,
the other servers elect a newer leader and commit an entry, the old leader can
still release the re-registered read with its own (older) commit index,
violating the ReadIndex contract (`node.go:155-157`, `raft.go:47-48`).
**Model**: ghost `gcommit` (highest committed index at registration);
property `Update!UpdReadIndexLinearizable`.
**Priority**: High.

### Scenario U4: Forwarded reads and role changes around freed entries

**Mechanism**: remote requests are released into `MsgReadIndexResp`
(`raft.go:929-931`), consumed by followers (`raft.go:1075-1080`); leaders that
step down or change term recreate `readOnly` (`raft.go:510`).
**Model**: repairs R1-R3; properties `UpdPendingMatchesQueue`,
`UpdReadStateOnlyAtLeader`, `ReadDeliveryJustified`; canaries
`HuntForwardedFreedRead`, `HuntReadLeaderSteppedDown`.

### Update property decisions (details: `spec/invariant-evidence.json`)

| Property | Decision | Placement |
|---|---|---|
| ReadDeliveryJustified | keep (watch touched) | base |
| ReadyNoInvention | keep (watch touched) | base |
| TypeOK, MessagesWellFormed | representation-only revision (ghost fields) | base |
| UpdPendingMatchesQueue | add (update intent) | Update.tla |
| UpdReadAckFresh | add (instance-bound acknowledgement) | Update.tla |
| UpdReadIndexLinearizable | add (consequence) | Update.tla |
| UpdReadStateOnlyAtLeader | add (structural guard for R1) | Update.tla |

### Findings pending verification (update)

| ID | Description | Expected violation | Scenario |
|---|---|---|---|
| MC-U1 | Reused context released by a pre-registration acknowledgement | UpdReadAckFresh | U2 |
| MC-U2 | Stale read index returned after newer-term commit | UpdReadIndexLinearizable | U3 |

Code-review-only (outside model granularity): the delete key is recomputed
from the retained request bytes at release time (`read_only.go:103`) while
the map key was copied at registration (`read_only.go:53`); a caller that
mutates its `rctx` buffer after `ReadIndex` could make the two differ. Byte
aliasing is an implementation-container detail excluded by the scope; no model
or finding is derived from it.

### Exclusions retained

Protobuf encoding, snapshots, membership change, leader transfer, PreVote,
lease-based reads (the update touches only the safe-read cleanup path),
allocation, and goroutine scheduling remain excluded as in V0.
