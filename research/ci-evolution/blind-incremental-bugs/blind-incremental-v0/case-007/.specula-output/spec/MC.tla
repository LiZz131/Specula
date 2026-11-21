----------------------------- MODULE MC -----------------------------
\* Finite-state wrapper for the exact-old replication boundary.
\* Bounds control exploration only; they are not protocol guarantees.

EXTENDS base

B == INSTANCE base

CONSTANT ModelSessions
CONSTANT MaxSpawn, MaxNewWork, MaxCommitUpdate, MaxSessionChange,
         MaxSnapshotStart, MaxStreamInput, MaxNotificationDepth, MaxStreamDepth

VARIABLE constraintCounters
mcVars == <<constraintCounters>>
MCVars == <<vars, constraintCounters>>

MCInit ==
    /\ Init
    /\ constraintCounters = [spawn |-> 0,
                              work |-> 0,
                              commit |-> 0,
                              session |-> 0,
                              snapshot |-> 0,
                              stream |-> 0]

\* Spawning is environment input and is bounded.
\* openraft/src/core/raft_core.rs:852-880
MCSpawn(t, s, c, m) ==
    /\ constraintCounters.spawn < MaxSpawn
    /\ B!SpawnReplication(t, s, c, m)
    /\ constraintCounters' = [constraintCounters EXCEPT !.spawn = @ + 1]

\* RaftCore log reservation/work arrival is bounded; task reactions are not.
\* openraft/src/progress/entry/mod.rs:112-164
MCReceiveLogs(t, p, l, i) ==
    /\ constraintCounters.work < MaxNewWork
    /\ B!ReceiveLogs(t, p, l, i)
    /\ constraintCounters' = [constraintCounters EXCEPT !.work = @ + 1]

MCReceiveCommitted(t, c) ==
    /\ constraintCounters.commit < MaxCommitUpdate
    /\ B!ReceiveCommitted(t, c)
    /\ constraintCounters' = [constraintCounters EXCEPT !.commit = @ + 1]

MCChangeSession(s) ==
    /\ constraintCounters.session < MaxSessionChange
    /\ B!ChangeCoreSession(s)
    /\ constraintCounters' = [constraintCounters EXCEPT !.session = @ + 1]

MCStartSnapshot(t, i) ==
    /\ constraintCounters.snapshot < MaxSnapshotStart
    /\ B!StartSnapshot(t, i)
    /\ constraintCounters' = [constraintCounters EXCEPT !.snapshot = @ + 1]

MCStreamEnqueue(t, p, l) ==
    /\ constraintCounters.stream < MaxStreamInput
    /\ Len(streamQueue[t]) < MaxStreamDepth
    /\ B!StreamEnqueue(t, p, l)
    /\ constraintCounters' = [constraintCounters EXCEPT !.stream = @ + 1]

Reactive(a) == a /\ UNCHANGED mcVars

MCNext ==
    \/ \E t \in Target, s \in ModelSessions,
          c \in NoIndex..MaxIndex, m \in NoIndex..MaxIndex : MCSpawn(t, s, c, m)
    \/ \E t \in Target, p \in NoIndex..MaxIndex,
          l \in 0..MaxIndex, i \in 0..MaxInflight : MCReceiveLogs(t, p, l, i)
    \/ \E t \in Target, c \in NoIndex..MaxIndex : MCReceiveCommitted(t, c)
    \/ \E t \in Target, l \in NoIndex..MaxIndex : Reactive(B!SendAppend(t, l))
    \/ \E t \in Target : Reactive(B!AppendSuccess(t))
    \/ \E t \in Target, m \in NoIndex..MaxIndex : Reactive(B!AppendPartial(t, m))
    \/ \E t \in Target : Reactive(B!AppendConflict(t)) \/ Reactive(B!AppendHigherVote(t))
    \/ \E t \in Target, e \in {"timeout", "unreachable", "network", "remote"} :
          Reactive(B!AppendRpcError(t, e))
    \/ \E t \in Target :
          Reactive(B!ResetBackoffAfterReply(t)) \/ Reactive(B!BeginBackoff(t)) \/ Reactive(B!EndBackoff(t))
    \/ Reactive(B!CoreHandleProgress)
    \/ \E s \in ModelSessions : MCChangeSession(s)
    \/ \E t \in Target, i \in 0..MaxInflight : MCStartSnapshot(t, i)
    \/ \E t \in Target : Reactive(B!BeginSnapshotAttempt(t)) \/ Reactive(B!BeginSnapshotBackoff(t))
    \/ \E t \in Target, e \in {"timeout", "unreachable", "network", "remote"} :
          Reactive(B!SnapshotRpcError(t, e))
    \/ \E t \in Target, m \in NoIndex..MaxIndex : Reactive(B!SnapshotSuccess(t, m))
    \/ \E t \in Target : Reactive(B!CloseTask(t))
    \/ \E t \in Target, p \in NoIndex..MaxIndex, l \in NoIndex..MaxIndex :
          MCStreamEnqueue(t, p, l)
    \/ \E t \in Target,
          o \in {"success", "partial", "conflict", "higher"},
          v \in NoIndex..MaxIndex : Reactive(B!StreamResult(t, o, v))
    \/ UNCHANGED MCVars

MCSpec == MCInit /\ [][MCNext]_MCVars

NotificationDepthConstraint == Len(notifications) <= MaxNotificationDepth

MCTypeOK == TypeOK /\
    constraintCounters \in
        [spawn : 0..MaxSpawn,
         work : 0..MaxNewWork,
         commit : 0..MaxCommitUpdate,
         session : 0..MaxSessionChange,
         snapshot : 0..MaxSnapshotStart,
         stream : 0..MaxStreamInput]

\* Reachability witnesses are separate from correctness invariants and are
\* checked with dedicated bounded configs/scripts.
SeenAppendAttempt == \E t \in Target : attemptCount[t] > 0
SeenPartial == \E t \in Target : partialCount[t] > 0
SeenBackoffWait == \E t \in Target : waitCount[t] > 0
SeenSnapshot == \E t \in Target : snapshotAttemptCount[t] > 0
SeenStreamTerminal == \E t \in Target : streamStopped[t]
SeenSessionRollover == constraintCounters.session > 0

\* Negations are used only as deliberate reachability checks. A TLC invariant
\* violation in those dedicated runs is the expected witness, not a finding.
NotSeenAppendAttempt == ~SeenAppendAttempt
NotSeenPartial == ~SeenPartial
NotSeenBackoffWait == ~SeenBackoffWait
NotSeenSnapshot == ~SeenSnapshot
NotSeenStreamTerminal == ~SeenStreamTerminal
NotSeenSessionRollover == ~SeenSessionRollover

=============================================================================
