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
\* V1 trace-local: the node's in-memory DB was left stale by a shutdown that
\* returned early in INITIAL state (observed ShutdownSkipped(INITIAL)); it is
\* cleared when a probe shows the in-memory position equal to the log again
\* (reload/fast-forward) or a new sync installs history.
VARIABLE memStale
\* V1 trace-local: FLE sets LEADING (QuorumPeer.setPeerState) before
\* Leader.lead binds the new epoch (getEpochToPropose -> setAcceptedEpoch);
\* base!WinElection performs both atomically.  An observed LEADING peer is the
\* model's protocol leader only once it persisted its new accepted epoch.
VARIABLE leaderBound
traceVars == <<l, memStale, leaderBound>>
traceAllVars == <<allVars, traceVars>>
logline == TraceLog[l]

EventNames == {
    "ElectionWon", "PeerRoleChanged", "PhaseChanged",
    "AcceptedEpochPersisted", "CurrentEpochPersisted",
    "FollowerRegistered", "SyncModeChanged", "SyncSelected",
    "SnapshotInstalled", "BroadcastReady", "ProposalQueued",
    "TxnAppended", "TxnDurable", "CommitDelivered", "TxnApplied",
    \* V1 update probes (harness/patches/instrumentation.patch)
    "NewLeaderAckSent", "NewLeaderAckReceived", "TxnAckSent",
    "ShutdownSkipped"
}

AckDispositions == {"counted", "counted-quorum", "after-quorum",
                    "rejected-zxid-mismatch"}

PipelineEvents == {
    "ProposalQueued", "TxnAppended", "TxnDurable",
    "CommitDelivered", "TxnApplied"
}

TraceScenario == TraceLog[1].scenario

\* Zab1_0Test-style conversations with a scripted (fake) leader peer.
FixtureScenarios == {"follower-snap", "follower-diff", "follower-diff-bulk-r1",
                     "follower-diff-bulk-r2", "follower-diff-bulk-r3"}
BulkScenario == TraceScenario \in {"follower-diff-bulk-r1", "follower-diff-bulk-r2",
                                   "follower-diff-bulk-r3"}
\* SpeculaNewLeaderAckOrderTest streams DIFF txns (1,1)..(1,7) from the
\* scripted leader (specula.diff.txns = 7).
FixtureSeed == IF BulkScenario THEN [k \in 1..7 |-> EntryFor(k, 1)]
               ELSE <<EntryFor(1, 1)>>

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
         \* V1: mandatory update fields of the new probes.
         /\ rec.event.name = "NewLeaderAckSent" =>
              /\ "update" \in DOMAIN rec.event
              /\ {"queuedZxid", "queuedEpoch", "queuedCounter",
                  "loggedAtNewLeader", "durableZxid", "durableEpoch",
                  "durableCounter", "fsyncedZxidAtAck", "serverState"}
                    \subseteq DOMAIN rec.event.update
              /\ rec.event.update.queuedCounter \in Txn \cup {-1}
              /\ rec.event.update.queuedEpoch \in Epoch \cup {-1}
              /\ rec.event.update.durableCounter \in Txn
              /\ rec.event.update.durableEpoch \in Epoch
              /\ rec.event.update.loggedAtNewLeader \in Nat
         /\ rec.event.name = "NewLeaderAckReceived" =>
              /\ "update" \in DOMAIN rec.event
              /\ rec.event.update.fromSid \in Server
              /\ rec.event.update.disposition \in AckDispositions
         /\ rec.event.name = "ShutdownSkipped" =>
              /\ "update" \in DOMAIN rec.event
              /\ "serverState" \in DOMAIN rec.event.update

ASSUME TraceInputOK

IsEvent(name) == l <= Len(TraceLog) /\ logline.event.name = name
EventName == logline.event.name
Node == logline.event.node
TxnId == logline.event.txnCounter
TxnEp == logline.event.txnEpoch
TxnEntry == EntryFor(TxnId, TxnEp)
Upd == logline.event.update
FromSid == Upd.fromSid
Disp == Upd.disposition
QueuedEntry == EntryFor(Upd.queuedCounter, Upd.queuedEpoch)
DurableEntry == EntryFor(Upd.durableCounter, Upd.durableEpoch)

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

ObservedRole == logline.event.state.role
NextLeaderBound ==
    CASE EventName = "AcceptedEpochPersisted" /\ ObservedRole = "leading" ->
           [leaderBound EXCEPT ![Node] = TRUE]
      [] ObservedRole \in {"looking", "following"} ->
           [leaderBound EXCEPT ![Node] = FALSE]
      [] OTHER -> leaderBound
\* model role for an observed role string, given the post-step binding
ModelRole(r) ==
    IF r = "leading" /\ ~NextLeaderBound[Node] THEN "looking" ELSE TraceRole(r)

\* getLastLoggedZxid = in-memory DataTree position of x: the log (load /
\* fast-forward), the applied prefix (a certified commit applied before the
\* local fsync; ZooKeeperServer.processTxn, QuorumPeer.java:1257-1262), or
\* the stale in-memory history after a skipped INITIAL shutdown.
InMemoryPositionMatches(x) ==
    \/ ZxidMatches(durable'[x])
    \* a LOOKING peer was fast-forwarded to its log on exit (RUNNING), so an
    \* applied position below the log is only legal while it still serves
    \/ /\ ZxidMatches(applied'[x])
       /\ (role'[x] /= "looking" \/ IsPrefix(durable'[x], applied'[x]))
    \/ memStale[x] /\ ZxidMatches(recovered[x])

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
       \/ /\ EventName = "AcceptedEpochPersisted" /\ ObservedRole = "leading"
    THEN [role EXCEPT ![Node] = ModelRole(logline.event.state.role)]
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

NextUsedTxn ==
    IF EventName \in PipelineEvents THEN usedTxn \cup {TxnId} ELSE usedTxn

\* ---------------- V1: update-visible state tracking --------------------
\* A role exit (QuorumPeer.setZabState back to election/discovery or a
\* LOOKING role) ends the learner/leader session.
SessionExit(nr, np) ==
    \/ /\ EventName = "PhaseChanged" /\ np[Node] \in {"election", "discovery"}
    \/ /\ EventName = "PeerRoleChanged" /\ nr[Node] = "looking"

\* The NEWLEADER branch logs packetsNotCommitted with logRequest
\* (ProposalQueued while still in SYNCHRONIZATION, before the ACK).
NewLeaderLog == EventName = "ProposalQueued" /\ phase[Node] = "sync"
                /\ nlState[Node] = "NONE"

NextNlState(nr, np) ==
    CASE NewLeaderLog -> [nlState EXCEPT ![Node] = "LOGGED"]
      [] EventName = "NewLeaderAckSent" -> [nlState EXCEPT ![Node] = "ACKED"]
      [] EventName = "BroadcastReady" -> [nlState EXCEPT ![Node] = "NONE"]
      [] SessionExit(nr, np) -> [nlState EXCEPT ![Node] = "NONE"]
      [] OTHER -> nlState

NextZkState(nr, np) ==
    CASE NewLeaderLog \/ EventName = "NewLeaderAckSent" ->
           [zkState EXCEPT ![Node] = "INITIAL"]
      [] EventName = "BroadcastReady" -> [zkState EXCEPT ![Node] = "RUNNING"]
      [] EventName = "PhaseChanged" /\ nr[Node] = "leading"
                                    /\ np[Node] = "broadcast" ->
           [zkState EXCEPT ![Node] = "RUNNING"]
      [] EventName = "ShutdownSkipped" /\ Upd.serverState /= "INITIAL" ->
           [zkState EXCEPT ![Node] = "OFF"]
      [] SessionExit(nr, np) -> [zkState EXCEPT ![Node] = "OFF"]
      [] OTHER -> zkState

NextAckShadowed(nr, np) ==
    CASE EventName = "TxnAckSent" /\ phase[Node] = "sync"
                                  /\ nlState[Node] = "LOGGED" ->
           [ackShadowed EXCEPT ![Node] = TRUE]
      [] SessionExit(nr, np) -> [ackShadowed EXCEPT ![Node] = FALSE]
      [] OTHER -> ackShadowed

NextNlAcks(nr, np) ==
    CASE EventName = "NewLeaderAckReceived"
            /\ Disp \in {"counted", "counted-quorum"} ->
           [nlAcks EXCEPT ![Node] = @ \cup {FromSid}]
      [] SessionExit(nr, np) -> [nlAcks EXCEPT ![Node] = {}]
      [] OTHER -> nlAcks

NextSyncKind(nr, np) ==
    CASE EventName = "SyncModeChanged" /\ logline.event.state.syncMode /= "NONE" ->
           [syncKind EXCEPT ![Node] = logline.event.state.syncMode]
      [] EventName = "BroadcastReady" \/ SessionExit(nr, np) ->
           [syncKind EXCEPT ![Node] = "NONE"]
      [] OTHER -> syncKind

\* Leader.lead certifies its loaded initial history when it starts serving
\* after the NEWLEADER quorum (base!LeaderBroadcast).
LeaderEstablished(nr, np) ==
    EventName = "PhaseChanged" /\ nr[Node] = "leading" /\ np[Node] = "broadcast"

\* getLastLoggedZxid reported by role/phase probes = in-memory DB position.
NextRecoveredV1(nr, np) ==
    CASE EventName = "SnapshotInstalled" ->
           [recovered EXCEPT ![Node] = durable[SyncLeader]]
      [] EventName \in {"PhaseChanged", "PeerRoleChanged"} /\ TxnId /= 0
            /\ HasEntry(queued[Node], TxnEntry) ->
           [recovered EXCEPT ![Node] = PrefixThrough(queued[Node], TxnEntry)]
      [] EventName \in {"PhaseChanged", "PeerRoleChanged"} /\ TxnId = 0
            /\ TxnEp = 0 ->
           [recovered EXCEPT ![Node] = <<>>]
      [] OTHER -> recovered

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
       \* at most one protocol leader per accepted epoch (base!OneActiveLeaderPerEpoch)
       /\ \A e \in Epoch : Cardinality({s \in Leading(nr) : na[s] = e}) <= 1
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
       /\ recovered' = NextRecoveredV1(nr, np)
       /\ acked' = acked
       /\ commitCertified' =
            IF LeaderEstablished(nr, np)
            THEN [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(proposed[Node])]
            ELSE NextCommitCertified
       /\ certEpoch' =
            IF LeaderEstablished(nr, np)
            THEN [t \in Txn |-> IF certEpoch[t] = 0 /\ t \in TxnIds(proposed[Node])
                                THEN nc[Node] ELSE certEpoch[t]]
            ELSE IF EventName \in {"CommitDelivered", "TxnApplied"} /\ certEpoch[TxnId] = 0
                 THEN [certEpoch EXCEPT ![TxnId] = TxnEp]
                 ELSE certEpoch
       /\ syncBuf' = syncBuf
       /\ syncKind' = NextSyncKind(nr, np)
       /\ nlState' = NextNlState(nr, np)
       /\ nlAckMsgs' = nlAckMsgs
       /\ nlAcks' = NextNlAcks(nr, np)
       /\ ackShadowed' = NextAckShadowed(nr, np)
       /\ zkState' = NextZkState(nr, np)
       /\ leaderBound' = NextLeaderBound
       /\ memStale' =
            CASE EventName = "ShutdownSkipped" /\ Upd.serverState = "INITIAL"
                    /\ zkState[Node] = "INITIAL" ->
                   [memStale EXCEPT ![Node] = TRUE]
              [] EventName \in {"PhaseChanged", "PeerRoleChanged"} /\ TxnId /= 0
                    /\ ZxidMatches(NextDurable[Node])
                    /\ NextQueued[Node] = NextDurable[Node] ->
                   [memStale EXCEPT ![Node] = FALSE]
              [] EventName \in {"SyncSelected", "SnapshotInstalled", "BroadcastReady"} ->
                   [memStale EXCEPT ![Node] = FALSE]
              [] OTHER -> memStale
       /\ messages' = messages
       /\ syncMode' = NextSyncMode
       /\ syncSource' = ObservedSyncSource(nr, np, nl)
       /\ syncJustified' = ObservedSyncJustified(nr, np)
       /\ usedTxn' = NextUsedTxn
       /\ rollbackAuthorized' =
            [s \in Server |-> EventName = "SnapshotInstalled" /\ s = Node]
       /\ l' = l + 1

ValidateCommonPostState ==
    /\ IF logline.event.state.acceptedEpoch >= 0
          THEN acceptedEpoch'[Node] = logline.event.state.acceptedEpoch
          ELSE TRUE
    /\ IF logline.event.state.currentEpoch >= 0
          THEN currentEpoch'[Node] = logline.event.state.currentEpoch
          ELSE TRUE
    /\ IF logline.event.state.role /= "unknown"
          THEN role'[Node] = ModelRole(logline.event.state.role)
          ELSE TRUE
    /\ IF logline.event.state.phase /= "unknown"
          THEN phase'[Node] = TracePhase(logline.event.state.phase)
          ELSE TRUE
    /\ syncMode'[Node] = logline.event.state.syncMode

ValidateEventPostState ==
    CASE EventName \in {"PeerRoleChanged", "ElectionWon", "PhaseChanged"} ->
           \* ElectionWon carries FastLeaderElection.proposedZxid, i.e. the
           \* elected leader's vote zxid (FastLeaderElection.java:setPeerState),
           \* not the local position, unless this node is the leader.
           \* Role/phase probes report getLastLoggedZxid = in-memory DB; V1:
           \* it equals the log unless an INITIAL-state shutdown was skipped
           \* (base!BeginElection INITIAL branch), in which case it keeps the
           \* previous in-memory position.
           /\ IF TxnId = 0
              THEN TxnEp <= acceptedEpoch'[Node]
              ELSE IF EventName = "ElectionWon" /\ ObservedRole /= "leading"
                   THEN \E x \in Server : InMemoryPositionMatches(x)
                   ELSE InMemoryPositionMatches(Node)
           \* V1 repair (base!LeaderBroadcast): BROADCAST only after a
           \* counted NEWLEADER-ACK quorum.
           /\ LeaderEstablished(role', phase') => Cardinality(nlAcks[Node]) >= Quorum
      [] EventName = "AcceptedEpochPersisted" ->
           acceptedEpoch'[Node] = TxnEp
      [] EventName = "CurrentEpochPersisted" ->
           currentEpoch'[Node] = TxnEp
      \* both report getLastLoggedZxid (Learner.java:487; QuorumPeer.setSyncMode probe)
      [] EventName = "FollowerRegistered" ->
           InMemoryPositionMatches(Node)
      [] EventName = "SyncModeChanged" ->
           TxnId = 0 \/ InMemoryPositionMatches(Node)
      \* the directive zxid is the leader's in-memory committed position
      \* (LearnerHandler.syncFollower: maxCommittedLog / DataTree position)
      [] EventName = "SyncSelected" ->
           InMemoryPositionMatches(SyncLeader)
      [] EventName = "SnapshotInstalled" ->
           /\ ZxidMatches(snapshot'[Node])
           /\ ZxidMatches(durable'[Node])
      [] EventName = "BroadcastReady" ->
           \* V1: UPTODATE is consumed only after the NEWLEADER branch wrote
           \* its ACK (Learner.java:711-767); startServing -> RUNNING.
           \* The probe reports the in-memory DataTree position
           \* (getDataTreeLastProcessedZxid) = V1 `recovered`: DIFF entries are
           \* not applied in memory before UPTODATE (Learner.java:655-668).
           /\ ZxidMatches(recovered'[Node])
           /\ nlState[Node] = "ACKED"
      [] EventName = "NewLeaderAckSent" ->
           \* V1 (base!FollowerProcessNewLeader + FollowerSendNewLeaderAck):
           \* epoch persisted and sync mode cleared before the ACK; the
           \* logged packetsNotCommitted are queued (not necessarily durable);
           \* the server is started without serving.
           /\ TxnId = 0
           /\ currentEpoch'[Node] = TxnEp
           /\ syncMode'[Node] = "NONE"
           /\ (Upd.loggedAtNewLeader > 0) = (nlState[Node] = "LOGGED")
           /\ Upd.loggedAtNewLeader > 0 =>
                /\ Len(queued'[Node]) > 0
                /\ queued'[Node][Len(queued'[Node])] = QueuedEntry
           \* durableZxid is the txn-log fsync watermark; it describes the
           \* restorable history only for DIFF sessions (SNAP/TRUNC replace it
           \* through the synchronous snapshot / truncation instead).
           /\ (Upd.durableCounter > 0 /\ syncKind[Node] = "DIFF") =>
                /\ Len(durable'[Node]) > 0
                /\ durable'[Node][Len(durable'[Node])] = DurableEntry
           /\ Upd.serverState = "NOT_RUNNING"
      [] EventName = "NewLeaderAckReceived" ->
           \* base!LeaderProcessNewLeaderAck (Leader.java:1547-1572)
           /\ role'[Node] = "leading"
           /\ CASE Disp \in {"counted", "counted-quorum"} ->
                     /\ phase[Node] = "sync"
                     /\ TxnId = 0 /\ TxnEp = acceptedEpoch[Node]
                     /\ (FromSid = Node \/ ~ackShadowed[FromSid])
                     /\ (Disp = "counted-quorum") =
                          (Cardinality(nlAcks'[Node]) >= Quorum)
                [] Disp = "after-quorum" ->
                     Cardinality(nlAcks[Node]) >= Quorum
                [] OTHER ->
                     \* rejected: a txn ACK read first must be a shadowing ACK
                     TxnId /= 0 => ackShadowed[FromSid]
      [] EventName = "TxnAckSent" ->
           \* SendAckRequestProcessor runs after the flush: ACK => durable
           HasEntry(durable'[Node], TxnEntry)
      [] EventName = "ShutdownSkipped" ->
           \* canShutdown() false: INITIAL (startupWithoutServing) or SHUTDOWN
           /\ Upd.serverState \in {"INITIAL", "SHUTDOWN"}
           \* INITIAL is also the constructor state of a never-started server
           \* (e.g. a leader before startZkServer); never RUNNING.
           /\ Upd.serverState = "INITIAL" => zkState[Node] \in {"INITIAL", "OFF"}
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
    /\ memStale = [s \in Server |-> FALSE]
    /\ leaderBound = [s \in Server |->
                        TraceScenario \in FixtureScenarios /\ s = "s1"]
    /\ up = [s \in Server |-> TRUE]
    /\ IF TraceScenario \in FixtureScenarios
       THEN
         LET leader == "s1" IN
         LET follower == "s0" IN
         LET seed == FixtureSeed IN
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
         /\ acked = [t \in Txn |-> IF t \in TxnIds(seed) THEN Server ELSE {}]
         /\ commitCertified = [t \in Txn |-> t \in TxnIds(seed)]
         /\ messages = {}
         /\ syncMode = [s \in Server |-> "NONE"]
         /\ syncSource = [s \in Server |-> IF s = follower THEN leader ELSE Nil]
         /\ syncJustified = [s \in Server |-> s /= follower]
         /\ usedTxn = TxnIds(seed)
         /\ rollbackAuthorized = [s \in Server |-> FALSE]
         /\ syncBuf = [s \in Server |-> <<>>]
         /\ syncKind = [s \in Server |-> "NONE"]
         /\ nlState = [s \in Server |-> "NONE"]
         /\ nlAckMsgs = {}
         /\ nlAcks = [s \in Server |-> IF s = leader THEN {leader} ELSE {}]
         /\ ackShadowed = [s \in Server |-> FALSE]
         /\ zkState = [s \in Server |-> IF s = follower THEN "OFF" ELSE "RUNNING"]
         /\ certEpoch = [t \in Txn |-> IF t \in TxnIds(seed) THEN 1 ELSE 0]
       ELSE
         /\ Init

TraceSpec == TraceInit /\ [][TraceNext]_traceAllVars
                         /\ WF_traceAllVars(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

TraceView == <<l, acceptedEpoch, currentEpoch, role, phase, syncMode,
               proposed, appended, durable, committed, applied,
               recovered, nlState, nlAcks, ackShadowed, zkState, certEpoch,
               memStale, leaderBound>>

=============================================================================
