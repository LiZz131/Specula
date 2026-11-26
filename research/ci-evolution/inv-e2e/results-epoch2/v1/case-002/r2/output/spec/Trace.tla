------------------------------ MODULE Trace ------------------------------
EXTENDS base, Json, IOUtils, Sequences, TLC

\* A caller selects one retained NDJSON trace by setting the JSON environment
\* value.  No scenario predicate is applied: every tag="trace" record in the
\* selected file is part of the replay obligation.
JsonFile == IF "JSON" \in DOMAIN IOEnv
            THEN IOEnv.JSON
            ELSE "../traces/follower-snap.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x :
         /\ "tag" \in DOMAIN x /\ x.tag = "trace"
         /\ "scenario" \in DOMAIN x
         /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0

VARIABLE l
traceVars == <<l>>
traceAllVars == <<allVars, traceVars>>
logline == TraceLog[l]

EventNames == {
    "ElectionWon", "PeerRoleChanged", "PhaseChanged",
    "AcceptedEpochPersisted", "CurrentEpochPersisted",
    "FollowerRegistered", "SyncModeChanged", "SyncSelected",
    "SnapshotInstalled", "BroadcastReady", "ProposalQueued",
    "TxnAppended", "TxnDurable", "CommitDelivered", "TxnApplied",
    \* UPDATE-MAP (incremental round U): learner NEWLEADER window probes
    \* code: Learner.java:641 (PROPOSAL buffered), Learner.java:760 (NEWLEADER ACK)
    \* update: Update!AffectedActions (MCLearnerNewLeader, MCLearnerAckNewLeader)
    "SyncProposalBuffered", "SyncProposalApplied", "NewLeaderAckSent"
}

PipelineEvents == {
    "ProposalQueued", "TxnAppended", "TxnDurable",
    "CommitDelivered", "TxnApplied"
}

TraceScenario == TraceLog[1].scenario

\* Zab1_0Test's ConversableFollower runs the real learner protocol while its
\* fixture peer remains publicly LOOKING.  That documented fixture projection
\* applies only to the two follower harness scenarios; other traces preserve
\* LOOKING exactly.
TraceRole(r) ==
    CASE r = "looking" ->
           IF TraceScenario \in {"follower-snap", "follower-diff"}
           THEN "following" ELSE "looking"
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
         /\ rec.event.txnCounter \in Txn
         /\ rec.event.txnEpoch \in Epoch
         /\ {"acceptedEpoch", "currentEpoch", "role", "phase", "syncMode"}
               \subseteq DOMAIN rec.event.state
         /\ IsKnownPeerState(rec.event.state)

ASSUME TraceInputOK

IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name
EventName == logline.event.name
Node == logline.event.node
TxnId == logline.event.txnCounter
TxnEp == logline.event.txnEpoch
TxnEntry == EntryFor(TxnId, TxnEp)

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

ObservedLeaderOf(r) ==
    [s \in Server |->
       IF r[s] = "leading" THEN s
       ELSE IF r[s] = "looking" THEN Nil
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

ObservedSyncJustified(r, ph) ==
    [s \in Server |->
       IF s = Node /\ EventName = "BroadcastReady"
       THEN TRUE
       ELSE IF s = Node /\ (r[s] = "looking" \/ ph[s] = "election")
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
    CASE EventName \in PipelineEvents ->
           [proposed EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
      [] EventName = "SnapshotInstalled" ->
           [proposed EXCEPT ![Node] = proposed[SyncLeader]]
      [] OTHER -> proposed

NextQueued ==
    CASE EventName \in PipelineEvents ->
           [queued EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
      [] EventName = "SnapshotInstalled" ->
           [queued EXCEPT ![Node] = queued[SyncLeader]]
      [] OTHER -> queued

NextAppended ==
    CASE EventName \in {"TxnAppended", "TxnDurable"} ->
           [appended EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
      [] EventName = "SnapshotInstalled" ->
           [appended EXCEPT ![Node] = appended[SyncLeader]]
      [] OTHER -> appended

NextDurable ==
    CASE EventName = "TxnDurable" ->
           [durable EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
      [] EventName = "SnapshotInstalled" ->
           [durable EXCEPT ![Node] = durable[SyncLeader]]
      [] OTHER -> durable

NextCommitted ==
    CASE EventName \in {"CommitDelivered", "TxnApplied"} ->
           [committed EXCEPT ![Node] = PrefixThrough(LongestCommitted, TxnEntry)]
      [] EventName = "SnapshotInstalled" ->
           [committed EXCEPT ![Node] = committed[SyncLeader]]
      [] OTHER -> committed

NextApplied ==
    CASE EventName = "TxnApplied" ->
           [applied EXCEPT ![Node] = PrefixThrough(LongestApplied, TxnEntry)]
      [] EventName = "SnapshotInstalled" ->
           [applied EXCEPT ![Node] = applied[SyncLeader]]
      [] OTHER -> applied

NextSnapshot ==
    IF EventName = "SnapshotInstalled"
    THEN [snapshot EXCEPT ![Node] = applied[SyncLeader]]
    ELSE snapshot

NextRecovered ==
    IF EventName = "SnapshotInstalled"
    THEN [recovered EXCEPT ![Node] = durable[SyncLeader]]
    ELSE recovered

NextCommitCertified ==
    IF EventName \in {"CommitDelivered", "TxnApplied"}
    THEN [commitCertified EXCEPT ![TxnId] = TRUE]
    ELSE commitCertified

\* packetsNotCommitted projection: a PROPOSAL buffered during synchronization is
\* pending until FollowerZooKeeperServer.logRequest hands it to the log pipeline
\* (ProposalQueued).  Leaving the learner role discards the local buffer.
NextSyncPending(r, ph) ==
    CASE EventName = "SyncProposalBuffered" ->
           [syncPending EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
      [] EventName = "SyncProposalApplied" /\ syncPending[Node] /= <<>>
                                          /\ Head(syncPending[Node]) = TxnEntry ->
           [syncPending EXCEPT ![Node] = Tail(@)]
      [] EventName = "ProposalQueued" /\ syncPending[Node] /= <<>>
                                     /\ Head(syncPending[Node]) = TxnEntry ->
           [syncPending EXCEPT ![Node] = Tail(@)]
      [] r[Node] /= "following" /\ (r[Node] = "leading" \/ ph[Node] = "election") ->
           [syncPending EXCEPT ![Node] = <<>>]
      [] OTHER -> syncPending

NextLearnerStage(r, ph) ==
    CASE EventName = "SyncSelected" -> [learnerStage EXCEPT ![Node] = "selected"]
      [] EventName = "CurrentEpochPersisted" /\ ph[Node] = "sync"
                                            /\ r[Node] = "following" ->
           [learnerStage EXCEPT ![Node] = "newleader"]
      [] EventName = "NewLeaderAckSent" -> [learnerStage EXCEPT ![Node] = "acked"]
      [] EventName = "BroadcastReady" -> [learnerStage EXCEPT ![Node] = "uptodate"]
      [] r[Node] = "leading" \/ ph[Node] = "election" ->
           [learnerStage EXCEPT ![Node] = "idle"]
      [] OTHER -> learnerStage

NextUsedTxn ==
    IF EventName \in PipelineEvents THEN usedTxn \cup {TxnId} ELSE usedTxn

\* Source-backed abstraction step for the serialized probes.  Public peer
\* fields are post-state observations.  Pipeline callbacks advance only the
\* corresponding prefix; missing leader-side proposal/commit probes are
\* represented by the minimum implied prefix needed by the observed callback.
\* SnapshotInstalled is the explicit history-replacement boundary.
TraceObservedStep ==
    /\ l <= Len(TraceLog)
    /\ LET nr == NextRole IN
       LET np == NextPhase IN
       LET na == NextAccepted IN
       LET nc == NextCurrent IN
       LET nl == ObservedLeaderOf(nr) IN
       /\ Cardinality(Leading(nr)) <= 1
       /\ \A s \in Server : nc[s] <= na[s]
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
       /\ committed' = NextCommitted
       /\ applied' = NextApplied
       /\ snapshot' = NextSnapshot
       /\ recovered' = NextRecovered
       /\ acked' = acked
       /\ commitCertified' = NextCommitCertified
       /\ messages' = messages
       /\ syncMode' = NextSyncMode
       /\ syncSource' = ObservedSyncSource(nr, np, nl)
       /\ syncJustified' = ObservedSyncJustified(nr, np)
       /\ usedTxn' = NextUsedTxn
       /\ rollbackAuthorized' =
            [s \in Server |-> EventName = "SnapshotInstalled" /\ s = Node]
       /\ syncPending' = NextSyncPending(nr, np)
       /\ learnerStage' = NextLearnerStage(nr, np)
       /\ nlAcks' = nlAcks
       /\ everCommitted' = everCommitted
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

\* Round U repair: PeerRoleChanged/ElectionWon/PhaseChanged/FollowerRegistered/
\* SyncModeChanged carry QuorumPeer.getLastLoggedZxid(), which returns the data
\* tree's lastProcessedZxid (QuorumPeer.java:1257-1261), i.e. the in-memory tree
\* position, not the durable log tail.  The tree position is the last entry of the
\* applied, commit-delivered (CommitProcessor may update the tree before its
\* TxnApplied probe), replayed/installed, or durable history of that node.
TreeZxidMatches(n) ==
    \E h \in {applied'[n], committed'[n], recovered'[n], durable'[n]} :
        Len(h) > 0 /\ h[Len(h)] = TxnEntry

ValidateEventPostState ==
    CASE EventName \in {"PeerRoleChanged", "PhaseChanged"} ->
           IF TxnId = 0
           THEN TxnEp <= acceptedEpoch'[Node]
           ELSE TreeZxidMatches(Node)
      \* FastLeaderElection.setPeerState emits the winning vote's proposedZxid,
      \* i.e. the elected leader's tree position (Round U repair).
      [] EventName = "ElectionWon" ->
           IF TxnId = 0
           THEN TxnEp <= MaxEpoch
           ELSE \E n \in Server : TreeZxidMatches(n)
      [] EventName = "AcceptedEpochPersisted" ->
           acceptedEpoch'[Node] = TxnEp
      [] EventName = "CurrentEpochPersisted" ->
           currentEpoch'[Node] = TxnEp
      [] EventName = "FollowerRegistered" ->
           TxnId = 0 \/ TreeZxidMatches(Node)
      [] EventName = "SyncModeChanged" ->
           TxnId = 0 \/ TreeZxidMatches(Node)
      [] EventName = "SyncSelected" ->
           ZxidMatches(durable'[SyncLeader])
      [] EventName = "SnapshotInstalled" ->
           /\ ZxidMatches(snapshot'[Node])
           /\ ZxidMatches(durable'[Node])
      \* getDataTreeLastProcessedZxid(): the tree replayed from snapshot+log on
      \* restart (FileTxnSnapLog.restore) or installed by sync (Round U repair).
      [] EventName = "BroadcastReady" ->
           TxnId = 0 \/ TreeZxidMatches(Node)
      [] EventName = "ProposalQueued" ->
           /\ ZxidMatches(proposed'[Node])
           /\ ZxidMatches(queued'[Node])
      [] EventName = "TxnAppended" -> ZxidMatches(appended'[Node])
      [] EventName = "TxnDurable" -> ZxidMatches(durable'[Node])
      [] EventName = "CommitDelivered" ->
           /\ ZxidMatches(committed'[Node])
           /\ commitCertified'[TxnId]
      [] EventName = "TxnApplied" ->
           /\ ZxidMatches(applied'[Node])
           /\ commitCertified'[TxnId]
      [] EventName = "SyncProposalBuffered" ->
           /\ phase'[Node] = "sync"
           /\ learnerStage[Node] = "selected" \/ learnerStage[Node] = "newleader"
                \/ learnerStage[Node] = "acked"
           /\ ZxidMatches(syncPending'[Node])
      \* SNAP/TRUNC (writeToTxnLog=false): a committed buffered PROPOSAL is applied
      \* to the in-memory tree and removed from packetsNotCommitted (Learner.java:656-665).
      [] EventName = "SyncProposalApplied" ->
           /\ phase'[Node] = "sync"
           /\ learnerStage[Node] = "selected"
           /\ syncMode[Node] \in {"SNAP", "TRUNC"}
           /\ syncPending[Node] /= <<>> /\ Head(syncPending[Node]) = TxnEntry
      \* UPDATE-MAP code: Learner.java:744-760 update: Update!AckedHistoryHandedOff
      \* The ACK carries newLeaderZxid (epoch, 0) after currentEpoch persisted.
      \* Update semantics: every PROPOSAL buffered before NEWLEADER was already
      \* handed to logRequest (ProposalQueued) and the sync mode was cleared.
      [] EventName = "NewLeaderAckSent" ->
           /\ TxnId = 0
           /\ currentEpoch'[Node] = TxnEp
           /\ learnerStage[Node] = "newleader"
           /\ IF NewLeaderLogsPending
              THEN /\ syncPending[Node] = <<>>
                   /\ syncMode'[Node] = "NONE"
              ELSE TRUE

TraceNext ==
    /\ TraceObservedStep
    /\ ValidateCommonPostState
    /\ ValidateEventPostState

TraceInit ==
    /\ l = 1
    /\ up = [s \in Server |-> TRUE]
    /\ IF TraceScenario \in {"follower-snap", "follower-diff"}
       THEN
         LET leader == "s1" IN
         LET follower == "s0" IN
         LET seed == <<EntryFor(1, 1)>> IN
         /\ role = [s \in Server |-> IF s = leader THEN "leading" ELSE "following"]
         /\ phase = [s \in Server |->
              IF s = follower THEN "discovery"
              ELSE IF s = leader THEN "sync" ELSE "broadcast"]
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
         /\ acked = [t \in Txn |-> IF t = 1 THEN Server ELSE {}]
         /\ commitCertified = [t \in Txn |-> t = 1]
         /\ messages = {}
         /\ syncMode = [s \in Server |-> "NONE"]
         /\ syncSource = [s \in Server |-> IF s = follower THEN leader ELSE Nil]
         /\ syncJustified = [s \in Server |-> s /= follower]
         /\ usedTxn = {1}
         /\ rollbackAuthorized = [s \in Server |-> FALSE]
         /\ syncPending = [s \in Server |-> <<>>]
         /\ learnerStage = [s \in Server |-> "idle"]
         /\ nlAcks = [s \in Server |-> {}]
         /\ everCommitted = {}
       ELSE
         /\ Init

TraceSpec == TraceInit /\ [][TraceNext]_traceAllVars
                         /\ WF_traceAllVars(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

TraceView == <<l, acceptedEpoch, currentEpoch, role, phase, syncMode,
               proposed, appended, durable, committed, applied,
               syncPending, learnerStage>>

=============================================================================
