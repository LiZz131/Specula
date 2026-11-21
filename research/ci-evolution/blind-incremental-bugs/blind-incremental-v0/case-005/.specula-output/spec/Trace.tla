------------------------------ MODULE Trace ------------------------------
(***************************************************************************)
(* Category-A linear replay of real SpeculaTrace events. Every consuming    *)
(* wrapper invokes a base action (or Observe for source-level send markers) *)
(* and checks the captured post-event fields that have defined semantics.   *)
(***************************************************************************)
EXTENDS base, Json, IOUtils, Sequences, TLC

JsonFile == IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
            ELSE "../traces/startup-mutation-restart-v2.tlc.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x :
         /\ "tag" \in DOMAIN x /\ x.tag = "trace"
         /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0

(* modelZxid is a deterministic projection added by normalize-trace.jq while
   the native 64-bit zxid remains in every event for provenance. *)
EventZX(eventRecord) ==
    IF "modelZxid" \in DOMAIN eventRecord.state
    THEN eventRecord.state.modelZxid
    ELSE eventRecord.state.zxid

TxnEventNames == {"Proposal", "ProposalReceived", "SyncProposalReceived",
                   "SyncCommitApplied", "LogAppend", "LogDurable", "AckSent",
                   "AckReceived", "Commit", "Apply"}

TraceTxn == TLCEval(UNION {
    IF TraceLog[k].event.name \in TxnEventNames
       /\ EventZX(TraceLog[k].event) # 0
    THEN {EventZX(TraceLog[k].event)} ELSE {}
    : k \in 1..Len(TraceLog)})

TraceServer == TLCEval(UNION {
    {TraceLog[k].event.nid} \cup
    (IF TraceLog[k].event.peer = "" THEN {} ELSE {TraceLog[k].event.peer})
    : k \in 1..Len(TraceLog)})

ASSUME TraceServer = Server
ASSUME TraceTxn = Txn

VARIABLE l
traceVars == <<vars, l>>

logline == TraceLog[l]
Name == logline.event.name
Node == logline.event.nid
Peer == logline.event.peer
RawZX == logline.event.state.zxid
ZX == EventZX(logline.event)
TraceZxidEpoch(z) == IF z = NoTxn THEN 0 ELSE z \div 100
Epoch == logline.event.state.epoch
Accepted == logline.event.state.acceptedEpoch
ImplRole == logline.event.state.role
ImplMode == logline.event.state.mode

RoleMapping ==
    "DOWN" :> "DOWN" @@ "LOOKING" :> "LOOKING" @@
    "FOLLOWING" :> "FOLLOWING" @@ "follower" :> "FOLLOWING" @@
    "OBSERVING" :> "OBSERVING" @@ "observer" :> "OBSERVING" @@
    "LEADING" :> "LEADING" @@ "leader" :> "LEADING"

(* All retained event fields are consumed.  The native zxid is type-checked
   here and retained byte-for-byte; its semantic epoch/counter value is checked
   through the deterministic modelZxid projection because TLC's NDJSON number
   path cannot preserve every native 64-bit zxid.  Each wrapper below then
   applies event-specific post-state checks. *)
ValidateEnvelope ==
    /\ logline.ts \in Int
    /\ Node \in Server
    /\ Peer \in Server \cup {""}
    /\ RawZX \in Int /\ ZX \in Int
    /\ Epoch \in Int /\ Accepted \in Int
    /\ ImplRole \in DOMAIN RoleMapping
    /\ ImplMode \in Modes

IsEvent(n) == /\ l <= Len(TraceLog) /\ Name = n /\ ValidateEnvelope
StepTrace == l' = l + 1

ValidateRole(i) == role'[i] = RoleMapping[ImplRole]
ValidateAccepted(i) == Accepted < 0 \/ acceptedEpoch'[i] = Accepted
ValidateCurrent(i) == Epoch < 0 \/ currentEpoch'[i] = Epoch
ValidateOrdinaryMode == ImplMode = "NONE"
ValidateSyncMode(i) == syncMode'[i] = ImplMode
ValidateTxnQueued(i) == ZX \in queuedLog'[i]
ValidateTxnVolatile(i) == ZX \in volatileLog'[i]
ValidateTxnDurable(i) == ZX \in durableLog'[i] \cup snapshotLog'[i]

TraceStart ==
    /\ IsEvent("ServerStart")
    /\ StartServer(Node)
    /\ ValidateRole(Node) /\ ValidateCurrent(Node) /\ ValidateAccepted(Node)
    /\ MaxOrZero(durableLog'[Node] \cup snapshotLog'[Node]) = ZX
    /\ ValidateOrdinaryMode /\ StepTrace

TraceElection ==
    /\ IsEvent("ElectionDecision")
    /\ ElectionDecision(Node, Peer, Epoch, RoleMapping[ImplRole])
    /\ ValidateRole(Node) /\ Epoch >= currentEpoch'[Node] /\ ValidateAccepted(Node)
    /\ ZX \in Txn \cup {NoTxn} /\ ValidateOrdinaryMode /\ StepTrace

TraceEpochSupport ==
    /\ IsEvent("EpochSupportReceived")
    /\ IF Node \in broadcastReady
       THEN /\ up[Node] /\ role[Node] = "LEADING"
            /\ Observe("EpochSupportExistingEpoch")
       ELSE ReceiveEpochSupport(Node, Peer)
    /\ (Node \in broadcastReady \/ Peer \in epochSupport'[Node])
    /\ ValidateRole(Node) /\ Accepted <= acceptedEpoch'[Node]
    /\ (Epoch < 0 \/ /\ Epoch >= acceptedEpoch'[Node]
                     /\ Epoch <= acceptedEpoch'[Node] + 1)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceAcceptedMemory ==
    /\ IsEvent("AcceptedEpochMemory")
    /\ IF ImplRole = "LEADING"
       THEN LeaderAcceptedEpochMemory(Node, Accepted)
       ELSE LearnerAcceptedEpochMemory(Node, Accepted)
    /\ acceptedEpoch'[Node] = Accepted /\ currentEpoch'[Node] = Epoch
    /\ ValidateRole(Node) /\ ValidateOrdinaryMode /\ StepTrace

TraceAcceptedPersist ==
    /\ IsEvent("AcceptedEpochPersist")
    /\ PersistAcceptedEpoch(Node)
    /\ durableAccepted'[Node] = Accepted /\ currentEpoch'[Node] = Epoch
    /\ ValidateRole(Node) /\ ValidateOrdinaryMode /\ StepTrace

TraceLeaderInfo ==
    /\ IsEvent("LeaderInfoSent")
    /\ up[Node] /\ up[Peer] /\ role[Node] = "LEADING"
    /\ acceptedEpoch[Node] = Accepted
    /\ (TraceZxidEpoch(ZX) = Accepted \/ (ZX = NoTxn /\ Epoch = Accepted))
    /\ Observe("LeaderInfoSent")
    /\ ValidateRole(Node) /\ ValidateAccepted(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceAckEpochSent ==
    /\ IsEvent("AckEpochSent")
    /\ up[Node] /\ up[Peer] /\ leaderOf[Node] = Peer
    /\ durableAccepted[Node] = Accepted /\ Epoch = Accepted
    /\ Observe("AckEpochSent")
    /\ ValidateRole(Node) /\ ValidateAccepted(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceEpochAck ==
    /\ IsEvent("EpochAckAccepted")
    /\ RecordEpochAck(Node, Peer)
    /\ Peer \in epochAcks'[Node]
    /\ ValidateRole(Node) /\ ValidateAccepted(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceCurrentMemory ==
    /\ IsEvent("CurrentEpochMemory")
    /\ CurrentEpochMemory(Node, Epoch)
    /\ currentEpoch'[Node] = Epoch /\ acceptedEpoch'[Node] = Accepted
    /\ ValidateRole(Node) /\ ValidateOrdinaryMode /\ StepTrace

TraceCurrentPersist ==
    /\ IsEvent("CurrentEpochPersist")
    /\ PersistCurrentEpoch(Node)
    /\ durableCurrent'[Node] = Epoch /\ acceptedEpoch'[Node] = Accepted
    /\ ValidateRole(Node) /\ ValidateOrdinaryMode /\ StepTrace

TraceSyncSelected ==
    /\ IsEvent("SyncModeSelected")
    /\ SelectSync(Node, Peer, ImplMode, ZX)
    /\ syncTarget'[Peer] = ZX /\ ValidateSyncMode(Peer)
    /\ ValidateRole(Node) /\ ValidateAccepted(Node)
    /\ currentEpoch'[Node] = Epoch /\ StepTrace

TraceNewLeaderSent ==
    /\ IsEvent("NewLeaderSent")
    /\ up[Node] /\ up[Peer] /\ role[Node] = "LEADING"
    /\ (TraceZxidEpoch(ZX) = Epoch \/ (ZX = NoTxn /\ Epoch = Accepted))
    /\ acceptedEpoch[Node] = Accepted
    /\ Observe("NewLeaderSent")
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceSyncApplied ==
    /\ IsEvent("SyncModeApplied")
    /\ ApplySync(Node, Peer, ImplMode, ZX)
    /\ ValidateSyncMode(Node) /\ syncTarget'[Node] = ZX
    /\ ValidateRole(Node) /\ acceptedEpoch'[Node] = Accepted
    /\ Epoch = Accepted /\ StepTrace

TraceSyncProposal ==
    /\ IsEvent("SyncProposalReceived")
    /\ ReceiveSyncProposal(Node, Peer, ZX)
    /\ ValidateTxnQueued(Node) /\ ValidateTxnVolatile(Node)
    /\ ValidateRole(Node) /\ ValidateAccepted(Node)
    /\ Epoch = acceptedEpoch'[Node] /\ ValidateOrdinaryMode /\ StepTrace

TraceSyncCommit ==
    /\ IsEvent("SyncCommitApplied")
    /\ ApplySyncCommit(Node, Peer, ZX)
    /\ ZX \in committedLog'[Node] /\ ZX \in appliedLog'[Node]
    /\ ValidateRole(Node) /\ ValidateAccepted(Node)
    /\ Epoch = acceptedEpoch'[Node] /\ ValidateOrdinaryMode /\ StepTrace

TraceBootstrapSnapshot ==
    /\ IsEvent("BootstrapSnapshot")
    /\ BootstrapSnapshot(Node, ZX)
    /\ snapshotZxid'[Node] = ZX /\ snapshotLog'[Node] = appliedLog'[Node]
    /\ ValidateRole(Node) /\ acceptedEpoch'[Node] = Accepted
    /\ Epoch = Accepted /\ ValidateOrdinaryMode /\ StepTrace

TraceNewLeaderAck ==
    /\ IsEvent("NewLeaderAckReceived")
    /\ RecordNewLeaderAck(Node, Peer)
    /\ Peer \in newLeaderAcks'[Node]
    /\ (TraceZxidEpoch(ZX) = Epoch \/ (ZX = NoTxn /\ Epoch = Accepted))
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceLeaderReady ==
    /\ IsEvent("LeaderBroadcastReady")
    /\ LeaderReady(Node)
    /\ Node \in broadcastReady'
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ (TraceZxidEpoch(ZX) = Epoch \/ (ZX = NoTxn /\ Epoch = Accepted))
    /\ ValidateOrdinaryMode /\ StepTrace

TraceUpToDate ==
    /\ IsEvent("UpToDateSent")
    /\ SendUpToDate(Node, Peer)
    /\ <<Node, Peer>> \in upToDate'
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceFollowerReady ==
    /\ IsEvent("FollowerBroadcastReady")
    /\ FollowerReady(Node, Peer)
    /\ Node \in broadcastReady'
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ MaxOrZero(appliedLog'[Node]) = ZX
    /\ ValidateOrdinaryMode /\ StepTrace

TraceProposal ==
    /\ IsEvent("Proposal")
    /\ Propose(Node, ZX)
    /\ proposedBy'[ZX] = Node /\ ValidateTxnQueued(Node)
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceProposalReceived ==
    /\ IsEvent("ProposalReceived")
    /\ IF ZX \notin queuedLog[Node]
       THEN ReceiveProposal(Node, Peer, ZX)
       ELSE /\ proposedBy[ZX] = Peer
            /\ up[Node]
            /\ Observe("ProposalReceivedAfterEnqueue")
    /\ proposedBy'[ZX] = Peer /\ ValidateTxnQueued(Node)
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceAppend ==
    /\ IsEvent("LogAppend")
    /\ AppendLog(Node, ZX)
    /\ ValidateTxnVolatile(Node) /\ ValidateRole(Node)
    /\ Epoch = -1 /\ Accepted = -1 /\ ValidateOrdinaryMode /\ StepTrace

TraceDurable ==
    /\ IsEvent("LogDurable")
    /\ ForceLog(Node, ZX)
    /\ ValidateTxnDurable(Node) /\ ValidateRole(Node)
    /\ Epoch = -1 /\ Accepted = -1 /\ ValidateOrdinaryMode /\ StepTrace

TraceAckSent ==
    /\ IsEvent("AckSent")
    /\ up[Node] /\ up[Peer] /\ ZX \in StableAt(Node)
    /\ Observe("AckSent")
    /\ ValidateTxnDurable(Node) /\ ValidateRole(Node)
    /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceAckReceived ==
    /\ IsEvent("AckReceived")
    /\ ReceiveAck(Node, Peer, ZX)
    /\ Peer \in ackers'[ZX]
    /\ ValidateRole(Node) /\ ValidateAccepted(Node) /\ ValidateCurrent(Node)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceCommit ==
    /\ IsEvent("Commit")
    /\ IF ImplRole = "LEADING"
       THEN CommitAtLeader(Node, ZX)
       ELSE ReceiveCommit(Node, Peer, ZX)
    /\ ZX \in committedLog'[Node] /\ ZX \in globalCommitted'
    /\ ValidateRole(Node) /\ ValidateAccepted(Node)
    /\ (Epoch < 0 \/ currentEpoch'[Node] = Epoch)
    /\ ValidateOrdinaryMode /\ StepTrace

TraceApply ==
    /\ IsEvent("Apply")
    /\ ApplyTxn(Node, ZX)
    /\ ZX \in appliedLog'[Node] /\ ValidateRole(Node)
    /\ Epoch = -1 /\ Accepted = -1 /\ ValidateOrdinaryMode /\ StepTrace

TraceCrash ==
    /\ IsEvent("ServerCrash")
    /\ Crash(Node)
    /\ ~up'[Node] /\ ValidateRole(Node)
    /\ currentEpoch'[Node] = Epoch /\ acceptedEpoch'[Node] = Accepted
    /\ MaxOrZero(durableLog'[Node] \cup snapshotLog'[Node]) = ZX
    /\ ValidateOrdinaryMode /\ StepTrace

(* Diagnostic-only action used by Trace-debug.cfg; never selected by Trace.cfg. *)
TraceCrashCore == /\ IsEvent("ServerCrash") /\ Crash(Node) /\ StepTrace

(* In the first retained run the ProposalReceived marker was emitted after
   FollowerZooKeeperServer.logRequest returned.  The request can be appended
   by SyncRequestProcessor before that caller-side marker obtains the trace
   writer.  Represent the already-occurred enqueue as one tightly gated silent
   step; the later marker is still consumed and validates its state fields.
   Exact-old evidence: Follower.java processPacket(PROPOSAL) and
   FollowerZooKeeperServer.logRequest -> SyncRequestProcessor.processRequest. *)
SilentReceiveProposalBeforeAppend ==
    /\ IsEvent("LogAppend")
    /\ Node \in Server /\ ZX \in Txn
    /\ up[Node] /\ role[Node] \in {"FOLLOWING", "OBSERVING"}
    /\ proposedBy[ZX] \in Server
    /\ ZX \notin queuedLog[Node]
    /\ ReceiveProposal(Node, proposedBy[ZX], ZX)
    /\ UNCHANGED l

TraceInit == /\ Init /\ l = 1

TraceNext ==
    \/ TraceStart \/ TraceElection \/ TraceEpochSupport
    \/ TraceAcceptedMemory \/ TraceAcceptedPersist \/ TraceLeaderInfo
    \/ TraceAckEpochSent \/ TraceEpochAck \/ TraceCurrentMemory
    \/ TraceCurrentPersist \/ TraceSyncSelected \/ TraceNewLeaderSent
    \/ TraceSyncApplied \/ TraceSyncProposal \/ TraceSyncCommit
    \/ TraceBootstrapSnapshot \/ TraceNewLeaderAck \/ TraceLeaderReady
    \/ TraceUpToDate \/ TraceFollowerReady \/ TraceProposal
    \/ TraceProposalReceived \/ TraceAppend \/ TraceDurable
    \/ TraceAckSent \/ TraceAckReceived \/ TraceCommit \/ TraceApply
    \/ TraceCrash
    \/ SilentReceiveProposalBeforeAppend
    \/ /\ l > Len(TraceLog) /\ UNCHANGED traceVars

TraceSpec == TraceInit /\ [][TraceNext]_traceVars /\ WF_traceVars(TraceNext)
DebugTraceNext == TraceNext \/ TraceCrashCore
DebugTraceSpec == TraceInit /\ [][DebugTraceNext]_traceVars
                  /\ WF_traceVars(DebugTraceNext)
TraceMatched == <>(l > Len(TraceLog))
TraceView == <<l, lastAction>>

=============================================================================
