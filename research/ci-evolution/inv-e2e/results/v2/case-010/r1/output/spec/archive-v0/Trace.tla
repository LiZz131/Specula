------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils, Sequences, TLC

(***************************************************************************)
(* Linear replay of the mutex-serialized Category-A NDJSON event stream.    *)
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
StatefulEvent == "schemaVersion" \in DOMAIN logline /\ logline.schemaVersion = 2

SeqToSet(q) == {q[k] : k \in 1..Len(q)}

ValidateCommonPost(s) ==
    /\ "state" \in DOMAIN logline.event
    /\ "running" \in DOMAIN logline.event.state
    /\ "role" \in DOMAIN logline.event.state
    /\ "phase" \in DOMAIN logline.event.state
    /\ "syncMode" \in DOMAIN logline.event.state
    /\ "acceptedEpoch" \in DOMAIN logline.event.state
    /\ "currentEpoch" \in DOMAIN logline.event.state
    /\ running'[s] = logline.event.state.running
    /\ role'[s] = logline.event.state.role
    /\ phase'[s] = logline.event.state.phase
    /\ syncMode'[s] = logline.event.state.syncMode
    /\ acceptedEpoch'[s] = logline.event.state.acceptedEpoch
    /\ currentEpoch'[s] = logline.event.state.currentEpoch

ValidateRestartPost(s) ==
    IF StatefulEvent THEN
        /\ "prepared" \in DOMAIN logline.event.state
        /\ "syncQueued" \in DOMAIN logline.event.state
        /\ "pending" \in DOMAIN logline.event.state
        /\ "durable" \in DOMAIN logline.event.state
        /\ "recoveryVisible" \in DOMAIN logline.event.state
        /\ "syncComplete" \in DOMAIN logline.event.state
        /\ "newLeaderReady" \in DOMAIN logline.event.state
        /\ prepared'[s] = logline.event.state.prepared
        /\ syncQueued'[s] = logline.event.state.syncQueued
        /\ pending'[s] = logline.event.state.pending
        /\ durable'[s] = logline.event.state.durable
        /\ recoveryVisible'[s] = logline.event.state.recoveryVisible
        /\ syncComplete'[s] = logline.event.state.syncComplete
        /\ newLeaderReady'[s] = logline.event.state.newLeaderReady
    ELSE TRUE

ValidateElectionPost(s) ==
    IF StatefulEvent THEN
        /\ "leaderOf" \in DOMAIN logline.event.state
        /\ leaderOf'[s] = logline.event.state.leaderOf
    ELSE TRUE

ValidateSyncCompletePost(s) ==
    IF StatefulEvent THEN
        /\ "prepared" \in DOMAIN logline.event.state
        /\ "durable" \in DOMAIN logline.event.state
        /\ "recoveryVisible" \in DOMAIN logline.event.state
        /\ "committed" \in DOMAIN logline.event.state
        /\ "applied" \in DOMAIN logline.event.state
        /\ "syncComplete" \in DOMAIN logline.event.state
        /\ prepared'[s] = logline.event.state.prepared
        /\ durable'[s] = logline.event.state.durable
        /\ recoveryVisible'[s] = logline.event.state.recoveryVisible
        /\ committed'[s] = logline.event.state.committed
        /\ applied'[s] = logline.event.state.applied
        /\ syncComplete'[s] = logline.event.state.syncComplete
    ELSE TRUE

ValidateNewLeaderPost(s) ==
    IF StatefulEvent THEN
        /\ "newLeaderReady" \in DOMAIN logline.event.state
        /\ newLeaderReady'[s] = logline.event.state.newLeaderReady
    ELSE TRUE

ValidatePreparedPost(s) ==
    IF StatefulEvent THEN
        /\ "prepared" \in DOMAIN logline.event.state
        /\ prepared'[s] = logline.event.state.prepared
    ELSE TRUE

ValidateLeaderProposePost(s) ==
    IF StatefulEvent THEN
        /\ ValidatePreparedPost(s)
        /\ "nextTxn" \in DOMAIN logline.event.state
        /\ nextTxn' = logline.event.state.nextTxn
    ELSE TRUE

ValidatePendingPost(s) ==
    IF StatefulEvent THEN
        /\ ValidatePreparedPost(s)
        /\ "pending" \in DOMAIN logline.event.state
        /\ pending'[s] = logline.event.state.pending
    ELSE TRUE

ValidateQueuePost(s) ==
    IF StatefulEvent THEN
        /\ "syncQueued" \in DOMAIN logline.event.state
        /\ syncQueued'[s] = logline.event.state.syncQueued
    ELSE TRUE

ValidateFlushPost(s, t) ==
    IF StatefulEvent THEN
        /\ "durable" \in DOMAIN logline.event.state
        /\ "durabilityEvidence" \in DOMAIN logline.event.state
        /\ durable'[s] = logline.event.state.durable
        /\ durabilityEvidence'[t] = SeqToSet(logline.event.state.durabilityEvidence)
    ELSE TRUE

ValidateAckPost(t) ==
    IF StatefulEvent THEN
        /\ "acks" \in DOMAIN logline.event.state
        /\ acks'[t] = SeqToSet(logline.event.state.acks)
    ELSE TRUE

ValidateLeaderCommitPost(s, t) ==
    IF StatefulEvent THEN
        /\ "committed" \in DOMAIN logline.event.state
        /\ "globalCommitted" \in DOMAIN logline.event.state
        /\ "commitWitness" \in DOMAIN logline.event.state
        /\ committed'[s] = logline.event.state.committed
        /\ globalCommitted' = logline.event.state.globalCommitted
        /\ commitWitness'[t] = SeqToSet(logline.event.state.commitWitness)
    ELSE TRUE

ValidateFollowerCommitPost(s) ==
    IF StatefulEvent THEN
        /\ "committed" \in DOMAIN logline.event.state
        /\ committed'[s] = logline.event.state.committed
    ELSE TRUE

ValidateApplyPost(s) ==
    IF StatefulEvent THEN
        /\ "applied" \in DOMAIN logline.event.state
        /\ applied'[s] = logline.event.state.applied
    ELSE TRUE

ValidateBeginSnapshotPost(s) ==
    IF StatefulEvent THEN
        /\ "snapshotBusy" \in DOMAIN logline.event.state
        /\ "snapshotImage" \in DOMAIN logline.event.state
        /\ snapshotBusy'[s] = logline.event.state.snapshotBusy
        /\ snapshotImage'[s] = logline.event.state.snapshotImage
    ELSE TRUE

ValidateFinishSnapshotPost(s) ==
    IF StatefulEvent THEN
        /\ "snapshotBusy" \in DOMAIN logline.event.state
        /\ "snapshotPublished" \in DOMAIN logline.event.state
        /\ snapshotBusy'[s] = logline.event.state.snapshotBusy
        /\ snapshotPublished'[s] = logline.event.state.snapshotPublished
    ELSE TRUE

Consume(s) == l' = l + 1 /\ ValidateCommonPost(s)

RestartIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("RestartLoadDatabase", s)
        /\ RestartLoadDatabase(s,
              logline.event.state.acceptedEpoch,
              logline.event.state.currentEpoch)
        /\ ValidateRestartPost(s)
        /\ Consume(s)

ShutdownIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("GracefulShutdown", s)
        /\ GracefulShutdown(s)
        /\ Consume(s)

ElectionIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FinishElection", s)
        /\ logline.event.msg.leader \in Server
        /\ ObserveElectionResult(s, logline.event.msg.leader)
        /\ ValidateElectionPost(s)
        /\ Consume(s)

PhaseIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("SetZabState", s)
        /\ ObserveSetZabState(s, logline.event.state.phase)
        /\ Consume(s)

PeerStateIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("SetPeerState", s)
        /\ ObserveSetPeerState(s, logline.event.state.role)
        /\ Consume(s)

AcceptedEpochIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("PersistAcceptedEpoch", s)
        /\ PersistAcceptedEpoch(s, logline.event.state.acceptedEpoch)
        /\ Consume(s)

CurrentEpochIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("PersistCurrentEpoch", s)
        /\ PersistCurrentEpoch(s, logline.event.state.currentEpoch)
        /\ Consume(s)

SyncModeIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ChooseSyncMode", s)
        /\ ChooseSyncMode(s, logline.event.state.syncMode)
        /\ Consume(s)

SyncCompleteIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("CompleteLearnerSync", s)
        /\ logline.event.msg.leader \in Server
        /\ logline.event.msg.selectedMode \in Modes
        /\ CompleteLearnerSync(s,
              logline.event.msg.leader,
              logline.event.msg.selectedMode)
        /\ ValidateSyncCompletePost(s)
        /\ Consume(s)

NewLeaderQuorumIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FormNewLeaderQuorum", s)
        /\ ObserveNewLeaderQuorum(s)
        /\ ValidateNewLeaderPost(s)
        /\ Consume(s)

LeaderProposeIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LeaderPropose", s)
        /\ LeaderPropose(s, logline.event.msg.tx)
        /\ ValidateLeaderProposePost(s)
        /\ Consume(s)

FollowerPendingIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FollowerPendingProposal", s)
        /\ FollowerPendingProposal(s, logline.event.msg.tx)
        /\ ValidatePendingPost(s)
        /\ Consume(s)

QueueIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("QueueForSync", s)
        /\ QueueForSync(s, logline.event.msg.tx)
        /\ ValidateQueuePost(s)
        /\ Consume(s)

FlushIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FlushTxnLog", s)
        /\ FlushTxnLog(s, logline.event.msg.tx)
        /\ ValidateFlushPost(s, logline.event.msg.tx)
        /\ Consume(s)

AckIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("RecordProposalAck", s)
        /\ logline.event.msg.source \in Server
        /\ RecordProposalAck(s,
              logline.event.msg.source,
              logline.event.msg.tx)
        /\ ValidateAckPost(logline.event.msg.tx)
        /\ Consume(s)

CommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("CommitProposal", s)
        /\ CommitProposal(s, logline.event.msg.tx)
        /\ ValidateLeaderCommitPost(s, logline.event.msg.tx)
        /\ Consume(s)

FollowerCommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FollowerCommit", s)
        /\ FollowerCommit(s, logline.event.msg.tx)
        /\ ValidateFollowerCommitPost(s)
        /\ Consume(s)

ApplyIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ApplyTxn", s)
        /\ ApplyTxn(s, logline.event.msg.tx)
        /\ ValidateApplyPost(s)
        /\ Consume(s)

BeginSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("BeginSnapshot", s)
        /\ BeginSnapshot(s)
        /\ ValidateBeginSnapshotPost(s)
        /\ Consume(s)

FinishSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FinishSnapshot", s)
        /\ FinishSnapshot(s)
        /\ ValidateFinishSnapshotPost(s)
        /\ Consume(s)

TraceNext ==
    \/ RestartIfLogged
    \/ ShutdownIfLogged
    \/ ElectionIfLogged
    \/ PeerStateIfLogged
    \/ PhaseIfLogged
    \/ AcceptedEpochIfLogged
    \/ CurrentEpochIfLogged
    \/ SyncModeIfLogged
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

\* REQ-EVIDENCE TraceMatched
\* intent:   trace validation: the replay eventually consumes every event of the recorded trace
\* status:   model-internal
\* verified: base
\* review:   ok
TraceMatched == <>(l > Len(TraceLog))

TraceView == <<vars, l>>

TraceAlias ==
    [cursor |-> l,
     length |-> Len(TraceLog),
     event |-> IF l <= Len(TraceLog) THEN logline.event.name ELSE "DONE",
     node |-> IF l <= Len(TraceLog) THEN logline.event.nid ELSE "DONE",
     roles |-> role,
     phases |-> phase,
     epochs |-> [s \in Server |-> <<acceptedEpoch[s], currentEpoch[s]>>],
     histories |-> [s \in Server |->
         [durable |-> durable[s], committed |-> committed[s], applied |-> applied[s]]]]

=============================================================================
