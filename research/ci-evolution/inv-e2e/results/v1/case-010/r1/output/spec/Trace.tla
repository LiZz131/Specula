------------------------------ MODULE Trace ------------------------------
EXTENDS base, UpdateProps, Json, IOUtils, Sequences, TLC

(***************************************************************************)
(* Linear replay of the mutex-serialized Category-A NDJSON event stream.    *)
(* Schema version 3 (update revision) carries real implementation          *)
(* observations for the changed learner-shutdown path; every v3 field below *)
(* is mandatory and compared with the primed (or, where noted, unprimed)   *)
(* reference state.  Events without schemaVersion 3 are archived V0 traces *)
(* and are checked on the common fields only.                              *)
(***************************************************************************)

JsonFile == IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON ELSE "../traces/trace.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x :
        /\ "tag" \in DOMAIN x /\ x.tag = "trace"
        /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0

VARIABLE l
traceVars == <<vars, l>>
logline == TraceLog[l]

TraceServers == TLCEval({TraceLog[k].event.nid : k \in 1..Len(TraceLog)})
ASSUME TraceServers /= {}
ASSUME TraceServers \subseteq Server

TraceInit == TraceBaseInit /\ l = 1

IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name
IsNodeEvent(name, s) == IsEvent(name) /\ logline.event.nid = s
V3 == "schemaVersion" \in DOMAIN logline /\ logline.schemaVersion = 3
St == logline.event.state
Msg == logline.event.msg
Has(r, f) == f \in DOMAIN r

SeqToSet(q) == {q[k] : k \in 1..Len(q)}

ValidateCommonPost(s) ==
    /\ Has(St, "running") /\ Has(St, "role") /\ Has(St, "phase")
    /\ Has(St, "syncMode") /\ Has(St, "acceptedEpoch") /\ Has(St, "currentEpoch")
    /\ running'[s] = St.running
    /\ role'[s] = St.role
    /\ phase'[s] = St.phase
    /\ syncMode'[s] = St.syncMode
    /\ acceptedEpoch'[s] = St.acceptedEpoch
    /\ currentEpoch'[s] = St.currentEpoch

Consume(s) == l' = l + 1 /\ ValidateCommonPost(s)

\* v3: the real recovered history (snapshot base + replayed WAL records,
\* SpeculaTrace.recovered) equals the model's recoverable history.
RestartIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("RestartLoadDatabase", s)
        /\ RestartLoadDatabase(s, St.acceptedEpoch, St.currentEpoch)
        /\ V3 => /\ Has(St, "recovered")
                 /\ durable[s] = St.recovered
                 /\ prepared'[s] = ReplayHistory(St.recovered)
        /\ Consume(s)

ReloadIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ReloadDatabase", s)
        /\ ReloadDatabase(s)
        /\ Has(St, "recovered")
        /\ durable[s] = St.recovered
        /\ prepared'[s] = ReplayHistory(St.recovered)
        /\ Consume(s)

ShutdownIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("GracefulShutdown", s)
        /\ GracefulShutdown(s)
        /\ Consume(s)

\* UPDATE: Learner.shutdown (Learner.java:850-866).  served = zk.isRunning()
\* before the call; full = syncMode==SNAP; leakedNow = this call left a live
\* SyncRequestProcessor that was not already leaked; leakedQueue = its
\* unflushed modeled requests; dbInit = zkDb.isInitialized() afterwards.
LearnerShutdownIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerShutdown", s)
        /\ Has(Msg, "served") /\ Has(Msg, "full") /\ Has(Msg, "leakedNow")
        /\ Has(Msg, "leakedQueue") /\ Has(Msg, "dbInit")
        /\ Msg.served = ZkServing(s)
        /\ Msg.full = (LearnerShutdownSemantics = "UPDATED" /\ syncMode[s] = "SNAP")
        /\ Msg.leakedNow = (ProcessorsStarted(s) /\ ~(LearnerShutdownSemantics = "PRIOR" /\ ZkServing(s)))
        /\ LearnerShutdown(s)
        /\ dbCleared'[s] = ~Msg.dbInit
        /\ leakedQueued'[s] = IF Msg.leakedQueue = <<>> THEN leakedQueued[s]
                              ELSE Append(leakedQueued[s], Msg.leakedQueue)
        /\ Consume(s)

ElectionIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FinishElection", s)
        /\ Msg.leader \in Server
        /\ ObserveElectionResult(s, Msg.leader)
        /\ V3 => leaderOf'[s] = Msg.leader
        /\ Consume(s)

PhaseIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("SetZabState", s)
        /\ ObserveSetZabState(s, St.phase)
        /\ Consume(s)

LookingPair(s) ==
    /\ IsNodeEvent("SetPeerState", s) /\ St.role = "LOOKING"
    /\ l + 1 <= Len(TraceLog)
    /\ TraceLog[l + 1].event.name = "SetZabState"
    /\ TraceLog[l + 1].event.nid = s
    /\ TraceLog[l + 1].event.state.phase = "ELECTION"

PeerStateIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("SetPeerState", s)
        /\ ~LookingPair(s)
        /\ ObserveSetPeerState(s, St.role)
        /\ Consume(s)

\* setPeerState(LOOKING) + nested setZabState(ELECTION): one composite step;
\* both events' common fields are checked (first role, then the full second).
PeerLookingIfLogged ==
    \E s \in Server :
        /\ LookingPair(s)
        /\ ObserveSetPeerStateLooking(s)
        /\ role'[s] = St.role
        /\ l' = l + 2
        /\ LET nx == TraceLog[l + 1].event.state IN
              /\ running'[s] = nx.running /\ role'[s] = nx.role
              /\ phase'[s] = nx.phase /\ syncMode'[s] = nx.syncMode
              /\ acceptedEpoch'[s] = nx.acceptedEpoch
              /\ currentEpoch'[s] = nx.currentEpoch

AcceptedEpochIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("PersistAcceptedEpoch", s)
        /\ PersistAcceptedEpoch(s, St.acceptedEpoch)
        /\ Consume(s)

CurrentEpochIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("PersistCurrentEpoch", s)
        /\ PersistCurrentEpoch(s, St.currentEpoch)
        /\ Consume(s)

\* QuorumPeer.setSyncMode: DIFF/SNAP/TRUNC at sync start, NONE at NEWLEADER.
SyncModeIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ChooseSyncMode", s)
        /\ IF St.syncMode = "NONE"
           THEN LearnerNewLeader(s)
           ELSE ChooseSyncMode(s, St.syncMode)
        /\ Consume(s)

\* UPDATE producer: SNAP image loaded (Learner.java:570-583).
LoadSyncSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LoadSyncSnapshot", s)
        /\ LoadSyncSnapshot(s)
        /\ Has(Msg, "lastZxid")
        /\ LastOr0(prepared'[s]) = Msg.lastZxid
        /\ Consume(s)

TruncateLogIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("TruncateLog", s)
        /\ TruncateLog(s)
        /\ Has(Msg, "lastZxid") /\ Has(St, "recovered")
        /\ durable'[s] = St.recovered
        /\ LastOr0(prepared'[s]) = Msg.lastZxid
        /\ Consume(s)

ApplySyncCommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ApplySyncCommit", s)
        /\ ApplySyncCommit(s, Msg.tx)
        /\ Has(Msg, "lastZxid") /\ Msg.lastZxid = Msg.tx
        /\ Consume(s)

SyncCompleteIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("CompleteLearnerSync", s)
        /\ Msg.leader \in Server
        /\ CompleteLearnerSync(s, Msg.leader)
        /\ Consume(s)

NewLeaderQuorumIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FormNewLeaderQuorum", s)
        /\ ObserveNewLeaderQuorum(s)
        /\ Consume(s)

LeaderProposeIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LeaderPropose", s)
        /\ LeaderPropose(s, Msg.tx)
        /\ nextTxn' = Msg.tx + 1
        /\ Consume(s)

FollowerPendingIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FollowerPendingProposal", s)
        /\ FollowerPendingProposal(s, Msg.tx)
        /\ V3 => (Has(St, "pending") /\ pending'[s] = St.pending)
        /\ Consume(s)

QueueIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("QueueForSync", s)
        /\ QueueForSync(s, Msg.tx)
        /\ V3 => (Has(St, "queue") /\ syncQueued'[s] = St.queue)
        /\ Consume(s)

FlushIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FlushTxnLog", s)
        /\ IF V3 /\ Has(Msg, "leaked") /\ Msg.leaked
           THEN \E i \in 1..Len(leakedQueued[s]) :
                /\ FlushLeakedTxnLog(s, i, Msg.tx)
                /\ IF St.queue = <<>>
                   THEN Len(leakedQueued'[s]) = Len(leakedQueued[s]) - 1
                   ELSE leakedQueued'[s][i] = St.queue
           ELSE /\ FlushTxnLog(s, Msg.tx)
                /\ V3 => (Has(St, "queue") /\ syncQueued'[s] = St.queue)
        /\ Consume(s)

AckIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("RecordProposalAck", s)
        /\ Msg.source \in Server
        /\ RecordProposalAck(s, Msg.source, Msg.tx)
        /\ V3 => (Has(St, "acks") /\ acks'[Msg.tx] = SeqToSet(St.acks))
        /\ Consume(s)

CommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("CommitProposal", s)
        /\ CommitProposal(s, Msg.tx)
        /\ V3 => (Has(St, "commitWitness") /\ commitWitness'[Msg.tx] = SeqToSet(St.commitWitness))
        /\ Consume(s)

FollowerCommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FollowerCommit", s)
        /\ FollowerCommit(s, Msg.tx)
        /\ V3 => (Has(St, "pending") /\ pending'[s] = St.pending)
        /\ Consume(s)

ApplyIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ApplyTxn", s)
        /\ ApplyTxn(s, Msg.tx)
        /\ V3 => (Has(Msg, "lastZxid") /\ Msg.lastZxid = Msg.tx)
        /\ Consume(s)

BeginSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("BeginSnapshot", s)
        /\ BeginSnapshot(s)
        /\ V3 => (Has(Msg, "lastZxid") /\ LastOr0(snapshotImage'[s]) = Msg.lastZxid)
        /\ Consume(s)

\* NEWLEADER snapshot of a SNAP/TRUNC image is FinishSyncSnapshot (durable
\* effect validated at the next real recovery); others are FinishSnapshot.
FinishSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FinishSnapshot", s)
        /\ \/ FinishSnapshot(s)
           \/ /\ FinishSyncSnapshot(s)
              /\ V3 => (Has(Msg, "syncSnap") /\ Msg.syncSnap = (syncMode[s] = "SNAP"))
        /\ Consume(s)

TraceNext ==
    \/ RestartIfLogged
    \/ ReloadIfLogged
    \/ ShutdownIfLogged
    \/ LearnerShutdownIfLogged
    \/ ElectionIfLogged
    \/ PeerStateIfLogged
    \/ PeerLookingIfLogged
    \/ PhaseIfLogged
    \/ AcceptedEpochIfLogged
    \/ CurrentEpochIfLogged
    \/ SyncModeIfLogged
    \/ LoadSyncSnapshotIfLogged
    \/ TruncateLogIfLogged
    \/ ApplySyncCommitIfLogged
    \/ SyncCompleteIfLogged
    \/ NewLeaderQuorumIfLogged
    \/ LeaderProposeIfLogged
    \/ FollowerPendingIfLogged
    \/ QueueIfLogged
    \/ FlushIfLogged
    \/ AckIfLogged
    \/ CommitIfLogged
    \/ FollowerCommitIfLogged
    \/ ApplyIfLogged
    \/ BeginSnapshotIfLogged
    \/ FinishSnapshotIfLogged

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

TraceView == <<vars, l>>

TraceAlias ==
    [cursor |-> l,
     length |-> Len(TraceLog),
     event |-> IF l <= Len(TraceLog) THEN logline.event.name ELSE "DONE",
     node |-> IF l <= Len(TraceLog) THEN logline.event.nid ELSE "DONE",
     roles |-> role,
     phases |-> phase,
     stages |-> learnerStage,
     modes |-> syncMode,
     cleared |-> dbCleared,
     epochs |-> [s \in Server |-> <<acceptedEpoch[s], currentEpoch[s]>>],
     histories |-> [s \in Server |->
         [prepared |-> prepared[s], durable |-> durable[s],
          queued |-> syncQueued[s], leaked |-> leakedQueued[s],
          pending |-> pending[s],
          committed |-> committed[s], applied |-> applied[s]]]]

=============================================================================
