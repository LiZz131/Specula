# Instrumentation specification — etcd Raft V1 (updated source; rebased from V0)

## Trace contract

The harness writes newline-delimited JSON. Every record is emitted by the real
exact-old Go transition; no record is synthesized by the test:

```text
{tag:"trace", ts:<UnixNano>, event:{name,nid,msg?,state}}
```

`event.state` contains `term`, `vote`, `role`, `leader`, `commit`, `applied`,
`logTerms`, `readQueue`, `pendingCount`, `pendingCtxs`, `readCount`,
`readStates`, and `readyReadCount`. V1 mandatory update fields:
`pendingCtxs` (sorted keys of `readOnly.pendingReadIndex`, read_only.go:35-39)
and `readStates` (`[{index, ctx}]` of `r.readStates`, read_only.go:24-27);
`Trace.tla` compares both exactly after every event.
`event.msg`, when present, contains the old `raftpb.Message` projection `type`,
`from`, `to`, `term`, `index`, `logTerm`, `commit`, final `entryTerm`, final
entry `value`, read `ctx`, and `reject`. For MsgReadIndex and MsgReadIndexResp
the read `ctx` is `Entries[0].Data` and `value` is `"Nil"` (the entry carries the
caller context, not a log value). Node IDs and empty optionals use the
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
| `HandleHeartbeatResponse` | `raft.go:903-932`; `read_only.go:64-109` | deferred at case entry (post-state) | peer activity, read ack, FIFO advance and **updated delete of released keys** (read_only.go:100-105) |
| `ClientReadIndex` | `raft.go:824-853`, local origin (`From` = None or self) | `raft.go:` end of MsgReadIndex case | context enqueue (or duplicate) and heartbeat broadcast |
| `HandleReadIndexRequest` | `raft.go:824-853`, remote origin (forwarded) | same probe, `From` = peer | forwarded request enqueue; consumes the model's MsgReadIndex |
| `ForwardReadIndex` | `raft.go:1068-1074` | after `r.send(m)` | follower forwards to `r.lead` (no term attached) |
| `HandleReadIndexResponse` | `raft.go:1075-1080` | after `readStates` append | remote read state produced at the follower |
| `BroadcastHeartbeat` | `raft.go:457-464` (MsgBeat) | after `r.bcastHeartbeat()` | heartbeat with `lastPendingRequestCtx` |
| `CheckQuorum` | `raft.go:791-796` | `raft.go:801` | activity reset and possible step-down |
| `ReadyPublish` | `node.go:506-525`, `newReady` | `node.go:525` | produced ReadStates at Ready boundary |

Probe line numbers refer to the instrumented copy produced by
`harness/apply.sh`; `harness/patches/instrumentation.patch` is the rebased V0
patch plus the V1 probes (V0 patch applied without drift).

## Correlation and identity

No synthetic operation ID is added to the implementation. Read correlation is
exactly `string(Entries[0].Data)` / heartbeat `Context`, following
read_only.go:52-109. The model's incarnation tag (`rinc`, `readInc`) is ghost
evidence; trace wrappers for heartbeat, heartbeat-response and forwarded-read
events consume the in-flight model message whose observable fields equal the
traced message (ghost tag ignored), so message existence is also checked.

## Update observation points (Validation 1 §3)

| Layer | Probe / field | Trace predicate |
|---|---|---|
| producer/setup | `ClientReadIndex`/`HandleReadIndexRequest` + `pendingCtxs`, `readQueue` | `ValidateCorePost` exact key set and queue |
| affected effect | `HandleHeartbeatResponse` (post-state) + `pendingCtxs`, `readQueue`, `readStates` | key set after delete; released index/ctx sequence |
| first consumer | duplicate guard on reuse (`read_reuse`, `forwarded_read`), `ReadyPublish` (`readStates`, `readyReadCount`), `HandleReadIndexResponse` | queue/key set on re-enqueue; published index/ctx |
| fault boundary | delayed first-round response (`delayed_ack`); reset on step-down/higher term (`step_down_reads`, `higher_term_reads`) | key set/queue at the reset events; ghost acknowledgement timing (`UpdReadAckAfterEnqueue`) |

## Scenarios and invocation

`harness/run.sh` (one command) materializes the `update` commit, applies the
patch, builds with the GOPATH overlay and runs:

| Trace | Test | Records | Purpose |
|---|---|---|---|
| `quorum_read` | `TestSpeculaTraceQuorumRead` (V0) | 28 | election, commit, safe read, Ready |
| `quorum_loss` | `TestSpeculaTraceQuorumLoss` (V0) | 15 | CheckQuorum activity reset and step-down |
| `read_reuse` | `TestSpeculaTraceReadReuse` | 33 | release deletes key; same context re-enqueued and served |
| `forwarded_read` | `TestSpeculaTraceForwardedRead` | 37 | forward, remote release/response, reuse by the follower |
| `delayed_ack` | `TestSpeculaTraceDelayedAck` | 29 | first-round response delivered after re-enqueue releases the new request |
| `step_down_reads` | `TestSpeculaTraceStepDownClearsReads` | 27 | MsgBeat with pending ctx; CheckQuorum step-down clears readOnly |
| `higher_term_reads` | `TestSpeculaTraceHigherTermClearsReads` | 28 | higher-term MsgVote clears readOnly; new leader elected |

`harness/validate.sh` replays every trace with TLC before model checking.
