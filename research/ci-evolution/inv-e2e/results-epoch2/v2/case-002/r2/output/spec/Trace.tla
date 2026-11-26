------------------------------ MODULE Trace ------------------------------
\* Incremental revision for update 2efbdfc.  Observational replay of one
\* retained NDJSON trace (Category A).  Update-specific probes
\* (SyncProposalBuffered, SyncCommitBuffered, NewLeaderAck,
\* NewLeaderAckCounted, NewLeaderAckRejected) drive the new learner-buffer,
\* NEWLEADER-stage and leader ack-set variables and are compared against the
\* reference semantics of SyncWithLeaderNewLeader / SyncWithLeaderUpToDate /
\* LeaderBroadcast (see ValidateEventPostState).
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

VARIABLE l, pendingLead
traceVars == <<l, pendingLead>>
traceAllVars == <<allVars, traceVars>>
logline == TraceLog[l]

EventNames == {
    "ElectionWon", "PeerRoleChanged", "PhaseChanged",
    "AcceptedEpochPersisted", "CurrentEpochPersisted",
    "FollowerRegistered", "SyncModeChanged", "SyncSelected",
    "SnapshotInstalled", "BroadcastReady", "ProposalQueued",
    "TxnAppended", "TxnDurable", "CommitDelivered", "TxnApplied",
    \* update probes (harness/patches/instrumentation.patch)
    "SyncProposalBuffered", "SyncCommitBuffered", "NewLeaderAck",
    "NewLeaderAckCounted", "NewLeaderAckRejected"
}

\* Zab1_0Test conversations use a scripted leader fixture that emits no
\* leader-side events.
FixtureScenarios == {"follower-snap", "follower-diff"}

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
         /\ {"name", "node", "peer", "zxid", "txnCounter", "txnEpoch", "state"}
               \subseteq DOMAIN rec.event
         /\ rec.event.peer \in Server \cup {"none"}
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
Peer == logline.event.peer
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

\* base!WinElection is atomic: the elected role and the proposed accepted
\* epoch change together.  In the implementation FastLeaderElection sets
\* LEADING (QuorumPeer.setPeerState) before Leader.getEpochToPropose persists
\* the new accepted epoch, and the previous epoch's leader can still be
\* LEADING meanwhile.  A reported LEADING peer is therefore projected to the
\* model's "looking" until its next AcceptedEpochPersisted (pendingLead).
NextPendingLead ==
    CASE EventName = "PeerRoleChanged" /\ logline.event.state.role = "leading" ->
           pendingLead \cup {Node}
      [] EventName = "AcceptedEpochPersisted" /\ logline.event.state.role = "leading" ->
           pendingLead \ {Node}
      [] EventName = "PeerRoleChanged" \/ (EventName = "PhaseChanged"
                                          /\ logline.event.state.phase = "election") ->
           pendingLead \ {Node}
      [] OTHER -> pendingLead

ProjectedRole(r, pl) == IF r = "leading" /\ Node \in pl THEN "looking" ELSE TraceRole(r)

NextRole ==
    IF \/ EventName = "PeerRoleChanged"
       \/ /\ EventName = "PhaseChanged"
          /\ logline.event.state.phase = "election"
       \/ /\ EventName = "AcceptedEpochPersisted"
          /\ logline.event.state.role = "leading"
    THEN [role EXCEPT ![Node] = ProjectedRole(logline.event.state.role, NextPendingLead)]
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

\* A learner session ends when the peer returns to election (base
\* BeginElection resets the learner buffers; the persistence pipeline stays).
SessionEnds(r, ph) == r[Node] = "looking" /\ ph[Node] = "election"
                      /\ TraceScenario \notin FixtureScenarios

\* ProposalQueued from Learner.syncWithLeader consumes the head of the
\* packetsNotCommitted buffer (in order); other ProposalQueued events are
\* broadcast-phase proposals.
FromSyncBuf == EventName = "ProposalQueued" /\ syncBuf[Node] /= <<>>

NextSyncBuf(r, ph) ==
    CASE EventName = "SyncSelected" -> [syncBuf EXCEPT ![Node] = <<>>]
      [] EventName = "SyncProposalBuffered" ->
           [syncBuf EXCEPT ![Node] = Append(@, TxnEntry)]
      [] FromSyncBuf -> [syncBuf EXCEPT ![Node] = Tail(@)]
      [] SessionEnds(r, ph) -> [syncBuf EXCEPT ![Node] = <<>>]
      [] OTHER -> syncBuf

NextSyncCommit(r, ph) ==
    CASE EventName = "SyncSelected" -> [syncCommit EXCEPT ![Node] = <<>>]
      [] EventName = "SyncCommitBuffered" ->
           [syncCommit EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
      [] EventName = "BroadcastReady" -> [syncCommit EXCEPT ![Node] = <<>>]
      [] SessionEnds(r, ph) -> [syncCommit EXCEPT ![Node] = <<>>]
      [] OTHER -> syncCommit

NextSyncStage(r, ph) ==
    CASE EventName = "SyncSelected" -> [syncStage EXCEPT ![Node] = "payload"]
      [] EventName = "NewLeaderAck" -> [syncStage EXCEPT ![Node] = "newleader"]
      [] EventName = "BroadcastReady" -> [syncStage EXCEPT ![Node] = "idle"]
      [] SessionEnds(r, ph) -> [syncStage EXCEPT ![Node] = "idle"]
      [] OTHER -> syncStage

\* Leader.waitForNewLeaderAck ack set (newLeaderProposal).  A peer that
\* (re)enters LEADING gets a new Leader object whose set starts empty
\* (QuorumPeer.makeLeader, Leader.java:434); the reported role is used
\* because the projected role stays "looking" until the epoch proposal.
NextNlAcks(r, ph) ==
    CASE EventName = "NewLeaderAckCounted" -> [nlAcks EXCEPT ![Node] = @ \cup {Peer}]
      [] EventName = "PeerRoleChanged" /\ logline.event.state.role = "leading" ->
           [nlAcks EXCEPT ![Node] = {}]
      [] OTHER -> nlAcks

\* Leader.lead: the BROADCAST publication follows startZkServer, which
\* serves the leader's whole loaded history (base!LeaderBroadcast).
LeaderActivates(r, ph) ==
    /\ EventName = "PhaseChanged" /\ r[Node] = "leading"
    /\ ph[Node] = "broadcast" /\ phase[Node] = "sync"

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
    CASE LeaderActivates(NextRole, NextPhase) /\ IsPrefix(committed[Node], durable[Node]) ->
           [committed EXCEPT ![Node] = durable[Node]]
      [] EventName \in {"CommitDelivered", "TxnApplied"} ->
           [committed EXCEPT ![Node] = PrefixThrough(LongestCommitted, TxnEntry)]
      [] EventName = "SnapshotInstalled" ->
           [committed EXCEPT ![Node] = committed[SyncLeader]]
      [] OTHER -> committed

NextApplied ==
    CASE LeaderActivates(NextRole, NextPhase) /\ IsPrefix(applied[Node], durable[Node]) ->
           [applied EXCEPT ![Node] = durable[Node]]
      [] EventName = "TxnApplied" ->
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
    CASE LeaderActivates(NextRole, NextPhase) ->
           [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(durable[Node])]
      [] EventName \in {"CommitDelivered", "TxnApplied"} ->
           [commitCertified EXCEPT ![TxnId] = TRUE]
      [] OTHER -> commitCertified

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
       /\ syncBuf' = NextSyncBuf(nr, np)
       /\ syncCommit' = NextSyncCommit(nr, np)
       /\ syncStage' = NextSyncStage(nr, np)
       /\ nlAcks' = NextNlAcks(nr, np)
       /\ l' = l + 1
       /\ pendingLead' = NextPendingLead

ValidateCommonPostState ==
    /\ IF logline.event.state.acceptedEpoch >= 0
          THEN acceptedEpoch'[Node] = logline.event.state.acceptedEpoch
          ELSE TRUE
    /\ IF logline.event.state.currentEpoch >= 0
          THEN currentEpoch'[Node] = logline.event.state.currentEpoch
          ELSE TRUE
    /\ IF logline.event.state.role /= "unknown"
          THEN role'[Node] = ProjectedRole(logline.event.state.role, pendingLead')
          ELSE TRUE
    /\ IF logline.event.state.phase /= "unknown"
          THEN phase'[Node] = TracePhase(logline.event.state.phase)
          ELSE TRUE
    /\ syncMode'[Node] = logline.event.state.syncMode

ValidateEventPostState ==
    \* QuorumPeer.getLastLoggedZxid() reports the in-memory data tree's last
    \* processed zxid.  It equals the durable tail whenever the previous
    \* ZooKeeperServer was shut down (fastForwardDataBase) or reloaded; in the
    \* updated code a learner that fails after NEWLEADER keeps an INITIAL
    \* server whose shutdown is skipped (ZooKeeperServer.java:784-786), so its
    \* tree can lag the log that the leaked SyncThread keeps fsyncing.  The
    \* reported zxid must still name an entry of the durable history.
    CASE EventName \in {"PeerRoleChanged", "PhaseChanged"} ->
           /\ IF TxnId = 0
              THEN TxnEp <= acceptedEpoch'[Node]
              ELSE HasEntry(durable'[Node], TxnEntry)
           \* base!LeaderBroadcast guard: a NEWLEADER ack quorum was counted.
           /\ (LeaderActivates(role', phase') => Cardinality(nlAcks[Node]) >= Quorum)
      \* FastLeaderElection.setPeerState emits proposedZxid, the zxid of the
      \* elected vote (FastLeaderElection.java:898-901), i.e. the winner's
      \* last zxid, not necessarily the emitting learner's own.
      [] EventName = "ElectionWon" ->
           \* The vote zxid is the winner's data-tree zxid; it names an entry
           \* of the winner's durable history (equal to its tail unless the
           \* tree lags the log, see the PeerRoleChanged comment).
           /\ IF TxnId = 0
              THEN TxnEp <= MaxEpoch
              ELSE \E x \in Server : HasEntry(durable'[x], TxnEntry)
           /\ (logline.event.state.role = "leading" /\ TxnId /= 0) =>
                 HasEntry(durable'[Node], TxnEntry)
           \* base!LeaderBroadcast guard: a NEWLEADER ack quorum was counted.
           /\ (LeaderActivates(role', phase') => Cardinality(nlAcks[Node]) >= Quorum)
      [] EventName = "AcceptedEpochPersisted" ->
           acceptedEpoch'[Node] = TxnEp
      [] EventName = "CurrentEpochPersisted" ->
           currentEpoch'[Node] = TxnEp
      [] EventName = "FollowerRegistered" ->
           ZxidMatches(durable'[Node])
      [] EventName = "SyncModeChanged" ->
           TxnId = 0 \/ ZxidMatches(durable'[Node])
      [] EventName = "SyncSelected" ->
           ZxidMatches(durable'[SyncLeader])
      [] EventName = "SnapshotInstalled" ->
           /\ ZxidMatches(snapshot'[Node])
           /\ ZxidMatches(durable'[Node])
      [] EventName = "BroadcastReady" ->
           \* The reported zxid is the data tree's last processed zxid: the
           \* applied tail, or -- after an unobserved process restart, where
           \* FileTxnSnapLog.restore replays the durable log into the tree
           \* without ZooKeeperServer.processTxn probes -- the durable tail.
           /\ ZxidMatches(applied'[Node]) \/ ZxidMatches(durable'[Node])
           \* UPTODATE follows the NEWLEADER handler; the leader sends it
           \* only after its NEWLEADER quorum formed (LearnerHandler.java:623-648).
           /\ syncStage[Node] = "newleader"
           /\ TraceScenario \notin FixtureScenarios =>
                \E ld \in Server : /\ role[ld] = "leading"
                                   /\ acceptedEpoch[ld] = acceptedEpoch[Node]
                                   /\ Cardinality(nlAcks[ld]) >= Quorum
      [] EventName = "ProposalQueued" ->
           /\ ZxidMatches(proposed'[Node])
           /\ ZxidMatches(queued'[Node])
           \* Buffered sync proposals are logged in buffer order, and in the
           \* NEWLEADER handler only after the new current epoch persisted
           \* (Learner.java:743 before :752-757).
           /\ FromSyncBuf =>
                /\ Head(syncBuf[Node]) = TxnEntry
                /\ (syncStage[Node] = "payload" =>
                      currentEpoch[Node] = acceptedEpoch[Node])
      [] EventName = "SyncProposalBuffered" ->
           /\ syncStage[Node] \in {"payload", "newleader"}
           /\ syncBuf'[Node] /= <<>>
           /\ syncBuf'[Node][Len(syncBuf'[Node])] = TxnEntry
           /\ ~HasEntry(syncBuf[Node], TxnEntry)
      [] EventName = "SyncCommitBuffered" ->
           /\ syncStage[Node] \in {"payload", "newleader"}
           /\ HasEntry(syncCommit'[Node], TxnEntry)
           \* a COMMIT names a proposal the learner already holds
           /\ HasEntry(proposed[Node] \o syncBuf[Node], TxnEntry)
      \* Updated NEWLEADER handler (Learner.java:743-760), observed just
      \* before the ACK write: the epoch is current, the reported sync mode
      \* was already reset, and every buffered packetsNotCommitted proposal
      \* was handed to logRequest (queued) -- the V0 code still held them.
      [] EventName = "NewLeaderAck" ->
           /\ syncStage[Node] = "payload"
           /\ currentEpoch'[Node] = TxnEp
           /\ currentEpoch'[Node] = acceptedEpoch'[Node]
           /\ syncMode'[Node] = "NONE"
           /\ syncBuf[Node] = <<>>
           /\ syncBuf'[Node] = <<>>
           /\ \A k \in 1..Len(syncCommit[Node]) :
                 HasEntry(queued'[Node], syncCommit[Node][k])
      \* Leader.waitForNewLeaderAck (Leader.java:1569): the ACK names the
      \* leader's epoch and comes from the leader itself or from a learner
      \* whose NewLeaderAck probe (emitted before its write) was replayed.
      [] EventName = "NewLeaderAckCounted" ->
           /\ role'[Node] = "leading"
           /\ phase'[Node] = "sync"
           /\ TxnEp = acceptedEpoch[Node] /\ TxnId = 0
           /\ Peer \in Server
           /\ (Peer = Node \/ /\ syncStage[Peer] = "newleader"
                               /\ acceptedEpoch[Peer] = TxnEp)
           /\ Peer \in nlAcks'[Node]
      [] EventName = "NewLeaderAckRejected" ->
           /\ role'[Node] = "leading"
           /\ ~(TxnEp = acceptedEpoch[Node] /\ TxnId = 0)
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
    /\ pendingLead = {}
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
         /\ syncBuf = [s \in Server |-> <<>>]
         /\ syncCommit = [s \in Server |-> <<>>]
         /\ syncStage = [s \in Server |-> "idle"]
         /\ nlAcks = [s \in Server |-> IF s = leader THEN Server ELSE {}]
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

TraceView == <<l, acceptedEpoch, currentEpoch, role, phase, syncMode,
               proposed, appended, durable, committed, applied,
               syncBuf, syncCommit, syncStage, nlAcks>>

=============================================================================
