------------------------------ MODULE Trace ------------------------------
(***************************************************************************)
(* Trace validation for the updated reference suite.                        *)
(*                                                                         *)
(* Learner synchronisation events (the update's affected path) drive the   *)
(* real base Actions: LearnerProposal, LearnerCommit, LearnerNewLeader,     *)
(* LearnerStartupWithoutServing, LearnerLogPending, LearnerAckNewLeader,   *)
(* LearnerUpToDate, LearnerLogAfterUpToDate, LearnerCommitAfterUpToDate,   *)
(* EnterBroadcast.  The leader side of a learner's packet stream is either *)
(* a Zab1_0Test fixture or an uninstrumented LearnerHandler, so each       *)
(* consumed packet is supplied by the tightly constrained silent step      *)
(* TraceDeliverPacket (exactly the packet the next event consumes).         *)
(* Election/epoch/pipeline events keep the V0 observer projection.          *)
(***************************************************************************)
EXTENDS base, Json, IOUtils, Sequences, TLC

JsonFile == IF "JSON" \in DOMAIN IOEnv
            THEN IOEnv.JSON
            ELSE "../traces/follower-diff.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x :
         /\ "tag" \in DOMAIN x /\ x.tag = "trace"
         /\ "scenario" \in DOMAIN x
         /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0

VARIABLES l, latestLeader
traceVars == <<l, latestLeader>>
traceAllVars == <<allVars, traceVars>>
logline == TraceLog[l]

EventNames == {
    "ElectionWon", "PeerRoleChanged", "PhaseChanged",
    "AcceptedEpochPersisted", "CurrentEpochPersisted",
    "FollowerRegistered", "SyncModeChanged", "SyncSelected",
    "SnapshotInstalled", "BroadcastReady", "ProposalQueued",
    "TxnAppended", "TxnDurable", "CommitDelivered", "TxnApplied",
    "SyncProposalBuffered", "SyncCommitReceived", "NewLeaderAcked",
    "FollowerException", "DatabaseLoaded"
}

PipelineEvents == {
    "ProposalQueued", "TxnAppended", "TxnDurable",
    "CommitDelivered", "TxnApplied"
}

SyncEvents == {"SyncProposalBuffered", "SyncCommitReceived", "NewLeaderAcked"}

TraceScenario == TraceLog[1].scenario

\* Zab1_0Test-style fixtures run the real learner protocol while the peer's
\* public role stays LOOKING; only these scenarios map LOOKING -> FOLLOWING.
FixtureScenarios == {"follower-snap", "follower-diff",
                     "update-commit-after-newleader",
                     "update-newleader-ack-durability"}

TraceRole(r) ==
    CASE r = "looking" ->
           IF TraceScenario \in FixtureScenarios THEN "following" ELSE "looking"
      [] r = "following" -> "following"
      [] r = "leading" -> "leading"
      [] OTHER -> "looking"

TracePhase(p) ==
    CASE p = "discovery" -> "discovery"
      [] p = "synchronization" -> "sync"
      [] p = "broadcast" -> "broadcast"
      [] p = "election" -> "election"
      [] OTHER -> "offline"

IsKnownPeerState(st) ==
    /\ st.acceptedEpoch \in (-1)..MaxEpoch
    /\ st.currentEpoch \in (-1)..MaxEpoch
    /\ st.role \in {"unknown", "looking", "following", "leading"}
    /\ st.phase \in {"unknown", "election", "discovery",
                       "synchronization", "broadcast", "offline"}
    /\ st.syncMode \in SyncModes

TraceInputOK ==
    /\ \A k \in 1..Len(TraceLog) :
         LET rec == TraceLog[k] IN
         /\ {"tag", "scenario", "seq", "timeMillis", "timeNanos",
               "thread", "event"} \subseteq DOMAIN rec
         /\ rec.tag = "trace"
         /\ rec.scenario = TraceScenario
         /\ rec.seq = k
         /\ {"id", "name"} \subseteq DOMAIN rec.thread
         /\ {"name", "node", "zxid", "txnCounter", "txnEpoch", "state"}
               \subseteq DOMAIN rec.event
         /\ rec.event.name \in EventNames
         /\ rec.event.node \in Server
         /\ rec.event.name /= "FollowerException" => rec.event.txnCounter \in Txn
         /\ rec.event.name /= "FollowerException" => rec.event.txnEpoch \in Epoch
         /\ {"acceptedEpoch", "currentEpoch", "role", "phase", "syncMode"}
               \subseteq DOMAIN rec.event.state
         /\ IsKnownPeerState(rec.event.state)
         \* Update probes must carry the learner buffer fields.
         /\ rec.event.name \in SyncEvents =>
              /\ "sync" \in DOMAIN rec.event
              /\ {"pending", "committed", "toLog"} \subseteq DOMAIN rec.event.sync
         /\ rec.event.name = "FollowerException" => "detail" \in DOMAIN rec.event

ASSUME TraceInputOK

IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name
EventName == logline.event.name
Node == logline.event.node
TxnId == logline.event.txnCounter
TxnEp == logline.event.txnEpoch
TxnEntry == EntryFor(TxnId, TxnEp)
SyncF == logline.event.sync

HasEntry(h, ent) == \E k \in 1..Len(h) : h[k] = ent
\* Post-state data-tree position of s (Node itself must stay unprimed).
DbPosNext(s) == IF zkState'[s] = "running" THEN applied'[s] ELSE recovered'[s]
EnsureEntry(h, ent) == IF HasEntry(h, ent) THEN h ELSE Append(h, ent)
PrefixThrough(h, ent) ==
    IF HasEntry(h, ent)
    THEN SubSeq(h, 1, CHOOSE k \in 1..Len(h) : h[k] = ent)
    ELSE Append(h, ent)

ZxidMatches(h) ==
    IF TxnId = 0
    THEN Len(h) = 0
    ELSE /\ Len(h) > 0
         /\ h[Len(h)] = TxnEntry

(***************************************************************************)
(* Dispatch: which learner events are replayed through base Actions.       *)
(***************************************************************************)
LearnerSession(s) == role[s] = "following" /\ phase[s] = "sync"

DrivesProposal == EventName = "SyncProposalBuffered"
DrivesCommit == EventName = "SyncCommitReceived"
DrivesNewLeader == EventName = "CurrentEpochPersisted" /\ LearnerSession(Node)
                   /\ syncStage[Node] = "loop"
DrivesStartup == EventName = "SyncModeChanged" /\ logline.event.state.syncMode = "NONE"
                 /\ LearnerSession(Node) /\ syncStage[Node] = "nlEpoch"
DrivesLogPending == EventName = "ProposalQueued" /\ syncStage[Node] = "nlStarted"
DrivesAck == EventName = "NewLeaderAcked"
DrivesUpToDate == EventName = "BroadcastReady"
DrivesLogAfter == EventName = "ProposalQueued" /\ syncStage[Node] = "serving"
DrivesCommitAfter == EventName = "CommitDelivered" /\ syncStage[Node] = "serving"
DrivesEnterBroadcast == EventName = "PhaseChanged"
                        /\ logline.event.state.phase = "broadcast"
                        /\ syncStage[Node] = "serving"

BaseDriven ==
    \/ DrivesProposal \/ DrivesCommit \/ DrivesNewLeader \/ DrivesStartup
    \/ DrivesLogPending \/ DrivesAck \/ DrivesUpToDate \/ DrivesLogAfter
    \/ DrivesCommitAfter \/ DrivesEnterBroadcast

\* Packet the next base-driven event consumes from the learner's stream.
NeededPacket ==
    CASE DrivesProposal -> PropPkt(TxnEntry)
      [] DrivesCommit -> CommitPkt(TxnEntry)
      [] DrivesNewLeader -> [type |-> "NEWLEADER", ent |-> Marker(TxnEp)]
      [] DrivesUpToDate -> [type |-> "UPTODATE", ent |-> Marker(acceptedEpoch[Node])]
      [] OTHER -> [type |-> "NONE", ent |-> Marker(0)]

NeedsPacket == DrivesProposal \/ DrivesCommit \/ DrivesNewLeader \/ DrivesUpToDate

\* Silent leader-side delivery (fixture or uninstrumented LearnerHandler):
\* only when the next event consumes a packet and the stream is empty.
TraceDeliverPacket ==
    /\ l <= Len(TraceLog)
    /\ NeedsPacket
    /\ lq[Node] = <<>>
    /\ LearnerSession(Node)
    /\ lq' = [lq EXCEPT ![Node] = <<NeededPacket>>]
    /\ UNCHANGED <<electionVars, histVars, commitVars,
                   syncMode, syncSource, syncJustified, pnc, pcm, toLog,
                   syncStage, hstage, nlAcked, zkState,
                   usedTxn, rollbackAuthorized, syncTarget, epochTarget, syncError>>
    /\ UNCHANGED <<l, latestLeader>>

(***************************************************************************)
(* Base-driven learner steps with update-field validation.                 *)
(***************************************************************************)
BufferFieldsPost ==
    /\ SyncF.pending = Len(pnc'[Node])
    /\ SyncF.committed = Len(pcm'[Node])
    /\ SyncF.toLog = toLog'[Node]

BufferFieldsPre ==
    /\ SyncF.pending = Len(pnc[Node])
    /\ SyncF.committed = Len(pcm[Node])
    /\ SyncF.toLog = toLog[Node]

TraceBaseStep ==
    /\ l <= Len(TraceLog)
    /\ \/ DrivesProposal /\ LearnerProposal(Node) /\ BufferFieldsPost
       \/ DrivesCommit /\ BufferFieldsPre /\ LearnerCommit(Node)
       \/ DrivesNewLeader /\ LearnerNewLeader(Node)
          /\ currentEpoch'[Node] = TxnEp
       \/ DrivesStartup /\ LearnerStartupWithoutServing(Node)
       \/ DrivesLogPending /\ Head(pnc[Node]) = TxnEntry
          /\ LearnerLogPending(Node) /\ HasEntry(queued'[Node], TxnEntry)
       \/ DrivesAck /\ BufferFieldsPre /\ LearnerAckNewLeader(Node)
          /\ BufferFieldsPost
       \/ DrivesUpToDate /\ LearnerUpToDate(Node) /\ ZxidMatches(applied'[Node])
       \/ DrivesLogAfter /\ Head(pnc[Node]) = TxnEntry
          /\ LearnerLogAfterUpToDate(Node) /\ HasEntry(queued'[Node], TxnEntry)
       \/ DrivesCommitAfter /\ LearnerCommitAfterUpToDate(Node)
          /\ ZxidMatches(committed'[Node])
       \/ DrivesEnterBroadcast /\ EnterBroadcast(Node)
    /\ l' = l + 1
    /\ UNCHANGED latestLeader

(***************************************************************************)
(* Observer projection for the remaining events (V0 semantics, adapted:    *)
(* SNAP installs the in-memory tree only; a role exit resets the session    *)
(* and fast-forwards the tree only from a RUNNING server).                 *)
(***************************************************************************)
NextAccepted ==
    IF EventName = "AcceptedEpochPersisted"
    THEN [acceptedEpoch EXCEPT ![Node] = TxnEp]
    ELSE acceptedEpoch

NextCurrent ==
    IF EventName = "CurrentEpochPersisted"
    THEN [currentEpoch EXCEPT ![Node] = TxnEp]
    ELSE currentEpoch

NextRole ==
    IF EventName = "PeerRoleChanged"
       \/ /\ EventName = "PhaseChanged"
          /\ logline.event.state.phase = "election"
    THEN [role EXCEPT ![Node] = TraceRole(logline.event.state.role)]
    ELSE role

NextPhase ==
    IF EventName = "PhaseChanged"
    THEN [phase EXCEPT ![Node] = TracePhase(logline.event.state.phase)]
    ELSE phase

NextSyncMode ==
    IF EventName = "SyncModeChanged"
    THEN [syncMode EXCEPT ![Node] = logline.event.state.syncMode]
    ELSE syncMode

Leading(r) == {s \in Server : r[s] = "leading"}

\* A stale leader can still be LEADING while a newer one is elected; a
\* follower that (re)enters FOLLOWING follows the most recently elected one.
NextLatestLeader(r) ==
    IF r[Node] = "leading" /\ role[Node] /= "leading" THEN Node ELSE latestLeader

ObservedLeaderOf(r) ==
    [s \in Server |->
       IF r[s] = "leading" THEN s
       ELSE IF r[s] = "looking" THEN Nil
       ELSE IF s = Node /\ role[s] /= "following" /\ NextLatestLeader(r) \in Server
            THEN NextLatestLeader(r)
       ELSE IF leaderOf[s] \in Server THEN leaderOf[s]
       ELSE IF Cardinality(Leading(r)) = 1
            THEN CHOOSE x \in Leading(r) : TRUE
            ELSE leaderOf[s]]

ObservedLeadersByEpoch(r, ae) ==
    [e \in Epoch |-> leadersByEpoch[e] \cup
         {s \in Server : /\ s = Node
                          /\ EventName = "AcceptedEpochPersisted"
                          /\ r[s] = "leading"
                          /\ ae[s] = e}]

ObservedSyncSource(r, ph, lof) ==
    [s \in Server |->
       IF s = Node /\ r[s] = "following"
                    /\ (ph[s] = "sync"
                        \/ EventName \in {"SyncModeChanged", "SyncSelected"})
       THEN IF lof[s] \in Server THEN lof[s] ELSE syncSource[s]
       ELSE IF s = Node /\ r[s] \in {"looking", "leading"}
            THEN Nil
            ELSE syncSource[s]]

\* A peer leaving its role (QuorumPeer.run -> LOOKING / election phase).
Exiting(nr, np) == (nr[Node] = "looking" \/ np[Node] = "election")
                   /\ (role[Node] /= nr[Node] \/ phase[Node] /= np[Node])

ObservedSyncJustified(r, ph) ==
    [s \in Server |->
       IF s = Node /\ (r[s] = "looking" \/ ph[s] = "election")
       THEN FALSE
       ELSE syncJustified[s]]

SyncLeader ==
    IF syncSource[Node] \in Server THEN syncSource[Node]
    ELSE IF Cardinality(Leading(role)) = 1
         THEN CHOOSE x \in Leading(role) : TRUE
         ELSE Node

LongestCommitted ==
    CHOOSE h \in {committed[s] : s \in Server} :
        \A s \in Server : Len(committed[s]) <= Len(h)

LongestApplied ==
    CHOOSE h \in {applied[s] : s \in Server} :
        \A s \in Server : Len(applied[s]) <= Len(h)

NextProposed ==
    IF EventName \in PipelineEvents
    THEN [proposed EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
    ELSE proposed

NextQueued ==
    IF EventName \in PipelineEvents
    THEN [queued EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
    ELSE queued

NextAppended ==
    IF EventName \in {"TxnAppended", "TxnDurable"}
    THEN [appended EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
    ELSE appended

NextDurable ==
    IF EventName = "TxnDurable"
    THEN [durable EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
    ELSE durable

\* A follower's own commit is replayed by base Actions; uninstrumented
\* leader-side commits are represented by the minimum implied prefix.
NextCommitted ==
    IF EventName \in {"CommitDelivered", "TxnApplied"} /\ ~HasEntry(committed[Node], TxnEntry)
    THEN [committed EXCEPT ![Node] = PrefixThrough(LongestCommitted, TxnEntry)]
    ELSE committed

NextApplied ==
    IF EventName = "TxnApplied"
    THEN [applied EXCEPT ![Node] =
            IF HasEntry(committed[Node], TxnEntry)
            THEN PrefixThrough(committed[Node], TxnEntry)
            ELSE PrefixThrough(LongestApplied, TxnEntry)]
    ELSE applied

NextCommitCertified ==
    IF EventName \in {"CommitDelivered", "TxnApplied"}
    THEN [commitCertified EXCEPT ![TxnId] = TRUE]
    ELSE commitCertified

NextUsedTxn ==
    IF EventName \in PipelineEvents THEN usedTxn \cup {TxnId} ELSE usedTxn

TraceObservedStep ==
    /\ l <= Len(TraceLog)
    /\ ~BaseDriven
    /\ LET nr == NextRole IN
       LET np == NextPhase IN
       LET na == NextAccepted IN
       LET nc == NextCurrent IN
       LET nl == ObservedLeaderOf(nr) IN
       LET exiting == Exiting(nr, np) \/ EventName = "DatabaseLoaded" IN
       LET leaderUp == nr[Node] = "leading" /\ np[Node] = "broadcast"
                       /\ phase[Node] /= "broadcast" IN
       /\ \A s \in Server : nc[s] <= na[s]
       /\ latestLeader' = NextLatestLeader(nr)
       /\ up' = up
       /\ role' = nr
       /\ phase' = np
       /\ leaderOf' = nl
       /\ acceptedEpoch' = na
       /\ currentEpoch' = nc
       /\ votes' = votes
       /\ leadersByEpoch' = ObservedLeadersByEpoch(nr, na)
       /\ proposed' = NextProposed
       /\ queued' = NextQueued
       /\ appended' = NextAppended
       /\ durable' = NextDurable
       \* Leader.startZkServer: the loaded tree becomes the epoch's committed
       \* and served history (base!LeaderBroadcast).
       /\ committed' = IF leaderUp THEN [committed EXCEPT ![Node] = recovered[Node]]
                       ELSE NextCommitted
       /\ applied' = IF leaderUp THEN [applied EXCEPT ![Node] = recovered[Node]]
                     ELSE NextApplied
       /\ snapshot' = snapshot
       /\ recovered' =
            CASE EventName = "SnapshotInstalled" ->
                   [recovered EXCEPT ![Node] = LeaderTree(SyncLeader)]
              \* QuorumPeer.loadDataBase (start of a QuorumPeer incarnation):
              \* snapshot + forced log (base!Restart).
              [] EventName = "DatabaseLoaded" ->
                   [recovered EXCEPT ![Node] = durable[Node]]
              [] exiting /\ zkState[Node] = "running" ->
                   [recovered EXCEPT ![Node] = durable[Node]]
              [] OTHER -> recovered
       /\ acked' = acked
       /\ commitCertified' =
            IF leaderUp THEN [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(recovered[Node])]
            ELSE NextCommitCertified
       /\ messages' = messages
       /\ syncMode' = NextSyncMode
       /\ syncSource' = ObservedSyncSource(nr, np, nl)
       /\ syncJustified' = ObservedSyncJustified(nr, np)
       /\ usedTxn' = NextUsedTxn
       /\ rollbackAuthorized' =
            [s \in Server |-> s = Node /\ (EventName = "SnapshotInstalled" \/ exiting)]
       \* Learner session bookkeeping
       /\ lq' = IF exiting \/ EventName \in {"SyncSelected", "FollowerException"}
                THEN [lq EXCEPT ![Node] = <<>>] ELSE lq
       /\ pnc' = IF exiting \/ EventName = "SyncSelected"
                 THEN [pnc EXCEPT ![Node] = <<>>] ELSE pnc
       /\ pcm' = IF exiting \/ EventName = "SyncSelected"
                 THEN [pcm EXCEPT ![Node] = <<>>] ELSE pcm
       /\ toLog' = CASE EventName = "SyncSelected" ->
                          [toLog EXCEPT ![Node] = (syncMode[Node] = "DIFF")]
                     [] exiting -> [toLog EXCEPT ![Node] = FALSE]
                     [] OTHER -> toLog
       /\ syncStage' = CASE EventName = "SyncSelected" ->
                             [syncStage EXCEPT ![Node] = "loop"]
                        [] exiting -> [syncStage EXCEPT ![Node] = "none"]
                        [] EventName = "FollowerException" /\ syncStage[Node] /= "none" ->
                             [syncStage EXCEPT ![Node] = "failed"]
                        [] OTHER -> syncStage
       /\ hstage' = hstage
       /\ nlAcked' = IF exiting THEN [nlAcked EXCEPT ![Node] = {}] ELSE nlAcked
       /\ zkState' = CASE exiting -> [zkState EXCEPT ![Node] = "none"]
                       [] leaderUp -> [zkState EXCEPT ![Node] = "running"]
                       [] OTHER -> zkState
       /\ syncTarget' = IF EventName = "SyncSelected"
                        THEN [syncTarget EXCEPT ![Node] = LeaderHist(SyncLeader)]
                        ELSE syncTarget
       /\ epochTarget' = epochTarget
       /\ syncError' = syncError
       /\ l' = l + 1

ValidateCommonPostState ==
    /\ IF logline.event.state.acceptedEpoch >= 0
          THEN acceptedEpoch'[Node] = logline.event.state.acceptedEpoch
          ELSE TRUE
    /\ IF logline.event.state.currentEpoch >= 0
          THEN currentEpoch'[Node] = logline.event.state.currentEpoch
          ELSE TRUE
    /\ IF logline.event.state.role /= "unknown"
          THEN role'[Node] = TraceRole(logline.event.state.role)
          ELSE TRUE
    /\ IF logline.event.state.phase /= "unknown"
          THEN phase'[Node] = TracePhase(logline.event.state.phase)
          ELSE TRUE
    /\ syncMode'[Node] = logline.event.state.syncMode

ValidateEventPostState ==
    \* QuorumPeer.getLastLoggedZxid() reports the in-memory tree (DbPos).
    \* A zero counter is an epoch marker: Leader.startZkServer sets the tree's
    \* lastProcessedZxid to makeZxid(epoch, 0) (or the log is empty).
    CASE EventName \in {"PeerRoleChanged", "PhaseChanged"} ->
           IF TxnId = 0
           THEN TxnEp <= acceptedEpoch'[Node]
           ELSE ZxidMatches(DbPosNext(Node))
      [] EventName = "DatabaseLoaded" ->
           ZxidMatches(recovered'[Node])
      \* FastLeaderElection.setPeerState logs the elected vote's zxid, which is
      \* the winner's last zxid (FastLeaderElection.java:898-901).
      [] EventName = "ElectionWon" ->
           IF TxnId = 0
           THEN TxnEp <= acceptedEpoch'[Node] \/ \E x \in Server : DbPosNext(x) = <<>>
           ELSE \E x \in Server : ZxidMatches(DbPosNext(x)) \/ ZxidMatches(durable'[x])
      [] EventName = "AcceptedEpochPersisted" ->
           acceptedEpoch'[Node] = TxnEp
      [] EventName = "CurrentEpochPersisted" ->
           currentEpoch'[Node] = TxnEp
      [] EventName = "FollowerRegistered" ->
           ZxidMatches(DbPosNext(Node))
      [] EventName = "SyncModeChanged" ->
           ZxidMatches(DbPosNext(Node))
      [] EventName = "SyncSelected" ->
           \* DIFF carries peerLastZxid or the leader's lastCommittedZxid
           \* (LearnerHandler.java:850,977,1032); Zab1_0Test fixtures choose it freely.
           \/ TraceScenario \in FixtureScenarios
           \/ ZxidMatches(LeaderHist(SyncLeader)) \/ ZxidMatches(DbPos(Node))
      [] EventName = "SnapshotInstalled" ->
           ZxidMatches(recovered'[Node])
      [] EventName = "BroadcastReady" ->
           ZxidMatches(applied'[Node])
      [] EventName = "ProposalQueued" ->
           /\ HasEntry(proposed'[Node], TxnEntry)
           /\ HasEntry(queued'[Node], TxnEntry)
      [] EventName = "TxnAppended" -> HasEntry(appended'[Node], TxnEntry)
      [] EventName = "TxnDurable" -> HasEntry(durable'[Node], TxnEntry)
      [] EventName = "CommitDelivered" ->
           /\ ZxidMatches(committed'[Node])
           /\ commitCertified'[TxnId] \/ syncStage[Node] = "serving"
      [] EventName = "TxnApplied" ->
           /\ ZxidMatches(applied'[Node])
           /\ commitCertified'[TxnId]
      [] EventName \in SyncEvents -> TRUE
      [] EventName = "FollowerException" -> TRUE

TraceNext ==
    \/ TraceDeliverPacket
    \/ /\ \/ TraceBaseStep
          \/ TraceObservedStep
       /\ ValidateCommonPostState
       /\ ValidateEventPostState

\* Fixture leaders (Zab1_0Test) are seeded as an established epoch-1 leader
\* s1 with a broadcast follower s2; follower s0 starts in discovery.
\* The fixture leader's committed log is seeded to be consistent with the
\* packets the fixture sends (follower-diff sends zxid 0x100000002 as a diff).
FixtureLeaderHist ==
    CASE TraceScenario = "update-commit-after-newleader" -> <<>>
      [] TraceScenario = "follower-diff" -> <<EntryFor(2, 1)>>
      [] OTHER -> <<EntryFor(1, 1)>>

TraceInit ==
    /\ l = 1
    /\ latestLeader = IF TraceScenario \in FixtureScenarios THEN "s1" ELSE Nil
    /\ up = [s \in Server |-> TRUE]
    /\ lq = [s \in Server |-> <<>>]
    /\ pnc = [s \in Server |-> <<>>]
    /\ pcm = [s \in Server |-> <<>>]
    /\ toLog = [s \in Server |-> FALSE]
    /\ syncStage = [s \in Server |-> "none"]
    /\ nlAcked = [s \in Server |-> {}]
    /\ syncTarget = [s \in Server |-> <<>>]
    /\ epochTarget = [s \in Server |-> <<>>]
    /\ syncError = {}
    /\ IF TraceScenario \in FixtureScenarios
       THEN
         LET leader == "s1" IN
         LET follower == "s0" IN
         LET seed == FixtureLeaderHist IN
         /\ role = [s \in Server |-> IF s = leader THEN "leading" ELSE "following"]
         /\ phase = [s \in Server |->
              IF s = follower THEN "discovery" ELSE "broadcast"]
         /\ leaderOf = [s \in Server |-> leader]
         /\ acceptedEpoch = [s \in Server |-> IF s = follower THEN 0 ELSE 1]
         /\ currentEpoch = [s \in Server |-> IF s = follower THEN 0 ELSE 1]
         /\ votes = [s \in Server |-> IF s = leader THEN Server ELSE {}]
         /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {leader} ELSE {}]
         /\ proposed = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ queued = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ appended = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ durable = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ committed = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ applied = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ snapshot = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ recovered = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
         /\ acked = [t \in Txn |-> IF t \in TxnIds(seed) THEN Server ELSE {}]
         /\ commitCertified = [t \in Txn |-> t \in TxnIds(seed)]
         /\ messages = {}
         /\ syncMode = [s \in Server |-> "NONE"]
         /\ syncSource = [s \in Server |-> IF s = leader THEN Nil ELSE leader]
         /\ syncJustified = [s \in Server |-> s /= follower]
         /\ usedTxn = TxnIds(seed)
         /\ rollbackAuthorized = [s \in Server |-> FALSE]
         /\ hstage = [s \in Server |-> IF s = leader THEN "none" ELSE "utd"]
         /\ zkState = [s \in Server |-> IF s = follower THEN "none" ELSE "running"]
       ELSE
         /\ role = [s \in Server |-> "looking"]
         /\ phase = [s \in Server |-> "election"]
         /\ leaderOf = [s \in Server |-> Nil]
         /\ acceptedEpoch = [s \in Server |-> 0]
         /\ currentEpoch = [s \in Server |-> 0]
         /\ votes = [s \in Server |-> {}]
         /\ leadersByEpoch = [e \in Epoch |-> {}]
         /\ proposed = [s \in Server |-> <<>>]
         /\ queued = [s \in Server |-> <<>>]
         /\ appended = [s \in Server |-> <<>>]
         /\ durable = [s \in Server |-> <<>>]
         /\ committed = [s \in Server |-> <<>>]
         /\ applied = [s \in Server |-> <<>>]
         /\ snapshot = [s \in Server |-> <<>>]
         /\ recovered = [s \in Server |-> <<>>]
         /\ acked = [t \in Txn |-> {}]
         /\ commitCertified = [t \in Txn |-> FALSE]
         /\ messages = {}
         /\ syncMode = [s \in Server |-> "NONE"]
         /\ syncSource = [s \in Server |-> Nil]
         /\ syncJustified = [s \in Server |-> FALSE]
         /\ usedTxn = {}
         /\ rollbackAuthorized = [s \in Server |-> FALSE]
         /\ hstage = [s \in Server |-> "none"]
         /\ zkState = [s \in Server |-> "none"]

TraceSpec == TraceInit /\ [][TraceNext]_traceAllVars
                         /\ WF_traceAllVars(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

\* Trace projection of OneActiveLeaderPerEpoch: the implementation sets the
\* LEADING role before Leader.lead proposes the new epoch, so a leader is
\* attributed to an epoch once it reaches synchronization (epoch persisted).
TraceOneActiveLeaderPerEpoch ==
    \A e \in Epoch :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ phase[s] \in {"sync", "broadcast"}
                                    /\ acceptedEpoch[s] = e}) <= 1

\* Update-path observation: learners whose sync stream raised an exception.
TraceSyncErrors == syncError

TraceView == <<l, acceptedEpoch, currentEpoch, role, phase, syncMode,
               proposed, queued, appended, durable, committed, applied,
               recovered, lq, pnc, pcm, syncStage, zkState, syncError>>

=============================================================================
