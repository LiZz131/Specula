---------------------------- MODULE base ----------------------------
\* Exact-old Openraft per-target replication boundary.
\* Log positions are abstracted to integer indexes; -1 represents no log ID.
\* Qualitative protocol state is separate from the attempt/wait counters.

EXTENDS Naturals, Integers, Sequences, TLC

CONSTANT Target, MaxIndex, MaxInflight, MaxAttempts, AllowLogReversion

NoIndex == -1
NoInflight == -1

TaskKinds == {"none", "committed", "logs"}
CoreInflightKinds == {"none", "logs", "snapshot"}
Outcomes == {"none", "success", "partial", "conflict", "higher",
             "timeout", "unreachable", "network", "remote"}
ProgressOutcomes == {"match", "conflict", "error"}
StreamOutcomes == {"none", "success", "partial", "conflict", "higher"}

VARIABLES
    active, taskSession, coreSession,
    localCommitted, remoteMatching,
    pendingKind, pendingPrev, pendingLast, pendingInflight,
    rpcPending, sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
    backoffActive, waiting, lastOutcome,
    coreMatching, coreSearchingEnd,
    coreInflightKind, coreInflightId, coreInflightPrev, coreInflightLast,
    notifications,
    snapshotActive, snapshotBackoff,
    streamQueue, streamStopped, lastStreamOutcome,
    attemptCount, waitCount, partialCount, snapshotAttemptCount, snapshotWaitCount

taskVars == <<active, taskSession, localCommitted, remoteMatching,
              pendingKind, pendingPrev, pendingLast, pendingInflight,
              rpcPending, sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
              backoffActive, waiting, lastOutcome>>
coreVars == <<coreSession, coreMatching, coreSearchingEnd,
              coreInflightKind, coreInflightId, coreInflightPrev, coreInflightLast,
              notifications>>
snapshotVars == <<snapshotActive, snapshotBackoff>>
streamVars == <<streamQueue, streamStopped, lastStreamOutcome>>
costVars == <<attemptCount, waitCount, partialCount,
              snapshotAttemptCount, snapshotWaitCount>>
vars == <<taskVars, coreVars, snapshotVars, streamVars, costVars>>

Max(a, b) == IF a >= b THEN a ELSE b
Min(a, b) == IF a <= b THEN a ELSE b

EmptyProgressNotification(t) ==
    [target |-> t,
     session |-> "",
     inflight |-> NoInflight,
     outcome |-> "error",
     value |-> NoIndex]

Init ==
    /\ active = [t \in Target |-> FALSE]
    /\ taskSession = [t \in Target |-> ""]
    /\ coreSession = ""
    /\ localCommitted = [t \in Target |-> NoIndex]
    /\ remoteMatching = [t \in Target |-> NoIndex]
    /\ pendingKind = [t \in Target |-> "none"]
    /\ pendingPrev = [t \in Target |-> NoIndex]
    /\ pendingLast = [t \in Target |-> NoIndex]
    /\ pendingInflight = [t \in Target |-> NoInflight]
    /\ rpcPending = [t \in Target |-> FALSE]
    /\ sentKind = [t \in Target |-> "none"]
    /\ sentPrev = [t \in Target |-> NoIndex]
    /\ sentLast = [t \in Target |-> NoIndex]
    /\ sentRequestLast = [t \in Target |-> NoIndex]
    /\ sentInflight = [t \in Target |-> NoInflight]
    /\ backoffActive = [t \in Target |-> FALSE]
    /\ waiting = [t \in Target |-> FALSE]
    /\ lastOutcome = [t \in Target |-> "none"]
    /\ coreMatching = [t \in Target |-> NoIndex]
    /\ coreSearchingEnd = [t \in Target |-> 0]
    /\ coreInflightKind = [t \in Target |-> "none"]
    /\ coreInflightId = [t \in Target |-> NoInflight]
    /\ coreInflightPrev = [t \in Target |-> NoIndex]
    /\ coreInflightLast = [t \in Target |-> NoIndex]
    /\ notifications = <<>>
    /\ snapshotActive = [t \in Target |-> FALSE]
    /\ snapshotBackoff = [t \in Target |-> FALSE]
    /\ streamQueue = [t \in Target |-> <<>>]
    /\ streamStopped = [t \in Target |-> FALSE]
    /\ lastStreamOutcome = [t \in Target |-> "none"]
    /\ attemptCount = [t \in Target |-> 0]
    /\ waitCount = [t \in Target |-> 0]
    /\ partialCount = [t \in Target |-> 0]
    /\ snapshotAttemptCount = [t \in Target |-> 0]
    /\ snapshotWaitCount = [t \in Target |-> 0]

\* Start one per-target worker from authoritative committed/matching state.
\* openraft/src/core/raft_core.rs:852-880
\* openraft/src/replication/mod.rs:123-180
SpawnReplication(t, s, committed0, matching0) ==
    /\ ~active[t]
    /\ committed0 \in NoIndex..MaxIndex
    /\ matching0 \in NoIndex..MaxIndex
    /\ active' = [active EXCEPT ![t] = TRUE]
    /\ taskSession' = [taskSession EXCEPT ![t] = s]
    /\ coreSession' = s
    /\ localCommitted' = [localCommitted EXCEPT ![t] = committed0]
    /\ remoteMatching' = [remoteMatching EXCEPT ![t] = matching0]
    /\ coreMatching' = [coreMatching EXCEPT ![t] = matching0]
    /\ coreSearchingEnd' = [coreSearchingEnd EXCEPT ![t] = matching0 + 1]
    /\ coreInflightKind' = [coreInflightKind EXCEPT ![t] = "none"]
    /\ coreInflightId' = [coreInflightId EXCEPT ![t] = NoInflight]
    /\ coreInflightPrev' = [coreInflightPrev EXCEPT ![t] = NoIndex]
    /\ coreInflightLast' = [coreInflightLast EXCEPT ![t] = NoIndex]
    /\ pendingKind' = [pendingKind EXCEPT ![t] = "none"]
    /\ pendingPrev' = [pendingPrev EXCEPT ![t] = NoIndex]
    /\ pendingLast' = [pendingLast EXCEPT ![t] = NoIndex]
    /\ pendingInflight' = [pendingInflight EXCEPT ![t] = NoInflight]
    /\ rpcPending' = [rpcPending EXCEPT ![t] = FALSE]
    /\ sentKind' = [sentKind EXCEPT ![t] = "none"]
    /\ sentPrev' = [sentPrev EXCEPT ![t] = NoIndex]
    /\ sentLast' = [sentLast EXCEPT ![t] = NoIndex]
    /\ sentRequestLast' = [sentRequestLast EXCEPT ![t] = NoIndex]
    /\ sentInflight' = [sentInflight EXCEPT ![t] = NoInflight]
    /\ backoffActive' = [backoffActive EXCEPT ![t] = FALSE]
    /\ waiting' = [waiting EXCEPT ![t] = FALSE]
    /\ lastOutcome' = [lastOutcome EXCEPT ![t] = "none"]
    /\ attemptCount' = [attemptCount EXCEPT ![t] = 0]
    /\ waitCount' = [waitCount EXCEPT ![t] = 0]
    /\ partialCount' = [partialCount EXCEPT ![t] = 0]
    /\ UNCHANGED <<notifications, snapshotVars, streamVars,
                    snapshotAttemptCount, snapshotWaitCount>>

\* RaftCore has reserved a log range and the worker processes Replicate::Data.
\* openraft/src/progress/entry/mod.rs:112-164
\* openraft/src/engine/handler/replication_handler/mod.rs:315-355
\* openraft/src/replication/mod.rs:594-625
ReceiveLogs(t, prev, last, iid) ==
    /\ active[t]
    /\ ~rpcPending[t]
    /\ (~backoffActive[t] \/ waiting[t])
    /\ taskSession[t] = coreSession
    /\ coreInflightKind[t] = "none"
    /\ NoIndex <= prev
    /\ remoteMatching[t] <= prev
    /\ coreMatching[t] <= prev
    /\ prev < last
    /\ last <= MaxIndex
    /\ iid \in 0..MaxInflight
    /\ pendingKind[t] /= "logs"
    /\ coreInflightKind' = [coreInflightKind EXCEPT ![t] = "logs"]
    /\ coreInflightId' = [coreInflightId EXCEPT ![t] = iid]
    /\ coreInflightPrev' = [coreInflightPrev EXCEPT ![t] = prev]
    /\ coreInflightLast' = [coreInflightLast EXCEPT ![t] = last]
    /\ pendingKind' = [pendingKind EXCEPT ![t] = "logs"]
    /\ pendingPrev' = [pendingPrev EXCEPT ![t] = prev]
    /\ pendingLast' = [pendingLast EXCEPT ![t] = last]
    /\ pendingInflight' = [pendingInflight EXCEPT ![t] = iid]
    /\ UNCHANGED <<active, taskSession, coreSession, localCommitted,
                    remoteMatching, rpcPending, sentKind, sentPrev, sentLast,
                    sentRequestLast,
                    sentInflight, backoffActive, waiting, lastOutcome,
                    coreMatching, coreSearchingEnd, notifications,
                    snapshotVars, streamVars, costVars>>

\* A committed update is monotone and only fills an empty worker action slot.
\* openraft/src/core/raft_core.rs:1929-1934
\* openraft/src/replication/mod.rs:598-613
ReceiveCommitted(t, committed0) ==
    /\ active[t]
    /\ ~rpcPending[t]
    /\ (~backoffActive[t] \/ waiting[t])
    /\ committed0 \in localCommitted[t]..MaxIndex
    /\ localCommitted' = [localCommitted EXCEPT ![t] = committed0]
    /\ IF pendingKind[t] = "none"
       THEN /\ pendingKind' = [pendingKind EXCEPT ![t] = "committed"]
            /\ pendingPrev' = [pendingPrev EXCEPT ![t] = remoteMatching[t]]
            /\ pendingLast' = [pendingLast EXCEPT ![t] = remoteMatching[t]]
            /\ pendingInflight' = [pendingInflight EXCEPT ![t] = NoInflight]
       ELSE UNCHANGED <<pendingKind, pendingPrev, pendingLast, pendingInflight>>
    /\ UNCHANGED <<active, taskSession, coreVars, remoteMatching,
                    rpcPending, sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
                    backoffActive, waiting, lastOutcome,
                    snapshotVars, streamVars, costVars>>

\* Taking next_action, reading a (possibly shorter) prefix, building the request,
\* and starting the awaited unary RPC.  No worker event is processed meanwhile.
\* openraft/src/replication/mod.rs:184-214,304-379
SendAppend(t, actualLast) ==
    /\ active[t]
    /\ ~rpcPending[t]
    /\ ~waiting[t]
    /\ pendingKind[t] \in {"committed", "logs"}
    /\ attemptCount[t] < MaxAttempts
    /\ IF pendingKind[t] = "committed"
       THEN actualLast = pendingPrev[t]
       ELSE actualLast \in (pendingPrev[t] + 1)..pendingLast[t]
    /\ rpcPending' = [rpcPending EXCEPT ![t] = TRUE]
    /\ sentKind' = [sentKind EXCEPT ![t] = pendingKind[t]]
    /\ sentPrev' = [sentPrev EXCEPT ![t] = pendingPrev[t]]
    /\ sentLast' = [sentLast EXCEPT ![t] = actualLast]
    /\ sentRequestLast' = [sentRequestLast EXCEPT ![t] = pendingLast[t]]
    /\ sentInflight' = [sentInflight EXCEPT ![t] = pendingInflight[t]]
    /\ pendingKind' = [pendingKind EXCEPT ![t] = "none"]
    /\ pendingPrev' = [pendingPrev EXCEPT ![t] = NoIndex]
    /\ pendingLast' = [pendingLast EXCEPT ![t] = NoIndex]
    /\ pendingInflight' = [pendingInflight EXCEPT ![t] = NoInflight]
    /\ attemptCount' = [attemptCount EXCEPT ![t] = @ + 1]
    /\ UNCHANGED <<active, taskSession, coreVars, localCommitted,
                    remoteMatching, backoffActive, waiting, lastOutcome,
                    snapshotVars, streamVars, waitCount, partialCount,
                    snapshotAttemptCount, snapshotWaitCount>>

ProgressNote(t, outcome0, value0) ==
    [target |-> t,
     session |-> taskSession[t],
     inflight |-> sentInflight[t],
     outcome |-> outcome0,
     value |-> value0]

\* Full reply: worker matching reaches the actual physical endpoint.
\* Heartbeat and progress sends are separate in code; this action records the
\* progress send and heartbeat acknowledgement is outside the scoped state.
\* openraft/src/replication/mod.rs:387-399,466-513
AppendSuccess(t) ==
    /\ rpcPending[t]
    /\ rpcPending' = [rpcPending EXCEPT ![t] = FALSE]
    /\ remoteMatching' = [remoteMatching EXCEPT ![t] = sentLast[t]]
    /\ lastOutcome' = [lastOutcome EXCEPT ![t] = "success"]
    /\ IF sentKind[t] = "logs"
       THEN /\ notifications' = Append(notifications, ProgressNote(t, "match", sentLast[t]))
            /\ IF sentLast[t] < sentRequestLast[t]
               THEN /\ pendingKind' = [pendingKind EXCEPT ![t] = "logs"]
                    /\ pendingPrev' = [pendingPrev EXCEPT ![t] = sentLast[t]]
                    /\ pendingLast' = [pendingLast EXCEPT ![t] = sentRequestLast[t]]
                    /\ pendingInflight' = [pendingInflight EXCEPT ![t] = sentInflight[t]]
               ELSE UNCHANGED <<pendingKind, pendingPrev, pendingLast, pendingInflight>>
       ELSE /\ UNCHANGED notifications
            /\ UNCHANGED <<pendingKind, pendingPrev, pendingLast, pendingInflight>>
    /\ UNCHANGED <<active, taskSession, coreSession, localCommitted,
                    sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
                    backoffActive, waiting, coreMatching, coreSearchingEnd,
                    coreInflightKind, coreInflightId, coreInflightPrev, coreInflightLast,
                    snapshotVars, streamVars, costVars>>

\* Partial reply may make zero progress; remainder retains the same inflight ID.
\* openraft/src/raft/message/append_entries_response.rs:24-41
\* openraft/src/replication/mod.rs:400-410,629-668
AppendPartial(t, matching0) ==
    /\ rpcPending[t]
    /\ sentKind[t] = "logs"
    /\ matching0 \in sentPrev[t]..sentLast[t]
    /\ partialCount[t] < MaxAttempts
    /\ rpcPending' = [rpcPending EXCEPT ![t] = FALSE]
    /\ remoteMatching' = [remoteMatching EXCEPT ![t] = matching0]
    /\ lastOutcome' = [lastOutcome EXCEPT ![t] = "partial"]
    /\ notifications' = Append(notifications, ProgressNote(t, "match", matching0))
    /\ IF matching0 < sentRequestLast[t]
       THEN /\ pendingKind' = [pendingKind EXCEPT ![t] = "logs"]
            /\ pendingPrev' = [pendingPrev EXCEPT ![t] = matching0]
            /\ pendingLast' = [pendingLast EXCEPT ![t] = sentRequestLast[t]]
            /\ pendingInflight' = [pendingInflight EXCEPT ![t] = sentInflight[t]]
       ELSE /\ pendingKind' = [pendingKind EXCEPT ![t] = "none"]
            /\ pendingPrev' = [pendingPrev EXCEPT ![t] = NoIndex]
            /\ pendingLast' = [pendingLast EXCEPT ![t] = NoIndex]
            /\ pendingInflight' = [pendingInflight EXCEPT ![t] = NoInflight]
    /\ partialCount' = [partialCount EXCEPT ![t] = @ + 1]
    /\ UNCHANGED <<active, taskSession, coreSession, localCommitted,
                    sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
                    backoffActive, waiting, coreMatching, coreSearchingEnd,
                    coreInflightKind, coreInflightId, coreInflightPrev, coreInflightLast,
                    snapshotVars, streamVars, attemptCount, waitCount,
                    snapshotAttemptCount, snapshotWaitCount>>

\* Conflict is a protocol reply and always reports sent prev, even for a
\* commit-only RPC. It does not change worker matching.
\* openraft/src/replication/mod.rs:426-439
AppendConflict(t) ==
    /\ rpcPending[t]
    /\ sentPrev[t] >= 0
    /\ rpcPending' = [rpcPending EXCEPT ![t] = FALSE]
    /\ lastOutcome' = [lastOutcome EXCEPT ![t] = "conflict"]
    /\ notifications' = Append(notifications, ProgressNote(t, "conflict", sentPrev[t]))
    /\ UNCHANGED <<active, taskSession, coreSession, localCommitted,
                    remoteMatching, pendingKind, pendingPrev, pendingLast,
                    pendingInflight, sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
                    backoffActive, waiting, coreMatching, coreSearchingEnd,
                    coreInflightKind, coreInflightId, coreInflightPrev, coreInflightLast,
                    snapshotVars, streamVars, costVars>>

\* Higher vote terminates this log-replication task after notifying RaftCore.
\* openraft/src/replication/mod.rs:226-246,412-425
AppendHigherVote(t) ==
    /\ rpcPending[t]
    /\ active' = [active EXCEPT ![t] = FALSE]
    /\ rpcPending' = [rpcPending EXCEPT ![t] = FALSE]
    /\ lastOutcome' = [lastOutcome EXCEPT ![t] = "higher"]
    /\ UNCHANGED <<taskSession, coreVars, localCommitted, remoteMatching,
                    pendingKind, pendingPrev, pendingLast, pendingInflight,
                    sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
                    backoffActive, waiting, snapshotVars, streamVars, costVars>>

\* Transport result: only Unreachable initializes log-task backoff. A payload
\* error creates progress; commit-only errors are silent to core.
\* openraft/src/replication/mod.rs:248-270,444-459
AppendRpcError(t, errorKind) ==
    /\ rpcPending[t]
    /\ errorKind \in {"timeout", "unreachable", "network", "remote"}
    /\ rpcPending' = [rpcPending EXCEPT ![t] = FALSE]
    /\ lastOutcome' = [lastOutcome EXCEPT ![t] = errorKind]
    /\ backoffActive' = [backoffActive EXCEPT ![t] =
                            backoffActive[t] \/ errorKind = "unreachable"]
    /\ IF sentKind[t] = "logs"
       THEN notifications' = Append(notifications, ProgressNote(t, "error", NoIndex))
       ELSE UNCHANGED notifications
    /\ UNCHANGED <<active, taskSession, coreSession, localCommitted,
                    remoteMatching, pendingKind, pendingPrev, pendingLast,
                    pendingInflight, sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
                    waiting, coreMatching, coreSearchingEnd,
                    coreInflightKind, coreInflightId, coreInflightPrev, coreInflightLast,
                    snapshotVars, streamVars, costVars>>

\* Main clears old log backoff only after a handled protocol reply.
\* openraft/src/replication/mod.rs:218-222
ResetBackoffAfterReply(t) ==
    /\ backoffActive[t]
    /\ lastOutcome[t] \in {"success", "partial", "conflict"}
    /\ backoffActive' = [backoffActive EXCEPT ![t] = FALSE]
    /\ UNCHANGED <<active, taskSession, coreVars, localCommitted,
                    remoteMatching, pendingKind, pendingPrev, pendingLast,
                    pendingInflight, rpcPending, sentKind, sentPrev, sentLast, sentRequestLast,
                    sentInflight, waiting, lastOutcome,
                    snapshotVars, streamVars, costVars>>

\* One iterator item is consumed; event receipt remains enabled while waiting.
\* openraft/src/replication/mod.rs:280-290,516-549
BeginBackoff(t) ==
    /\ active[t]
    /\ backoffActive[t]
    /\ ~waiting[t]
    /\ ~rpcPending[t]
    /\ lastOutcome[t] \in {"timeout", "unreachable", "network", "remote"}
    /\ waitCount[t] < MaxAttempts
    /\ waitCount[t] < attemptCount[t]
    /\ waiting' = [waiting EXCEPT ![t] = TRUE]
    /\ waitCount' = [waitCount EXCEPT ![t] = @ + 1]
    /\ UNCHANGED <<active, taskSession, coreVars, localCommitted,
                    remoteMatching, pendingKind, pendingPrev, pendingLast,
                    pendingInflight, rpcPending, sentKind, sentPrev, sentLast, sentRequestLast,
                    sentInflight, backoffActive, lastOutcome,
                    snapshotVars, streamVars, attemptCount, partialCount,
                    snapshotAttemptCount, snapshotWaitCount>>

\* Timer expiry permits the already-folded next action to run.
\* openraft/src/replication/mod.rs:530-547
EndBackoff(t) ==
    /\ waiting[t]
    /\ waiting' = [waiting EXCEPT ![t] = FALSE]
    /\ UNCHANGED <<active, taskSession, coreVars, localCommitted,
                    remoteMatching, pendingKind, pendingPrev, pendingLast,
                    pendingInflight, rpcPending, sentKind, sentPrev, sentLast, sentRequestLast,
                    sentInflight, backoffActive, lastOutcome,
                    snapshotVars, streamVars, costVars>>

\* The single-threaded core checks session and applies one queued progress item.
\* Session mismatch consumes the stale item without progress mutation.
\* For current-session messages, inflight ID guards only nested inflight changes;
\* outer matching/search changes follow exact-old Updater control flow.
\* openraft/src/core/raft_core.rs:1565-1592,1746-1767
\* openraft/src/progress/entry/update.rs:40-115
CoreHandleProgress ==
    /\ Len(notifications) > 0
    /\ LET n == Head(notifications)
       IN /\ notifications' = Tail(notifications)
          /\ IF n.session /= coreSession
             THEN UNCHANGED <<coreMatching, coreSearchingEnd,
                              coreInflightKind, coreInflightId,
                              coreInflightPrev, coreInflightLast>>
             ELSE CASE n.outcome = "error" ->
                         /\ coreInflightKind' = [coreInflightKind EXCEPT ![n.target] = "none"]
                         /\ coreInflightId' = [coreInflightId EXCEPT ![n.target] = NoInflight]
                         /\ coreInflightPrev' = [coreInflightPrev EXCEPT ![n.target] = NoIndex]
                         /\ coreInflightLast' = [coreInflightLast EXCEPT ![n.target] = NoIndex]
                         /\ UNCHANGED <<coreMatching, coreSearchingEnd>>
                    [] n.outcome = "match" ->
                         /\ coreMatching' = [coreMatching EXCEPT ![n.target] = n.value]
                         /\ coreSearchingEnd' = [coreSearchingEnd EXCEPT
                                                  ![n.target] = Max(@, n.value + 1)]
                         /\ IF coreInflightKind[n.target] \in {"logs", "snapshot"}
                                /\ coreInflightId[n.target] = n.inflight
                            THEN /\ coreInflightKind' = [coreInflightKind EXCEPT
                                     ![n.target] = IF coreInflightKind[n.target] = "logs"
                                                      /\ n.value < coreInflightLast[n.target]
                                                   THEN "logs" ELSE "none"]
                                 /\ coreInflightId' = [coreInflightId EXCEPT
                                     ![n.target] = IF coreInflightKind[n.target] = "logs"
                                                      /\ n.value < coreInflightLast[n.target]
                                                   THEN @ ELSE NoInflight]
                                 /\ coreInflightPrev' = [coreInflightPrev EXCEPT
                                     ![n.target] = IF coreInflightKind[n.target] = "logs"
                                                      /\ n.value < coreInflightLast[n.target]
                                                   THEN n.value ELSE NoIndex]
                                 /\ coreInflightLast' = [coreInflightLast EXCEPT
                                     ![n.target] = IF coreInflightKind[n.target] = "logs"
                                                      /\ n.value < coreInflightLast[n.target]
                                                   THEN @ ELSE NoIndex]
                            ELSE UNCHANGED <<coreInflightKind, coreInflightId,
                                             coreInflightPrev, coreInflightLast>>
                    [] n.outcome = "conflict" ->
                         /\ n.value >= coreMatching[n.target] + 1 \/ AllowLogReversion
                         /\ coreSearchingEnd' = [coreSearchingEnd EXCEPT
                                                  ![n.target] = Min(@, n.value)]
                         /\ IF coreInflightKind[n.target] = "logs"
                                /\ coreInflightId[n.target] = n.inflight
                            THEN /\ coreInflightKind' = [coreInflightKind EXCEPT ![n.target] = "none"]
                                 /\ coreInflightId' = [coreInflightId EXCEPT ![n.target] = NoInflight]
                                 /\ coreInflightPrev' = [coreInflightPrev EXCEPT ![n.target] = NoIndex]
                                 /\ coreInflightLast' = [coreInflightLast EXCEPT ![n.target] = NoIndex]
                            ELSE UNCHANGED <<coreInflightKind, coreInflightId,
                                             coreInflightPrev, coreInflightLast>>
                         /\ IF n.value < coreMatching[n.target] + 1
                            THEN coreMatching' = [coreMatching EXCEPT ![n.target] = NoIndex]
                            ELSE UNCHANGED coreMatching
    /\ UNCHANGED <<taskVars, coreSession, snapshotVars, streamVars, costVars>>

\* Vote or effective membership rollover changes the strong session boundary.
\* Existing task notifications may still be queued and will be dropped by core.
\* openraft/src/core/raft_core.rs:883-905,1746-1767,1977-1983
ChangeCoreSession(s) ==
    /\ s /= coreSession
    /\ coreSession' = s
    /\ coreInflightKind' = [t \in Target |-> "none"]
    /\ coreInflightId' = [t \in Target |-> NoInflight]
    /\ coreInflightPrev' = [t \in Target |-> NoIndex]
    /\ coreInflightLast' = [t \in Target |-> NoIndex]
    /\ UNCHANGED <<taskVars, coreMatching, coreSearchingEnd, notifications,
                    snapshotVars, streamVars, costVars>>

\* Snapshot selection reserves authoritative snapshot inflight and spawns a
\* separate task; the log worker itself remains alive.
\* openraft/src/progress/entry/mod.rs:129-142
\* openraft/src/core/raft_core.rs:1954-1973
StartSnapshot(t, iid) ==
    /\ active[t]
    /\ taskSession[t] = coreSession
    /\ coreInflightKind[t] = "none"
    /\ ~snapshotActive[t]
    /\ iid \in 0..MaxInflight
    /\ coreInflightKind' = [coreInflightKind EXCEPT ![t] = "snapshot"]
    /\ coreInflightId' = [coreInflightId EXCEPT ![t] = iid]
    /\ coreInflightPrev' = [coreInflightPrev EXCEPT ![t] = NoIndex]
    /\ coreInflightLast' = [coreInflightLast EXCEPT ![t] = NoIndex]
    /\ snapshotActive' = [snapshotActive EXCEPT ![t] = TRUE]
    /\ snapshotBackoff' = [snapshotBackoff EXCEPT ![t] = FALSE]
    /\ UNCHANGED <<taskVars, coreSession, coreMatching, coreSearchingEnd,
                    notifications, streamVars, costVars>>

\* Each snapshot attempt re-reads and calls full_snapshot.
\* openraft/src/replication/snapshot_transmitter.rs:91-106,173-212
BeginSnapshotAttempt(t) ==
    /\ snapshotActive[t]
    /\ snapshotAttemptCount[t] < MaxAttempts
    /\ snapshotAttemptCount' = [snapshotAttemptCount EXCEPT ![t] = @ + 1]
    /\ UNCHANGED <<taskVars, coreVars, snapshotVars, streamVars,
                    attemptCount, waitCount, partialCount, snapshotWaitCount>>

\* Snapshot transient error policy differs from log policy.
\* openraft/src/replication/snapshot_transmitter.rs:134-169
SnapshotRpcError(t, errorKind) ==
    /\ snapshotActive[t]
    /\ errorKind \in {"timeout", "unreachable", "network", "remote"}
    /\ snapshotBackoff' = [snapshotBackoff EXCEPT ![t] = errorKind = "unreachable"]
    /\ UNCHANGED <<taskVars, coreVars, snapshotActive, streamVars, costVars>>

BeginSnapshotBackoff(t) ==
    /\ snapshotActive[t]
    /\ snapshotBackoff[t]
    /\ snapshotWaitCount[t] < MaxAttempts
    /\ snapshotWaitCount' = [snapshotWaitCount EXCEPT ![t] = @ + 1]
    /\ UNCHANGED <<taskVars, coreVars, snapshotVars, streamVars,
                    attemptCount, waitCount, partialCount, snapshotAttemptCount>>

\* A completed installation emits current-session matching progress and exits.
\* openraft/src/replication/snapshot_transmitter.rs:199-265
SnapshotSuccess(t, matching0) ==
    /\ snapshotActive[t]
    /\ matching0 \in NoIndex..MaxIndex
    /\ snapshotActive' = [snapshotActive EXCEPT ![t] = FALSE]
    /\ snapshotBackoff' = [snapshotBackoff EXCEPT ![t] = FALSE]
    /\ notifications' = Append(notifications,
         [target |-> t, session |-> taskSession[t],
          inflight |-> coreInflightId[t], outcome |-> "match", value |-> matching0])
    /\ UNCHANGED <<taskVars, coreSession, coreMatching, coreSearchingEnd,
                    coreInflightKind, coreInflightId, coreInflightPrev,
                    coreInflightLast, streamVars, costVars>>

\* Channel closure is observed by the log task's drain paths.
\* openraft/src/replication/mod.rs:538-547,560-588
CloseTask(t) ==
    /\ active[t]
    /\ ~rpcPending[t]
    /\ active' = [active EXCEPT ![t] = FALSE]
    /\ waiting' = [waiting EXCEPT ![t] = FALSE]
    /\ UNCHANGED <<taskSession, coreVars, localCommitted, remoteMatching,
                    pendingKind, pendingPrev, pendingLast, pendingInflight,
                    rpcPending, sentKind, sentPrev, sentLast, sentRequestLast, sentInflight,
                    backoffActive, lastOutcome, snapshotVars, streamVars, costVars>>

\* The inbound producer may enqueue ahead of output consumption.
\* openraft/src/raft/stream_append.rs:26-71
StreamEnqueue(t, prev, last) ==
    /\ prev \in NoIndex..MaxIndex
    /\ last \in prev..MaxIndex
    /\ streamQueue' = [streamQueue EXCEPT
         ![t] = Append(@, [prev |-> prev, last |-> last])]
    /\ UNCHANGED <<taskVars, coreVars, snapshotVars,
                    streamStopped, lastStreamOutcome, costVars>>

\* Output receives queued replies in order and terminates on protocol error.
\* openraft/src/raft/stream_append.rs:74-86
\* openraft/src/raft/message/append_entries_response.rs:68-84
StreamResult(t, outcome0, value0) ==
    /\ ~streamStopped[t]
    /\ Len(streamQueue[t]) > 0
    /\ outcome0 \in {"success", "partial", "conflict", "higher"}
    /\ LET r == Head(streamQueue[t])
       IN /\ CASE outcome0 = "success" -> value0 = r.last
                   [] outcome0 = "partial" -> value0 \in r.prev..r.last
                   [] outcome0 = "conflict" -> value0 = r.prev
                   [] outcome0 = "higher" -> value0 = NoIndex
          /\ streamQueue' = [streamQueue EXCEPT ![t] = Tail(@)]
    /\ streamStopped' = [streamStopped EXCEPT
                           ![t] = outcome0 \in {"conflict", "higher"}]
    /\ lastStreamOutcome' = [lastStreamOutcome EXCEPT ![t] = outcome0]
    /\ UNCHANGED <<taskVars, coreVars, snapshotVars, costVars>>

Next ==
    \/ \E t \in Target, s \in STRING,
          c \in NoIndex..MaxIndex, m \in NoIndex..MaxIndex :
          SpawnReplication(t, s, c, m)
    \/ \E t \in Target, p \in NoIndex..MaxIndex,
          l \in 0..MaxIndex, i \in 0..MaxInflight : ReceiveLogs(t, p, l, i)
    \/ \E t \in Target, c \in NoIndex..MaxIndex : ReceiveCommitted(t, c)
    \/ \E t \in Target, l \in NoIndex..MaxIndex : SendAppend(t, l)
    \/ \E t \in Target : AppendSuccess(t)
    \/ \E t \in Target, m \in NoIndex..MaxIndex : AppendPartial(t, m)
    \/ \E t \in Target : AppendConflict(t) \/ AppendHigherVote(t)
    \/ \E t \in Target, e \in {"timeout", "unreachable", "network", "remote"} :
          AppendRpcError(t, e)
    \/ \E t \in Target : ResetBackoffAfterReply(t) \/ BeginBackoff(t) \/ EndBackoff(t)
    \/ CoreHandleProgress
    \/ \E s \in STRING : ChangeCoreSession(s)
    \/ \E t \in Target, i \in 0..MaxInflight : StartSnapshot(t, i)
    \/ \E t \in Target : BeginSnapshotAttempt(t) \/ BeginSnapshotBackoff(t)
    \/ \E t \in Target, e \in {"timeout", "unreachable", "network", "remote"} :
          SnapshotRpcError(t, e)
    \/ \E t \in Target, m \in NoIndex..MaxIndex : SnapshotSuccess(t, m)
    \/ \E t \in Target : CloseTask(t)
    \/ \E t \in Target, p \in NoIndex..MaxIndex, l \in NoIndex..MaxIndex :
          StreamEnqueue(t, p, l)
    \/ \E t \in Target,
          o \in {"success", "partial", "conflict", "higher"},
          v \in NoIndex..MaxIndex : StreamResult(t, o, v)

Spec == Init /\ [][Next]_vars

TypeOK ==
    /\ active \in [Target -> BOOLEAN]
    /\ taskSession \in [Target -> STRING]
    /\ coreSession \in STRING
    /\ localCommitted \in [Target -> NoIndex..MaxIndex]
    /\ remoteMatching \in [Target -> NoIndex..MaxIndex]
    /\ pendingKind \in [Target -> TaskKinds]
    /\ pendingPrev \in [Target -> NoIndex..MaxIndex]
    /\ pendingLast \in [Target -> NoIndex..MaxIndex]
    /\ pendingInflight \in [Target -> NoInflight..MaxInflight]
    /\ rpcPending \in [Target -> BOOLEAN]
    /\ sentKind \in [Target -> TaskKinds]
    /\ sentPrev \in [Target -> NoIndex..MaxIndex]
    /\ sentLast \in [Target -> NoIndex..MaxIndex]
    /\ sentRequestLast \in [Target -> NoIndex..MaxIndex]
    /\ sentInflight \in [Target -> NoInflight..MaxInflight]
    /\ backoffActive \in [Target -> BOOLEAN]
    /\ waiting \in [Target -> BOOLEAN]
    /\ lastOutcome \in [Target -> Outcomes]
    /\ coreMatching \in [Target -> NoIndex..MaxIndex]
    /\ coreSearchingEnd \in [Target -> 0..(MaxIndex + 1)]
    /\ coreInflightKind \in [Target -> CoreInflightKinds]
    /\ coreInflightId \in [Target -> NoInflight..MaxInflight]
    /\ coreInflightPrev \in [Target -> NoIndex..MaxIndex]
    /\ coreInflightLast \in [Target -> NoIndex..MaxIndex]
    /\ \A n \in 1..Len(notifications) :
          /\ notifications[n].target \in Target
          /\ notifications[n].session \in STRING
          /\ notifications[n].inflight \in NoInflight..MaxInflight
          /\ notifications[n].outcome \in ProgressOutcomes
          /\ notifications[n].value \in NoIndex..MaxIndex
    /\ snapshotActive \in [Target -> BOOLEAN]
    /\ snapshotBackoff \in [Target -> BOOLEAN]
    /\ \A t \in Target :
          /\ \A q \in 1..Len(streamQueue[t]) :
               /\ streamQueue[t][q].prev \in NoIndex..MaxIndex
               /\ streamQueue[t][q].last \in NoIndex..MaxIndex
          /\ streamStopped[t] \in BOOLEAN
          /\ lastStreamOutcome[t] \in StreamOutcomes
          /\ attemptCount[t] \in 0..MaxAttempts
          /\ waitCount[t] \in 0..MaxAttempts
          /\ partialCount[t] \in 0..MaxAttempts
          /\ snapshotAttemptCount[t] \in 0..MaxAttempts
          /\ snapshotWaitCount[t] \in 0..MaxAttempts

OnePayloadInflight ==
    \A t \in Target :
        /\ coreInflightKind[t] \in CoreInflightKinds
        /\ (coreInflightKind[t] = "none") = (coreInflightId[t] = NoInflight)

SentRangeWellFormed ==
    \A t \in Target : rpcPending[t] =>
        /\ sentPrev[t] <= sentLast[t]
        /\ sentLast[t] <= sentRequestLast[t]
        /\ sentRequestLast[t] <= MaxIndex
        /\ (sentKind[t] = "committed" => sentPrev[t] = sentLast[t])
        /\ (sentKind[t] = "logs" => sentPrev[t] < sentLast[t])

WorkerMatchWithinSent ==
    \A t \in Target :
        lastOutcome[t] \in {"success", "partial"} => remoteMatching[t] <= sentLast[t]

PartialContinuationBounded ==
    \A t \in Target : pendingKind[t] = "logs" =>
        /\ pendingPrev[t] < pendingLast[t]
        /\ pendingInflight[t] \in 0..MaxInflight

WaitRequiresBackoff ==
    \A t \in Target : waiting[t] => backoffActive[t]

WaitCountBoundedByAttempts ==
    \A t \in Target : waitCount[t] <= attemptCount[t]

ProgressBounds ==
    \A t \in Target :
        /\ coreMatching[t] + 1 <= coreSearchingEnd[t]
        /\ coreSearchingEnd[t] <= MaxIndex + 1

SnapshotInflightConsistent ==
    \A t \in Target :
        snapshotActive[t] /\ taskSession[t] = coreSession =>
            coreInflightKind[t] = "snapshot"

StreamTerminalStable ==
    \A t \in Target : streamStopped[t] =>
        lastStreamOutcome[t] \in {"conflict", "higher"}

=============================================================================
