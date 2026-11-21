------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils, Sequences, TLC

(***************************************************************************)
(* Linear replay (Category A) of the mutex-serialized NDJSON stream written *)
(* by the rebased schema-v3 probe (harness/patches/instrumentation.patch).  *)
(* Every event drives a base action; post-states are compared with fields   *)
(* read from real objects: QuorumPeer epochs/role/phase/syncMode, ZKDatabase *)
(* initialized flag and data-tree lastProcessedZxid (memInit/memLast), and   *)
(* the on-disk last zxid of txn log / newest snapshot (durableLast).         *)
(***************************************************************************)

JsonFile == IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON ELSE "../traces/snap-abort-rejoin-v3.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x :
        /\ "tag" \in DOMAIN x /\ x.tag = "trace"
        /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0
ASSUME \A k \in 1..Len(TraceLog) :
          "schemaVersion" \in DOMAIN TraceLog[k] /\ TraceLog[k].schemaVersion = 3

VARIABLE l
traceVars == <<vars, l>>
logline == TraceLog[l]
st == logline.event.state
msg == logline.event.msg

TraceServers == TLCEval({TraceLog[k].event.nid : k \in 1..Len(TraceLog)})
ASSUME TraceServers \subseteq Server

TraceInit == TraceBaseInit /\ l = 1

IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name
IsNodeEvent(name, s) == IsEvent(name) /\ logline.event.nid = s

SeqToSet(q) == {q[k] : k \in 1..Len(q)}

\* Common fields on every event (QuorumPeer state read under the probe lock).
ValidateCommonPost(s) ==
    /\ running'[s] = st.running
    /\ role'[s] = st.role
    /\ phase'[s] = st.phase
    /\ syncMode'[s] = st.syncMode
    /\ acceptedEpoch'[s] = st.acceptedEpoch
    /\ currentEpoch'[s] = st.currentEpoch

\* Mandatory on update-local events and ApplyTxn: real ZKDatabase state.
ValidateMemPost(s) ==
    /\ "memInit" \in DOMAIN st /\ "memLast" \in DOMAIN st
    /\ memInit'[s] = st.memInit
    /\ LastOf(memDb'[s]) = st.memLast

\* Mandatory on reload, truncation and sync-snapshot events: real disk.
ValidateDurablePost(s) ==
    /\ "durableLast" \in DOMAIN st
    /\ LastOf(durable'[s]) = st.durableLast

Consume(s) == l' = l + 1 /\ ValidateCommonPost(s)

-----------------------------------------------------------------------------

\* QuorumPeer.loadDataBase: process start when the peer is not running in the
\* model, otherwise the in-process reload of a cleared ZKDatabase.
LoadIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("RestartLoadDatabase", s)
        /\ IF running[s]
           THEN ReloadDatabase(s)
           ELSE RestartLoadDatabase(s, st.acceptedEpoch, st.currentEpoch)
        /\ ValidateMemPost(s) /\ ValidateDurablePost(s)
        /\ Consume(s)

ShutdownIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("GracefulShutdown", s)
        /\ GracefulShutdown(s)
        /\ Consume(s)

\* Update-affected action. The probe reports the boolean actually passed to
\* ZooKeeperServer.shutdown and an unsynchronized isRunning() read taken just
\* before it. Two callers can race (QuorumPeer.shutdown, QuorumPeer.java:1544-
\* 1546, and the run loop's finally, :1476): ZooKeeperServer.shutdown is
\* synchronized, so whichever event is emitted first is emitted after the
\* effectful call completed; the model applies the effect there. A caller
\* that reads "not running" may be the one waiting on the effectful caller,
\* hence only RUNNING => syncComplete is required. A duplicate call that
\* returns after updateServerState of a stopped peer is a stutter.
LearnerShutdownIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerShutdown", s)
        /\ msg.fullyShutDown = (UpdateFullShutdownOnSnap /\ syncMode[s] = "SNAP")
        /\ IF role[s] = "FOLLOWING"
           THEN /\ (msg.zkWasRunning => syncComplete[s])
                /\ LearnerShutdown(s)
           ELSE /\ ~running[s] /\ role[s] = "LOOKING"
                /\ UNCHANGED vars
        /\ ValidateMemPost(s)
        /\ Consume(s)

ElectionIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FinishElection", s)
        /\ msg.leader \in Server
        /\ ObserveElectionResult(s, msg.leader)
        /\ leaderOf'[s] = msg.leader
        /\ Consume(s)

PeerStateIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("SetPeerState", s)
        /\ IF st.role = "LOOKING" /\ role[s] = "FOLLOWING" /\ syncStage[s] = "EXITED"
           THEN FollowerExitToLooking(s)
           ELSE ObserveSetPeerState(s, st.role)
        /\ Consume(s)

PhaseIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("SetZabState", s)
        /\ CASE st.phase = "SYNCHRONIZATION" /\ role[s] = "LEADING" ->
                    LeaderStartSyncCore(s)
             [] st.phase = "SYNCHRONIZATION" /\ role[s] = "FOLLOWING" ->
                    EnterFollowerSync(s)
             [] st.phase = "BROADCAST" /\ role[s] = "LEADING" ->
                    LeaderEnterBroadcast(s)
             [] st.phase = "BROADCAST" /\ role[s] = "FOLLOWING" ->
                    FollowerEnterBroadcast(s)
             [] st.phase = "DISCOVERY" /\ phase[s] = "ELECTION"
                /\ role[s] \in {"LEADING", "FOLLOWING"} ->
                    EnterDiscovery(s)
             [] st.phase = "ELECTION" /\ role[s] = "LOOKING" /\ phase[s] # "ELECTION" ->
                    EnterElectionPhase(s)
             [] OTHER -> ObserveSetZabState(s, st.phase)
        /\ Consume(s)

AcceptedEpochIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("PersistAcceptedEpoch", s)
        /\ IF role[s] = "LEADING"
           THEN LeaderPersistEpoch(s, st.acceptedEpoch)
           ELSE PersistAcceptedEpoch(s, st.acceptedEpoch)
        /\ Consume(s)

CurrentEpochIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("PersistCurrentEpoch", s)
        /\ IF role[s] = "FOLLOWING" /\ phase[s] = "SYNCHRONIZATION"
           THEN LearnerPersistCurrentEpoch(s)
           ELSE PersistCurrentEpoch(s, st.currentEpoch)
        /\ Consume(s)

SyncModeIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ChooseSyncMode", s)
        /\ IF st.syncMode = "NONE"
           THEN LearnerNewLeaderModeNone(s)
           ELSE ChooseSyncMode(s, st.syncMode)
        /\ Consume(s)

ReportedIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ObserveReportedZxid", s)
        /\ memInit[s] /\ LastZxid(s) = msg.zxid
        \* ACKEPOCH was just written: the leader counts it if still collecting.
        /\ IF leaderOf[s] \in Server /\ phase[leaderOf[s]] = "DISCOVERY"
              /\ epochProposal[leaderOf[s]] > currentEpoch[leaderOf[s]]
           THEN RecordEpochAck(leaderOf[s], s)
           ELSE UNCHANGED vars
        /\ ValidateMemPost(s)
        /\ Consume(s)

ApplySnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerApplySnapshot", s)
        /\ LearnerApplySnapshot(s)
        /\ ValidateMemPost(s)
        /\ Consume(s)

TruncateIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerTruncateLog", s)
        /\ LearnerTruncateLog(s)
        /\ ValidateMemPost(s) /\ ValidateDurablePost(s)
        /\ Consume(s)

SyncPacketIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerSyncPacket", s)
        /\ LearnerSyncPacket(s, msg.tx)
        /\ Consume(s)

SyncCommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerSyncCommit", s)
        /\ msg.inMemory = (syncMode[s] \in {"SNAP", "TRUNC"} /\ syncStage[s] = "DATA")
        /\ LearnerSyncCommit(s)
        /\ IF msg.inMemory
           THEN syncBuf[s] # <<>> /\ Head(syncBuf[s]) = msg.tx
           ELSE LastOf(syncCommits'[s]) = msg.tx
        /\ ValidateMemPost(s)
        /\ Consume(s)

SyncSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerSyncSnapshot", s)
        /\ LearnerSyncSnapshot(s)
        /\ ValidateMemPost(s) /\ ValidateDurablePost(s)
        /\ Consume(s)

AckNewLeaderIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("AckNewLeader", s)
        /\ LearnerAckNewLeader(s)
        /\ Consume(s)

NewLeaderQuorumIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FormNewLeaderQuorum", s)
        /\ ObserveNewLeaderQuorum(s)
        /\ Consume(s)

UpToDateIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LearnerUpToDate", s)
        /\ LearnerUpToDate(s)
        /\ ValidateMemPost(s)
        /\ Consume(s)

SyncCompleteIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("CompleteLearnerSync", s)
        /\ msg.leader = leaderOf[s]
        /\ CompleteLearnerSync(s)
        /\ Consume(s)

LeaderProposeIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("LeaderPropose", s)
        /\ LeaderPropose(s, msg.tx)
        /\ Consume(s)

FollowerPendingIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FollowerPendingProposal", s)
        /\ FollowerPendingProposal(s, msg.tx)
        /\ Consume(s)

QueueIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("QueueForSync", s)
        /\ QueueForSync(s, msg.tx)
        /\ Consume(s)

FlushIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FlushTxnLog", s)
        /\ FlushTxnLog(s, msg.tx)
        /\ Consume(s)

AckIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("RecordProposalAck", s)
        /\ msg.source \in Server
        /\ RecordProposalAck(s, msg.source, msg.tx)
        /\ Consume(s)

CommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("CommitProposal", s)
        /\ CommitProposal(s, msg.tx)
        /\ Consume(s)

FollowerCommitIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FollowerCommit", s)
        /\ FollowerCommit(s, msg.tx)
        /\ Consume(s)

ApplyIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("ApplyTxn", s)
        /\ ApplyTxn(s, msg.tx)
        /\ ValidateMemPost(s)
        /\ Consume(s)

BeginSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("BeginSnapshot", s)
        /\ BeginSnapshot(s)
        /\ Consume(s)

FinishSnapshotIfLogged ==
    \E s \in Server :
        /\ IsNodeEvent("FinishSnapshot", s)
        /\ FinishSnapshot(s)
        /\ Consume(s)

TraceNext ==
    \/ LoadIfLogged
    \/ ShutdownIfLogged
    \/ LearnerShutdownIfLogged
    \/ ElectionIfLogged
    \/ PeerStateIfLogged
    \/ PhaseIfLogged
    \/ AcceptedEpochIfLogged
    \/ CurrentEpochIfLogged
    \/ SyncModeIfLogged
    \/ ReportedIfLogged
    \/ ApplySnapshotIfLogged
    \/ TruncateIfLogged
    \/ SyncPacketIfLogged
    \/ SyncCommitIfLogged
    \/ SyncSnapshotIfLogged
    \/ AckNewLeaderIfLogged
    \/ NewLeaderQuorumIfLogged
    \/ UpToDateIfLogged
    \/ SyncCompleteIfLogged
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
     roles |-> role, phases |-> phase, modes |-> syncMode, stages |-> syncStage,
     epochs |-> [s \in Server |-> <<acceptedEpoch[s], currentEpoch[s]>>],
     mem |-> [s \in Server |-> <<memInit[s], memDb[s]>>],
     durable |-> durable, syncBuf |-> syncBuf, syncCommits |-> syncCommits,
     syncPos |-> syncPos, syncCut |-> syncCut, prepared |-> prepared,
     pending |-> pending, syncQueued |-> syncQueued,
     committed |-> committed, gc |-> globalCommitted]

=============================================================================
