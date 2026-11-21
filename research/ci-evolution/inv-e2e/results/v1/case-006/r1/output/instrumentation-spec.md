# Instrumentation specification — etcd Raft (V0, rebased for the `update` revision as V1)

## Trace contract

The harness writes newline-delimited JSON. Every record is emitted by the real
exact-old Go transition; no record is synthesized by the test:

```text
{tag:"trace", ts:<UnixNano>, event:{name,nid,msg?,state}}
```

`event.state` contains `term`, `vote`, `role`, `leader`, `commit`, `applied`,
`logTerms`, `readQueue`, `pendingCount`, `readCount`, and `readyReadCount`.
`event.msg`, when present, contains the old `raftpb.Message` projection `type`,
`from`, `to`, `term`, `index`, `logTerm`, `commit`, final `entryTerm`, final
entry `value`, read `ctx`, and `reject`. Node IDs and empty optionals use the
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
| `ForwardReadIndex` (V1) | `raft.go:1068-1074`, stepFollower `MsgReadIndex` | after `r.send(m)` | forwarded caller context to known leader |
| `HandleReadIndexResponse` (V1) | `raft.go:1075-1080`, stepFollower `MsgReadIndexResp` | after `readStates` append | follower ReadState from the leader's release |

The base spec additionally models follower `MsgReadIndex` forwarding and
`MsgReadIndexResp` receipt from the exact-old branches at `raft.go:1068-1075`
and `raft.go:1033-1049`. Those paths have model-checking reachability evidence;
the fresh concrete trace concentrates on the local safe-read path.

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

## V1 rebase for the `update` revision

Source drift: none in instrumented files (`raft.go`, `node.go` are identical in
`baseline` and `update`); the V0 patch applied unchanged. Changes:

- **Densified update probes.** `ForwardReadIndex` and `HandleReadIndexResponse`
  observe the forwarded consumer of the changed release path
  (`read_only.go:100-104` -> `raft.go:926-931` -> `raft.go:1075-1080`).
- **Capture fix.** For `MsgReadIndex`/`MsgReadIndexResp` the caller context
  lives in `Entries[0].Data`; `msg.ctx` now carries it for both types and
  `msg.value`/`msg.entryTerm` are `"Nil"`/0 (they are not proposal values).
- **Update fields.** No new field was needed: the changed effect is observed by
  the existing `state.pendingCount` (`len(pendingReadIndex)`) and
  `state.readQueue`, compared by `ValidateCorePost` after every event, and by
  `state.readCount`/`readyReadCount` at the Ready boundary.
  `HandleHeartbeatResponse` is captured by `defer` at the end of the
  stepLeader case, i.e. after `advance` deleted the released entries.

Where each update effect is compared (Trace.tla):

| Effect | Trace predicate | Observation point |
|---|---|---|
| released request deleted (US1) | `ValidateCorePost`: active pending count = `pendingCount`, `readQueue` | `HandleHeartbeatResponse` post-state |
| same-context re-enqueue (US2) | same, plus `Len(producedReads)` = `readCount` | `ClientReadIndex` post-state |
| stale ack releases new instance (US3) | queue/pending/readCount after the delayed ack | `HandleHeartbeatResponse` post-state |
| reset discards reads (US5) | queue/pending after step-down | `CheckQuorum` post-state |
| forwarded release consumed (US6) | follower `readCount` | `HandleReadIndexResponse` post-state |
| published reads (all) | `ConsumeReady` pre/post read counts | `ReadyPublish` |

Fresh scenarios (all in `harness/patches/instrumentation.patch`,
`specula_trace_test.go`): `TestSpeculaTraceQuorumRead` and
`TestSpeculaTraceQuorumLoss` (prior, unchanged), `TestSpeculaTraceReadReuse`
(US1/US2/US3/US6), `TestSpeculaTraceStaleRead` (US4),
`TestSpeculaTraceReadStepDown` (US5). Messages are held or dropped only by not
delivering them (manual `Step` relay or the in-tree network's
`isolate`/`recover`); no state is synthesized.

Known observation gaps: `BroadcastHeartbeat` (MsgBeat) and `ReadyAdvance` have
no probe (as in V0); the higher-term reset branches of `HandleVoteRequest`/
`HandleAppendEntries`/`HandleHeartbeat` are observed only with empty readOnly
(the non-empty discard is observed through `CheckQuorum`); the higher-term
branch of `HandleReadIndexResponse` is not observed.
