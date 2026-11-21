# Instrumentation specification — etcd Raft (V0 + incremental update c780d355)

## Trace contract

The harness writes newline-delimited JSON. Every record is emitted by the real
exact-old Go transition; no record is synthesized by the test:

```text
{tag:"trace", ts:<UnixNano>, event:{name,nid,msg?,state}}
```

`event.state` contains `term`, `vote`, `role`, `leader`, `commit`, `applied`,
`logTerms`, `readQueue`, `pendingCount`, `readCount`, `readyReadCount`, and the
update-mandatory fields `pending` (every `pendingReadIndex` entry as
`{ctx, index, from, acks}`, sorted by ctx; `from` is `req.From`, with `None`
mapped to the local node as `raft.go:927` does) and `readStates` (every
`r.readStates` element as `{index, ctx}`).
`event.msg`, when present, contains the old `raftpb.Message` projection `type`,
`from`, `to`, `term`, `index`, `logTerm`, `commit`, final `entryTerm`, final
entry `value`, read `ctx`, and `reject`. For `MsgReadIndex` and
`MsgReadIndexResp` the caller context is taken from `Entries[0].Data` and
`entryTerm`/`value` are `0`/`"Nil"` (the model's read messages carry no entry). Node IDs and empty optionals use the
model value `"Nil"`. Empty queues and logs are JSON arrays, never null.

All protocol probes observe post-state after one `raft.Step` subtransition.
`ReadyPublish` is intentionally captured inside `newReady`: it observes the
publication payload and the pre-clear `readStates`; `Trace.ConsumeReady` checks
that pre-state and the corresponding model post-state after publication.

## Action-to-source mapping

| TLA+ action / event | Exact-old source boundary | Writable-copy probe | Captured reason |
|---|---|---|---|
| `Campaign` | `raft.go:570-580`, `becomeCandidate` | `raft.go:581` | incremented term, self vote, candidate role |
| `HandleVoteRequest` | `raft.go:679-781`, vote branch | `raft.go:779` | granted/rejected vote post-state and request |
| `HandleVoteResponse` | `raft.go:988-1024` | `raft.go:1024` | candidate vote tally state after poll |
| `BecomeLeader` | `raft.go:597-621` | `raft.go:623` | leader role and current-term no-op |
| `ClientProposal` | `raft.go:797-823` | `raft.go:828` | appended exact-old proposal entry |
| `HandleAppendEntries` | `raft.go:1084-1097` | `raft.go:1098` | prefix check, zero/one-entry append, commit clamp |
| `HandleAppendResponse` | `raft.go:863-902` | `raft.go:911` | progress and current-term quorum commit |
| `HandleHeartbeat` | `raft.go:1099-1102` | `raft.go:1114` | follower commit and echoed read context |
| `HandleHeartbeatResponse` | `raft.go:903-932` | `raft.go:913` | peer activity, read ack, FIFO advance |
| `ClientReadIndex` | `raft.go:824-853` | `raft.go:860` | exact caller context enqueue/broadcast |
| `CheckQuorum` | `raft.go:791-796` | `raft.go:801` | activity reset and possible step-down |
| `ReadyPublish` | `node.go:506-525`, `newReady` | `node.go:525` | produced ReadStates at Ready boundary |
| `ForwardReadIndex` (new) | `raft.go:1068-1074`, `stepFollower` MsgReadIndex | after `r.send(m)` | forwarded caller context (only when a leader is known) |
| `HandleReadIndexResponse` (new) | `raft.go:1075-1080`, `stepFollower` MsgReadIndexResp | after the ReadState append | follower ReadState index/ctx after Step term handling |
| `ClientReadIndex` / `HandleReadIndexRequest` | `raft.go:824-853` (one branch for local and forwarded) | unchanged probe | Trace maps it to `HandleReadIndexRequest` when `msg.from` differs from the node and a matching forwarded `MsgReadIndex` is in flight, else `ClientReadIndex` |

Update revision: the forwarded-read path is now instrumented (`ForwardReadIndex`,
`HandleReadIndexResponse`) and exercised by `TestSpeculaTraceForwardedRead`.

## Correlation and identity

No synthetic operation ID is added. Read correlation is exactly
`string(Entries[0].Data)` / heartbeat `Context`, following
`read_only.go:48-108`. The state projection records the queue, active pending
count, produced read count, and Ready read count. The TLA+ replay compares the
full modeled log-term sequence and those lifecycle counts after every event.

## Scenario and invocation

`TestSpeculaTraceQuorumRead` creates the exact-old in-tree three-node network,
elects node 1, commits the leader no-op, proposes and commits `v1`, executes a
safe ReadIndex for `ctx1`, and invokes `newReady`. Run it with
`harness/run.sh`; validate trace-first with `harness/validate.sh`.

The safe-read trace has 28 records: one campaign, two vote requests, one vote
response, one leader transition, eight append receipts, eight append responses,
one proposal, one read request, two heartbeat receipts, two heartbeat
responses, and one Ready publication.

`TestSpeculaTraceQuorumLoss` produces a second 15-record trace. It elects the
leader, observes append activity, then performs two quorum checks: the first
consumes recent peer activity and the second steps the leader down. Both traces
are consumed by TLC before ordinary model checking in `harness/validate.sh`.


## Update revision (c780d355): validated effects and comparison points

| Update/repair effect | Observation point | Trace predicate |
|---|---|---|
| released requests leave `pendingReadIndex` (`read_only.go:103`) | `HandleHeartbeatResponse` post-state (`defer` probe in stepLeader) | `PendingMatches` (exact ctx set, index, requester, acks, count) |
| re-registration of a freed context (`read_only.go:54-58`) | `ClientReadIndex` post-state | `PendingMatches`, `readQueue` |
| ReadState produced from the re-registered request | `HandleHeartbeatResponse` / `ReadyPublish` | `ReadStatesMatch` (index, ctx per element) |
| forwarded release and follower consumption | `HandleReadIndexResponse` post-state | `ReadStatesMatch`, term/role/leader |
| `reset()` recreates readOnly on step-down (repair R1) | `CheckQuorum` post-state | `PendingMatches`, `readQueue` |
| stale acknowledgement released a re-registered context | `HandleHeartbeatResponse` post-state of `stale_ack_reuse` | `ReadStatesMatch` + evidence oracles `TrFinalReadAckFresh`, `TrFinalReadIndexLinearizable` |

Limitation: in a three-node cluster the first peer acknowledgement completes
the quorum, so captured `acks` sets are empty at every observation point; the
acknowledgement effect is validated through the release (queue, pending, and
ReadState comparisons), not through a non-empty `acks` list.

Scenarios (all in `harness/src/specula_trace_test.go`, run by `harness/run.sh`):
`TestSpeculaTraceQuorumRead`, `TestSpeculaTraceQuorumLoss` (prior),
`TestSpeculaTraceReadReuse`, `TestSpeculaTraceForwardedRead`,
`TestSpeculaTraceStepDownWithPending`, `TestSpeculaTraceStaleAckReuse` (update).
