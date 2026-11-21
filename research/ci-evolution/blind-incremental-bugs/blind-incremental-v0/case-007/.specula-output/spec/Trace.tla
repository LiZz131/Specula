--------------------------- MODULE Trace ---------------------------
\* Linear replay of Category A NDJSON emitted by the instrumented exact-old code.

EXTENDS base, Json, IOUtils, Sequences, TLC

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/trace.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x :
        /\ "tag" \in DOMAIN x
        /\ x.tag = "trace"
        /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0

VARIABLE l
traceVars == <<l>>
TraceVars == <<vars, l>>

logline == TraceLog[l]

TraceTarget == TLCEval({TraceLog[k].event.target : k \in 1..Len(TraceLog)})
ASSUME TraceTarget \subseteq Target

TraceInit == Init /\ l = 1

IsEvent(name) ==
    /\ l <= Len(TraceLog)
    /\ logline.event.name = name

IsTargetEvent(name, t) ==
    /\ IsEvent(name)
    /\ logline.event.target = t

StepTrace == l' = l + 1

ValidateSpawn(t) ==
    /\ active'[t] = logline.event.state.active
    /\ localCommitted'[t] = logline.event.state.local_commit
    /\ remoteMatching'[t] = logline.event.state.remote_match
    /\ coreMatching'[t] = logline.event.state.core_match

ValidatePending(t) ==
    /\ pendingKind'[t] = logline.event.state.pending_kind
    /\ pendingPrev'[t] = logline.event.state.pending_prev
    /\ pendingLast'[t] = logline.event.state.pending_last
    /\ pendingInflight'[t] = logline.event.state.pending_inflight

ValidateSend(t) ==
    /\ rpcPending'[t] = logline.event.state.rpc_pending
    /\ sentKind'[t] = logline.event.state.sent_kind
    /\ sentPrev'[t] = logline.event.state.sent_prev
    /\ sentLast'[t] = logline.event.state.sent_last
    /\ sentInflight'[t] = logline.event.state.sent_inflight
    /\ attemptCount'[t] = logline.event.state.attempt_count

ValidateResponse(t) ==
    /\ rpcPending'[t] = logline.event.state.rpc_pending
    /\ remoteMatching'[t] = logline.event.state.remote_match
    /\ lastOutcome'[t] = logline.event.state.last_outcome

ValidateCore(t) ==
    /\ coreMatching'[t] = logline.event.state.core_match
    /\ coreSearchingEnd'[t] = logline.event.state.core_searching_end
    /\ coreInflightKind'[t] = logline.event.state.core_inflight_kind
    /\ coreInflightId'[t] = logline.event.state.core_inflight_id
    /\ coreInflightPrev'[t] = logline.event.state.core_inflight_prev
    /\ coreInflightLast'[t] = logline.event.state.core_inflight_last

TaskSpawnIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("TaskSpawn", t)
        /\ SpawnReplication(t,
             logline.event.session,
             logline.event.state.local_commit,
             logline.event.state.remote_match)
        /\ ValidateSpawn(t)
        /\ StepTrace

ReceiveLogsIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("ReceiveLogs", t)
        /\ ReceiveLogs(t,
             logline.event.msg.prev,
             logline.event.msg.last,
             logline.event.msg.inflight)
        /\ ValidatePending(t)
        /\ StepTrace

ReceiveCommittedIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("ReceiveCommitted", t)
        /\ ReceiveCommitted(t, logline.event.msg.committed)
        /\ localCommitted'[t] = logline.event.state.local_commit
        /\ ValidatePending(t)
        /\ StepTrace

SendAppendIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("SendAppend", t)
        /\ SendAppend(t, logline.event.msg.last)
        /\ ValidateSend(t)
        /\ StepTrace

AppendSuccessIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("AppendSuccess", t)
        /\ AppendSuccess(t)
        /\ ValidateResponse(t)
        /\ ValidatePending(t)
        /\ StepTrace

AppendPartialIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("AppendPartial", t)
        /\ AppendPartial(t, logline.event.msg.matching)
        /\ ValidateResponse(t)
        /\ ValidatePending(t)
        /\ partialCount'[t] = logline.event.state.partial_count
        /\ StepTrace

AppendConflictIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("AppendConflict", t)
        /\ AppendConflict(t)
        /\ rpcPending'[t] = logline.event.state.rpc_pending
        /\ lastOutcome'[t] = logline.event.state.last_outcome
        /\ StepTrace

AppendHigherVoteIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("AppendHigherVote", t)
        /\ AppendHigherVote(t)
        /\ active'[t] = logline.event.state.active
        /\ rpcPending'[t] = logline.event.state.rpc_pending
        /\ lastOutcome'[t] = logline.event.state.last_outcome
        /\ StepTrace

AppendRpcErrorIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("AppendRpcError", t)
        /\ AppendRpcError(t, logline.event.msg.error_kind)
        /\ rpcPending'[t] = logline.event.state.rpc_pending
        /\ backoffActive'[t] = logline.event.state.backoff_active
        /\ lastOutcome'[t] = logline.event.state.last_outcome
        /\ StepTrace

BackoffResetIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("BackoffReset", t)
        /\ ResetBackoffAfterReply(t)
        /\ backoffActive'[t] = logline.event.state.backoff_active
        /\ StepTrace

BackoffBeginIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("BackoffBegin", t)
        /\ BeginBackoff(t)
        /\ waiting'[t] = logline.event.state.waiting
        /\ waitCount'[t] = logline.event.state.wait_count
        /\ StepTrace

BackoffEndIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("BackoffEnd", t)
        /\ EndBackoff(t)
        /\ waiting'[t] = logline.event.state.waiting
        /\ StepTrace

CoreProgressIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("CoreProgress", t)
        /\ Len(notifications) > 0
        /\ Head(notifications).session = logline.event.session
        /\ Head(notifications).inflight = logline.event.msg.inflight
        /\ Head(notifications).outcome = logline.event.msg.outcome
        /\ Head(notifications).value = logline.event.msg.value
        /\ CoreHandleProgress
        /\ ValidateCore(t)
        /\ StepTrace

SnapshotStartIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("SnapshotStart", t)
        /\ StartSnapshot(t, logline.event.msg.inflight)
        /\ snapshotActive'[t] = logline.event.state.snapshot_active
        /\ coreInflightKind'[t] = logline.event.state.core_inflight_kind
        /\ coreInflightId'[t] = logline.event.state.core_inflight_id
        /\ StepTrace

SnapshotAttemptIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("SnapshotAttempt", t)
        /\ BeginSnapshotAttempt(t)
        /\ snapshotAttemptCount'[t] = logline.event.state.snapshot_attempt_count
        /\ StepTrace

SnapshotRpcErrorIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("SnapshotRpcError", t)
        /\ SnapshotRpcError(t, logline.event.msg.error_kind)
        /\ snapshotBackoff'[t] = logline.event.state.snapshot_backoff
        /\ StepTrace

SnapshotBackoffIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("SnapshotBackoff", t)
        /\ BeginSnapshotBackoff(t)
        /\ snapshotWaitCount'[t] = logline.event.state.snapshot_wait_count
        /\ StepTrace

SnapshotSuccessIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("SnapshotSuccess", t)
        /\ SnapshotSuccess(t, logline.event.msg.matching)
        /\ snapshotActive'[t] = logline.event.state.snapshot_active
        /\ snapshotBackoff'[t] = logline.event.state.snapshot_backoff
        /\ StepTrace

TaskCloseIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("TaskClose", t)
        /\ CloseTask(t)
        /\ active'[t] = logline.event.state.active
        /\ StepTrace

StreamEnqueueIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("StreamEnqueue", t)
        /\ StreamEnqueue(t, logline.event.msg.prev, logline.event.msg.last)
        /\ StepTrace

StreamResultIfLogged ==
    \E t \in Target :
        /\ IsTargetEvent("StreamResult", t)
        /\ StreamResult(t, logline.event.msg.outcome, logline.event.msg.value)
        /\ streamStopped'[t] = logline.event.state.stream_stopped
        /\ lastStreamOutcome'[t] = logline.event.state.last_stream_outcome
        /\ StepTrace

LoggedTraceNext ==
    \/ TaskSpawnIfLogged
    \/ ReceiveLogsIfLogged
    \/ ReceiveCommittedIfLogged
    \/ SendAppendIfLogged
    \/ AppendSuccessIfLogged
    \/ AppendPartialIfLogged
    \/ AppendConflictIfLogged
    \/ AppendHigherVoteIfLogged
    \/ AppendRpcErrorIfLogged
    \/ BackoffResetIfLogged
    \/ BackoffBeginIfLogged
    \/ BackoffEndIfLogged
    \/ CoreProgressIfLogged
    \/ SnapshotStartIfLogged
    \/ SnapshotAttemptIfLogged
    \/ SnapshotRpcErrorIfLogged
    \/ SnapshotBackoffIfLogged
    \/ SnapshotSuccessIfLogged
    \/ TaskCloseIfLogged
    \/ StreamEnqueueIfLogged
    \/ StreamResultIfLogged
    \/ /\ l > Len(TraceLog)
       /\ UNCHANGED TraceVars

\* Channel send happens before each response hook. Eagerly linearizing the
\* unlogged single-threaded core step avoids inventing scheduler branches while
\* retaining the exact CoreHandleProgress transition.
TraceNext ==
    IF Len(notifications) > 0
    THEN /\ CoreHandleProgress
         /\ UNCHANGED l
    ELSE LoggedTraceNext

TraceProgress == TraceNext /\ l' = l + 1
TraceInternal == CoreHandleProgress /\ UNCHANGED l
TraceSpec == TraceInit
    /\ [][TraceNext]_TraceVars
    /\ WF_TraceVars(TraceProgress)
    /\ WF_TraceVars(TraceInternal)
TraceMatched == <>(l > Len(TraceLog))
TraceView == <<vars, l>>

=============================================================================
