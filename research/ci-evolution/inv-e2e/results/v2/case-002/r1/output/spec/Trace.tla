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
\* Trace-local: the follower's current synchronization is a SNAP session (its
\* synced history is a snapshot file, not txn-log records).
VARIABLE snapSession
\* Trace-local: the most recent server observed entering LEADING (several
\* servers can be LEADING at once in different, not yet established epochs).
VARIABLE lastLeader
traceVars == <<l, snapSession, lastLeader>>
traceAllVars == <<allVars, traceVars>>
logline == TraceLog[l]

EventNames == {
    "ElectionWon", "PeerRoleChanged", "PhaseChanged",
    "AcceptedEpochPersisted", "CurrentEpochPersisted",
    "FollowerRegistered", "SyncModeChanged", "SyncSelected",
    "SnapshotInstalled", "BroadcastReady", "ProposalQueued",
    "TxnAppended", "TxnDurable", "CommitDelivered", "TxnApplied",
    \* UPDATE-MAP: update-focused probes (instrumentation-spec.md section 2b)
    "SyncProposalReceived", "SyncCommitReceived", "NewLeaderAckSent",
    "NewLeaderAckWritten", "NewLeaderAckCounted", "NewLeaderAckRejected"
}

\* Events whose `detail` object is mandatory, with its mandatory fields.
DetailFields ==
    [e \in {"SyncProposalReceived", "SyncCommitReceived", "NewLeaderAckSent",
            "NewLeaderAckWritten",
            "BroadcastReady", "NewLeaderAckCounted", "NewLeaderAckRejected"} |->
       CASE e \in {"SyncProposalReceived", "SyncCommitReceived"} -> {"pending", "writeToTxnLog"}
         [] e \in {"NewLeaderAckSent", "NewLeaderAckWritten"} ->
                {"logged", "pending", "running", "durableZxid", "durableEpoch", "durableCounter"}
         [] e = "BroadcastReady" -> {"running", "pending"}
         [] OTHER -> {"peer"}]

PipelineEvents == {
    "ProposalQueued", "TxnAppended", "TxnDurable",
    "CommitDelivered", "TxnApplied"
}

TraceScenario == TraceLog[1].scenario

\* Zab1_0Test ConversableFollower-based scenarios (fixture leader "s1").
FixtureScenarios == {"follower-snap", "follower-diff",
                     "update-observe-ack-durability",
                     "update-observe-commit-after-newleader"}

\* Zab1_0Test's ConversableFollower runs the real learner protocol while its
\* fixture peer remains publicly LOOKING.  That documented fixture projection
\* applies only to the two follower harness scenarios; other traces preserve
\* LOOKING exactly.
TraceRole(r) ==
    CASE r = "looking" ->
           IF TraceScenario \in FixtureScenarios
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
         /\ rec.event.name \in DOMAIN DetailFields =>
               /\ "detail" \in DOMAIN rec.event
               /\ DetailFields[rec.event.name] \subseteq DOMAIN rec.event.detail

ASSUME TraceInputOK

IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name
EventName == logline.event.name
Node == logline.event.node
TxnId == logline.event.txnCounter
TxnEp == logline.event.txnEpoch
TxnEntry == EntryFor(TxnId, TxnEp)

HasEntry(h, ent) == \E k \in 1..Len(h) : h[k] = ent
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

NextLastLeader ==
    IF EventName \in {"PeerRoleChanged", "ElectionWon"}
       /\ logline.event.state.role = "leading"
    THEN Node ELSE lastLeader

ObservedLeaderOf(r) ==
    [s \in Server |->
       IF r[s] = "leading" THEN s
       ELSE IF r[s] = "looking" THEN Nil
       ELSE IF Cardinality(Leading(r)) = 1
            THEN CHOOSE x \in Leading(r) : TRUE
            ELSE IF s = Node /\ role[s] /= "following" /\ NextLastLeader \in Leading(r)
                 THEN NextLastLeader
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

\* ---- Update-focused observer state (Learner.syncWithLeader NEWLEADER path) ----
Detail == logline.event.detail

NextPendingSync ==
    CASE EventName = "SyncProposalReceived" ->
           [pendingSync EXCEPT ![Node] = Append(@, TxnEntry)]
      [] EventName = "SyncCommitReceived" /\ ~Detail.writeToTxnLog
           /\ pendingSync[Node] /= <<>> /\ Head(pendingSync[Node]) = TxnEntry ->
           \* SNAP before NEWLEADER: zk.processTxn + packetsNotCommitted.remove()
           [pendingSync EXCEPT ![Node] = Tail(@)]
      [] EventName = "NewLeaderAckSent" ->
           \* updated source: buffered proposals were logged, buffer cleared
           [pendingSync EXCEPT ![Node] = <<>>]
      [] EventName = "BroadcastReady" ->
           \* remaining buffered proposals are logged right after this probe
           [pendingSync EXCEPT ![Node] = <<>>]
      [] EventName \in {"PeerRoleChanged", "PhaseChanged"}
           /\ logline.event.state.phase \in {"election", "discovery"} ->
           [pendingSync EXCEPT ![Node] = <<>>]
      [] OTHER -> pendingSync

NextNlAckSent ==
    CASE EventName = "NewLeaderAckSent" -> [nlAckSent EXCEPT ![Node] = TRUE]
      [] EventName \in {"PeerRoleChanged", "PhaseChanged"}
           /\ logline.event.state.phase \in {"election", "discovery"} ->
           [nlAckSent EXCEPT ![Node] = FALSE]
      [] OTHER -> nlAckSent

PeerOf == IF EventName \in {"NewLeaderAckCounted", "NewLeaderAckRejected"}
          THEN Detail.peer ELSE Node

NextNlAcks ==
    CASE EventName = "NewLeaderAckCounted" -> [nlAcks EXCEPT ![Node] = @ \cup {PeerOf}]
      [] EventName \in {"PeerRoleChanged", "PhaseChanged"}
           /\ logline.event.state.phase \in {"election", "discovery"} ->
           [nlAcks EXCEPT ![Node] = {}]
      [] OTHER -> nlAcks

NextCertEpoch ==
    IF EventName \in {"CommitDelivered", "TxnApplied"} /\ certEpoch[TxnId] = 0
    THEN [certEpoch EXCEPT ![TxnId] = TxnEp]
    ELSE certEpoch

\* getLastLoggedZxid() probes report the IN-MEMORY database position, which
\* may lag the durable log (learner shutdown in INITIAL state skips the
\* fast-forward).  The observer keeps memHist as the node's local history
\* prefix ending at the reported zxid.
MemProbe == EventName \in {"PeerRoleChanged", "PhaseChanged", "FollowerRegistered",
                           "SyncModeChanged"}
LocalHist(n) ==
    LET cands == {proposed'[n], durable'[n], applied'[n], snapshot'[n]} IN
    CHOOSE h \in cands : \A g \in cands : Len(g) <= Len(h)
NextMemHist ==
    IF MemProbe /\ TxnId /= 0 /\ HasEntry(LocalHist(Node), TxnEntry)
    THEN [memHist EXCEPT ![Node] = PrefixThrough(LocalHist(Node), TxnEntry)]
    ELSE IF EventName = "SnapshotInstalled"
         THEN [memHist EXCEPT ![Node] = applied[SyncLeader]]
         ELSE memHist

\* zxid order between an entry and the (epoch, counter) read from disk.
EntryAtMost(ent, ep, ctr) == ent.epoch < ep \/ (ent.epoch = ep /\ ent.id <= ctr)

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
       /\ pendingSync' = NextPendingSync
       /\ nlAckSent' = NextNlAckSent
       /\ nlAcks' = NextNlAcks
       /\ certEpoch' = NextCertEpoch
       /\ memHist' = NextMemHist
       /\ lastLeader' = NextLastLeader
       /\ snapSession' = IF EventName = "SyncSelected"
                         THEN [snapSession EXCEPT ![Node] = (logline.event.state.syncMode = "SNAP")]
                         ELSE snapSession
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
    CASE EventName = "ElectionWon" ->
           \* FastLeaderElection.setPeerState logs proposedZxid, the zxid of the
           \* agreed vote, i.e. the ELECTED LEADER's last zxid (repair of the
           \* inherited interpretation, which compared it with the node's own log).
           IF TxnId = 0
           THEN TxnEp <= acceptedEpoch'[Node]
           ELSE IF role'[Node] = "leading"
                THEN ZxidMatches(memHist'[Node])
                ELSE \E x \in Server : ZxidMatches(memHist'[x]) \/ ZxidMatches(durable'[x])
      [] EventName \in {"PeerRoleChanged", "PhaseChanged"} ->
           \* REPAIR: the reported zxid is the in-memory position; it must be
           \* an entry of the node's local history (it may lag the durable log).
           IF TxnId = 0
           THEN TxnEp <= acceptedEpoch'[Node]
           ELSE /\ HasEntry(LocalHist(Node), TxnEntry)
                /\ ZxidMatches(memHist'[Node])
      [] EventName = "AcceptedEpochPersisted" ->
           acceptedEpoch'[Node] = TxnEp
      [] EventName = "CurrentEpochPersisted" ->
           currentEpoch'[Node] = TxnEp
      [] EventName = "FollowerRegistered" ->
           \* ACKEPOCH carries lastLoggedZxid (in-memory position)
           IF TxnId = 0 THEN TRUE
           ELSE /\ HasEntry(LocalHist(Node), TxnEntry)
                /\ ZxidMatches(memHist'[Node])
      [] EventName = "SyncModeChanged" ->
           \* QuorumPeer.setSyncMode probe reports getLastLoggedZxid (in-memory)
           TxnId = 0 \/ (HasEntry(LocalHist(Node), TxnEntry) /\ ZxidMatches(memHist'[Node]))
      [] EventName = "SyncSelected" ->
           \* the leader's directive zxid is its loaded (in-memory) position
           ZxidMatches(memHist'[SyncLeader]) \/ ZxidMatches(durable'[SyncLeader])
      [] EventName = "SnapshotInstalled" ->
           /\ ZxidMatches(snapshot'[Node])
           /\ ZxidMatches(durable'[Node])
      [] EventName = "BroadcastReady" ->
           \* getDataTreeLastProcessedZxid(): the in-memory data tree, which also
           \* holds history reloaded from disk at restart (not only TxnApplied)
           /\ ZxidMatches(applied'[Node]) \/ ZxidMatches(memHist'[Node])
           \* UPDATE: startServing() -> RUNNING only after UPTODATE (Learner.java:767)
           /\ Detail.running = TRUE
           \* UPTODATE is consumed only after the NEWLEADER ACK was written
           /\ nlAckSent[Node]
           \* buffered post-NEWLEADER proposals still to be logged
           /\ Detail.pending = Len(pendingSync[Node])
      [] EventName = "SyncProposalReceived" ->
           /\ Detail.pending = Len(pendingSync'[Node])
           /\ pendingSync'[Node][Len(pendingSync'[Node])] = TxnEntry
      [] EventName = "SyncCommitReceived" ->
           \* size of packetsNotCommitted when the COMMIT is handled
           Detail.pending = Len(pendingSync[Node])
      [] EventName = "NewLeaderAckSent" ->
           \* UPDATE (Learner.java:749-760): sync mode cleared, server INITIAL,
           \* every buffered proposal handed to logRequest before the ACK.
           /\ logline.event.state.syncMode = "NONE"
           /\ logline.event.state.currentEpoch = logline.event.state.acceptedEpoch
           /\ Detail.running = FALSE
           /\ Detail.pending = 0
           /\ Detail.logged = Len(pendingSync[Node])
           /\ \A k \in 1..Len(pendingSync[Node]) :
                 HasEntry(queued[Node], pendingSync[Node][k])
           /\ ~nlAckSent[Node]
           \* The on-disk txn-log position read at the ACK is at least the
           \* observed durable prefix (TxnDurable probes precede in sequence
           \* order).  SNAP sessions persist a snapshot, not log records.
           /\ (~snapSession[Node] /\ Detail.durableCounter >= 0) =>
                 (Len(durable'[Node]) = 0 \/
                  EntryAtMost(durable'[Node][Len(durable'[Node])],
                              Detail.durableEpoch, Detail.durableCounter))
      [] EventName = "NewLeaderAckWritten" ->
           \* post-write probe of the same NEWLEADER ACK: no state change,
           \* the on-disk position read after the write is at least the
           \* observed durable prefix.
           /\ nlAckSent[Node]
           /\ Detail.running = FALSE
           /\ Detail.pending = 0
           /\ (~snapSession[Node] /\ Detail.durableCounter >= 0) =>
                 (Len(durable'[Node]) = 0 \/
                  EntryAtMost(durable'[Node][Len(durable'[Node])],
                              Detail.durableEpoch, Detail.durableCounter))
      [] EventName = "NewLeaderAckCounted" ->
           /\ PeerOf \in Server
           \* the leader counts itself, or a learner that already wrote its ACK
           /\ PeerOf = Node \/ nlAckSent[PeerOf]
           /\ TxnEp = acceptedEpoch'[Node]
      [] EventName = "NewLeaderAckRejected" ->
           PeerOf \in Server
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

TraceNext ==
    /\ TraceObservedStep
    /\ ValidateCommonPostState
    /\ ValidateEventPostState

TraceInit ==
    /\ l = 1
    /\ snapSession = [s \in Server |-> FALSE]
    /\ lastLeader = Nil
    /\ up = [s \in Server |-> TRUE]
    /\ IF TraceScenario \in FixtureScenarios
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
         /\ pendingSync = [s \in Server |-> <<>>]
         /\ nlAckSent = [s \in Server |-> s /= follower]
         /\ nlAcks = [s \in Server |-> IF s = leader THEN Server ELSE {}]
         /\ certEpoch = [t \in Txn |-> IF t = 1 THEN 1 ELSE 0]
         /\ memHist = [s \in Server |-> IF s = follower THEN <<>> ELSE seed]
       ELSE
         /\ Init

TraceSpec == TraceInit /\ [][TraceNext]_traceAllVars
                         /\ WF_traceAllVars(TraceNext)

\* REQ-EVIDENCE TraceMatched
\* intent:   Trace validation eventually consumes every record of the selected trace, i.e. the whole trace is accepted by the model.
\* status:   model-internal
\* watch:    none in source/ (the trace files and the probes that emit these events are not part of this revision)
\* verified: base
\* note:     searched source/ for the trace event names (SyncSelected, TxnDurable, BroadcastReady) and for "ndjson": no matches.
\* review:   ok
TraceMatched == <>(l > Len(TraceLog))

\* Trace projection of OneActiveLeaderPerEpoch: the model's WinElection makes the
\* LEADING role and the new accepted epoch one step, the implementation sets
\* LEADING first and persists the epoch later in Leader.lead; a leader counts
\* for its epoch once it has established it (SYNCHRONIZATION or BROADCAST).
OneActiveLeaderPerEpochTrace ==
    \A e \in Epoch :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ phase[s] \in {"sync", "broadcast"}
                                    /\ acceptedEpoch[s] = e}) <= 1

TraceView == <<l, acceptedEpoch, currentEpoch, role, phase, syncMode,
               proposed, appended, durable, committed, applied,
               pendingSync, nlAckSent, nlAcks, snapSession>>

\* Update-observation helpers (used by the trace inventory; not assumptions).
AckBeforeDurableAt(k) ==
    LET rec == TraceLog[k] IN
    /\ rec.event.name = "NewLeaderAckSent"
    /\ rec.event.detail.logged > 0

=============================================================================
