------------------------------ MODULE Trace ------------------------------
(***************************************************************************)
(* Trace validation for revision `update` (case-002).                      *)
(*                                                                         *)
(* Two step kinds:                                                         *)
(*  * Action steps (update window and SyncRequestProcessor/apply path):    *)
(*    the event is replayed through the reference Action of base.tla and  *)
(*    the captured fields are compared with the post-state.  This covers  *)
(*    SelectSync, CompleteSync, PersistCurrentEpoch, ClearSyncMode,        *)
(*    LogSyncProposal, AckNewLeader, CountNewLeaderAck, LeaderBroadcast,   *)
(*    ReceiveUpToDate, EnterBroadcast, ObserveCommit, AppendOne, FsyncOne, *)
(*    ApplyOne.                                                            *)
(*  * Observed steps (inherited V0 projection, unchanged mechanisms):      *)
(*    election, discovery, epoch persistence of the leader, and leader-   *)
(*    side/broadcast-phase pipeline probes whose producing Actions        *)
(*    (FLE voting, Propose, DeliverAck, Commit) are not instrumented.      *)
(*    These keep the V0 source-gated field projection and are recorded as *)
(*    an inherited limitation (spec/changelog.md).                         *)
(* Two narrowly guarded silent steps stand for uninstrumented leader-side  *)
(* Actions that the next learner event requires (see below).               *)
(***************************************************************************)
EXTENDS base, Json, IOUtils, Sequences, TLC

\* A caller selects one retained NDJSON trace by setting the JSON environment
\* value.  Every tag="trace" record in the selected file is a replay obligation.
JsonFile == IF "JSON" \in DOMAIN IOEnv
            THEN IOEnv.JSON
            ELSE "../traces/diff-sync-uncommitted-log.ndjson"

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
    \* UPDATE-MAP code: quorum/Learner.java:760; quorum/Leader.java:1555-1569
    \* update: Update!AffectedActions (AckNewLeader), base!CountNewLeaderAck
    "NewLeaderAckSent", "NewLeaderAckCounted", "NewLeaderAckMismatch",
    \* QuorumPeer.loadDataBase (QuorumPeer.java:1101-1150): process (re)start
    "PeerDatabaseLoaded"
}

PeerEvents == {"NewLeaderAckCounted", "NewLeaderAckMismatch"}

PipelineEvents == {
    "ProposalQueued", "TxnAppended", "TxnDurable",
    "CommitDelivered", "TxnApplied"
}

TraceScenario == TraceLog[1].scenario

\* Zab1_0Test's ConversableFollower runs the real learner protocol against a
\* test-thread "leader" while the fixture peer remains publicly LOOKING.  The
\* fixture projection (role LOOKING -> FOLLOWING, the fake leader's history and
\* its uninstrumented commits) applies only to these two scenarios.
FixtureScenarios == {"follower-snap", "follower-diff"}
IsFixture == TraceScenario \in FixtureScenarios

TraceRole(r) ==
    CASE r = "looking" ->
           IF IsFixture THEN "following" ELSE "looking"
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
         /\ (rec.event.name \in PeerEvents) => ("peer" \in DOMAIN rec.event
                                                 /\ rec.event.peer \in Server)
         /\ {"acceptedEpoch", "currentEpoch", "role", "phase", "syncMode"}
               \subseteq DOMAIN rec.event.state
         /\ IsKnownPeerState(rec.event.state)

ASSUME TraceInputOK

EventName == logline.event.name
Node == logline.event.node
Peer == logline.event.peer
TxnId == logline.event.txnCounter
TxnEp == logline.event.txnEpoch
TxnEntry == EntryFor(TxnId, TxnEp)
St == logline.event.state

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
(* Event classification (evaluated in the pre-state).                      *)
(***************************************************************************)
Kind ==
    CASE EventName = "SyncModeChanged" /\ St.syncMode /= "NONE" -> "SelectSync"
      [] EventName = "SyncModeChanged" -> "ClearSyncMode"
      [] EventName = "SyncSelected" -> "CompleteSync"
      [] EventName = "SnapshotInstalled" -> "Check"
      [] EventName = "CurrentEpochPersisted"
           /\ role[Node] = "following" /\ phase[Node] = "sync" -> "PersistCurrentEpoch"
      [] EventName = "ProposalQueued" /\ phase[Node] = "sync" -> "LogSyncProposal"
      [] EventName = "NewLeaderAckSent" -> "AckNewLeader"
      [] EventName = "NewLeaderAckCounted" -> "CountNewLeaderAck"
      [] EventName = "NewLeaderAckMismatch" -> "Check"
      [] EventName = "PeerDatabaseLoaded" /\ ~up[Node] -> "Restart"
      [] EventName = "PeerDatabaseLoaded" -> "Check"
      [] EventName = "BroadcastReady" -> "ReceiveUpToDate"
      [] EventName = "PhaseChanged" /\ St.phase = "broadcast"
           /\ role[Node] = "leading" -> "LeaderBroadcast"
      [] EventName = "PhaseChanged" /\ St.phase = "broadcast"
           /\ role[Node] = "following" -> "EnterBroadcast"
      [] EventName = "CommitDelivered" /\ phase[Node] = "sync" -> "ObserveCommit"
      [] EventName = "TxnAppended" /\ role[Node] /= "leading" -> "AppendOne"
      [] EventName = "TxnDurable" /\ role[Node] /= "leading" -> "FsyncOne"
      [] EventName = "TxnApplied" /\ role[Node] = "following" -> "ApplyOne"
      [] OTHER -> "Observed"

ActionStep ==
    /\ l <= Len(TraceLog)
    /\ Kind /= "Observed"
    /\ CASE Kind = "SelectSync" -> SelectSync(Node, leaderOf[Node], St.syncMode)
         [] Kind = "ClearSyncMode" -> ClearSyncMode(Node)
         [] Kind = "CompleteSync" -> CompleteSync(Node)
         [] Kind = "PersistCurrentEpoch" -> PersistCurrentEpoch(Node)
         [] Kind = "LogSyncProposal" -> LogSyncProposal(Node)
         [] Kind = "AckNewLeader" -> AckNewLeader(Node)
         [] Kind = "CountNewLeaderAck" -> CountNewLeaderAck(Node, Peer)
         [] Kind = "ReceiveUpToDate" -> ReceiveUpToDate(Node)
         [] Kind = "LeaderBroadcast" -> LeaderBroadcast(Node)
         [] Kind = "EnterBroadcast" -> EnterBroadcast(Node)
         [] Kind = "ObserveCommit" -> ObserveCommit(Node, TxnId, TxnEp)
         [] Kind = "AppendOne" -> AppendOne(Node)
         [] Kind = "FsyncOne" -> FsyncOne(Node)
         [] Kind = "ApplyOne" -> ApplyOne(Node)
         [] Kind = "Restart" -> Restart(Node)
         [] Kind = "Check" -> UNCHANGED allVars
    /\ l' = l + 1

(***************************************************************************)
(* Inherited observed projection for unchanged, uninstrumented mechanisms. *)
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
          /\ St.phase = "election"
    THEN [role EXCEPT ![Node] = TraceRole(St.role)]
    ELSE role

NextPhase ==
    IF EventName = "PhaseChanged"
    THEN [phase EXCEPT ![Node] = TracePhase(St.phase)]
    ELSE phase

Leading(r) == {s \in Server : r[s] = "leading"}

\* A learner follows the unique LEADING peer; while two peers are LEADING
\* (a stale leader has not yet noticed the new election, observed in
\* diff-sync-uncommitted-log) the association is left unchanged.
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
       IF s = Node /\ r[s] = "following" /\ ph[s] = "sync"
       THEN IF lof[s] \in Server THEN lof[s] ELSE syncSource[s]
       ELSE IF s = Node /\ r[s] \in {"looking", "leading"}
            THEN Nil
            ELSE syncSource[s]]

\* Leaving the protocol round (LOOKING / ELECTION / a new DISCOVERY) resets
\* the per-round learner and leader bookkeeping exactly as BeginElection,
\* WinElection and FollowLeader do in base.tla.
ResetsRound(r, ph) ==
    {s \in Server : s = Node /\ (r[s] = "looking" \/ ph[s] \in {"election", "discovery"})}

ObservedSyncJustified(r, ph) ==
    [s \in Server |-> IF s \in ResetsRound(r, ph) THEN FALSE ELSE syncJustified[s]]

LongestCommitted ==
    CHOOSE h \in {committed[s] : s \in Server} :
        \A s \in Server : Len(committed[s]) <= Len(h)

LongestApplied ==
    CHOOSE h \in {applied[s] : s \in Server} :
        \A s \in Server : Len(applied[s]) <= Len(h)

\* Leaving a RUNNING server: SyncRequestProcessor.shutdown has drained and
\* forced the queue (its TxnDurable probes precede LOOKING on the same
\* thread) and fastForwardDataBase rebuilt the database from the log
\* (ZooKeeperServer.java:803-850).  A non-RUNNING server keeps its database.
GracefulReset(r, ph) ==
    {s \in ResetsRound(r, ph) : zkState[s] = "running"
                                /\ (r[s] = "looking" \/ ph[s] = "election")}

NextRecovered(r, ph) ==
    CASE Node \in GracefulReset(r, ph) ->
           [recovered EXCEPT ![Node] = durable[Node]]
      [] EventName = "TxnApplied" ->
           LET na == PrefixThrough(LongestApplied, TxnEntry) IN
           [recovered EXCEPT ![Node] =
               IF IsPrefix(na, recovered[Node]) THEN recovered[Node] ELSE na]
      [] OTHER -> recovered

ObservedProposed(r, ph) ==
    CASE EventName \in PipelineEvents ->
           [proposed EXCEPT ![Node] = EnsureEntry(@, TxnEntry)]
      [] Node \in ResetsRound(r, ph) /\ (r[Node] = "looking" \/ ph[Node] = "election") ->
           [proposed EXCEPT ![Node] = queued[Node]]
      [] OTHER -> proposed

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

NextCommitted ==
    IF EventName \in {"CommitDelivered", "TxnApplied"}
    THEN [committed EXCEPT ![Node] = PrefixThrough(LongestCommitted, TxnEntry)]
    ELSE committed

NextApplied ==
    IF EventName = "TxnApplied"
    THEN [applied EXCEPT ![Node] = PrefixThrough(LongestApplied, TxnEntry)]
    ELSE applied

NextCommitCertified ==
    IF EventName \in {"CommitDelivered", "TxnApplied"}
    THEN [commitCertified EXCEPT ![TxnId] = TRUE]
    ELSE commitCertified

NextUsedTxn ==
    IF EventName \in PipelineEvents THEN usedTxn \cup {TxnId} ELSE usedTxn

ObservedStep ==
    /\ l <= Len(TraceLog)
    /\ Kind = "Observed"
    /\ LET nr == NextRole IN
       LET np == NextPhase IN
       LET na == NextAccepted IN
       LET nc == NextCurrent IN
       LET nl == ObservedLeaderOf(nr) IN
       LET rs == ResetsRound(nr, np) IN
       /\ \A s \in Server : nc[s] <= na[s]
       \* validates the drain-before-LOOKING abstraction of base!BeginElection
       /\ \A s \in GracefulReset(nr, np) : durable[s] = queued[s]
       /\ up' = up
       /\ role' = nr
       /\ phase' = np
       /\ leaderOf' = nl
       /\ acceptedEpoch' = na
       /\ currentEpoch' = nc
       /\ votes' = votes
       /\ leadersByEpoch' = ObservedLeadersByEpoch(nr, na)
       /\ proposed' = ObservedProposed(nr, np)
       /\ queued' = NextQueued
       /\ appended' = NextAppended
       /\ durable' = NextDurable
       /\ committed' = NextCommitted
       /\ applied' = NextApplied
       /\ snapshot' = snapshot
       /\ recovered' = NextRecovered(nr, np)
       /\ acked' = acked
       /\ commitCertified' = NextCommitCertified
       /\ messages' = messages
       /\ syncMode' = syncMode
       /\ syncSource' = ObservedSyncSource(nr, np, nl)
       /\ syncJustified' = ObservedSyncJustified(nr, np)
       /\ usedTxn' = NextUsedTxn
       /\ rollbackAuthorized' = [s \in Server |-> FALSE]
       /\ nlAcks' = [s \in Server |->
                       IF s = Node /\ EventName = "PeerRoleChanged"
                          /\ nr[s] \in {"leading", "looking"}
                       THEN {} ELSE nlAcks[s]]
       /\ newLeaderAcked' = [s \in Server |->
                               IF s \in rs THEN FALSE ELSE newLeaderAcked[s]]
       /\ zkState' = [s \in Server |-> IF s \in rs THEN "off" ELSE zkState[s]]
       /\ leaderSummaryEpoch' =
            [s \in Server |->
               IF s = Node /\ EventName = "PeerRoleChanged" /\ nr[s] = "leading"
               THEN currentEpoch[s] ELSE leaderSummaryEpoch[s]]
       /\ l' = l + 1

(***************************************************************************)
(* Silent steps for uninstrumented leader-side Actions.                    *)
(***************************************************************************)
\* Leader.propose + startForwarding/forwarding of a proposal to a learner that
\* is still synchronizing (quorum/Leader.java:1225-1260, 1294-1330;
\* Learner.java:616-643).  Enabled only when the next event logs a proposal
\* that is not yet in the learner buffer.
SilentBufferProposal ==
    /\ l <= Len(TraceLog)
    /\ EventName = "ProposalQueued" /\ phase[Node] = "sync"
    /\ role[Node] = "following" /\ leaderOf[Node] \in Server
    /\ syncJustified[Node]
    /\ Len(queued[Node]) = Len(proposed[Node])
    /\ ~HasEntry(proposed[Node], TxnEntry)
    /\ acceptedEpoch[Node] = TxnEp
    /\ proposed' = [proposed EXCEPT ![Node] = Append(@, TxnEntry)]
    /\ usedTxn' = usedTxn \cup {TxnId}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, newLeaderVars, l>>
    /\ ResetRollback

\* Leader.tryToCommit for a proposal whose COMMIT the learner buffered during
\* synchronization (Learner.java:645-655); enabled only when the next event
\* hands that commit to the CommitProcessor.
SilentLeaderCommit ==
    /\ l <= Len(TraceLog)
    /\ EventName = "CommitDelivered" /\ phase[Node] = "sync"
    /\ ~commitCertified[TxnId]
    /\ HasEntry(proposed[Node], TxnEntry)
    /\ commitCertified' = [commitCertified EXCEPT ![TxnId] = TRUE]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    messages, syncMode, syncSource, syncJustified, usedTxn,
                    newLeaderVars, l>>
    /\ ResetRollback

\* An in-JVM peer restart (test MainThread.shutdown/start) creates a new
\* QuorumPeer that reloads its database; volatile state of the previous
\* instance is gone.  Represented by base!Crash immediately before the
\* traced reload, enabled only when the next event is that reload of a peer
\* that already took part in the trace.  Zab1_0Test fixtures never restart.
FreshPeer(s) ==
    /\ role[s] = "looking" /\ phase[s] = "election"
    /\ durable[s] = <<>> /\ acceptedEpoch[s] = 0 /\ currentEpoch[s] = 0
SilentCrashBeforeReload ==
    /\ l <= Len(TraceLog)
    /\ EventName = "PeerDatabaseLoaded"
    /\ ~IsFixture
    /\ up[Node] /\ ~FreshPeer(Node)
    /\ Crash(Node)
    /\ UNCHANGED l

(***************************************************************************)
(* Post-state validation.                                                  *)
(***************************************************************************)
ValidateCommonPostState ==
    /\ IF St.acceptedEpoch >= 0
          THEN acceptedEpoch'[Node] = St.acceptedEpoch
          ELSE TRUE
    /\ IF St.currentEpoch >= 0
          THEN currentEpoch'[Node] = St.currentEpoch
          ELSE TRUE
    /\ IF St.role /= "unknown"
          THEN role'[Node] = TraceRole(St.role)
          ELSE TRUE
    /\ IF St.phase /= "unknown"
          THEN phase'[Node] = TracePhase(St.phase)
          ELSE TRUE
    \* Generic ZooKeeperServer probes hard-code syncMode NONE and do not read
    \* the peer; the mode is validated wherever the peer state is captured.
    /\ IF St.role /= "unknown"
          THEN syncMode'[Node] = St.syncMode
          ELSE TRUE

SyncLeader ==
    IF syncSource[Node] \in Server THEN syncSource[Node]
    ELSE IF Cardinality(Leading(role)) = 1
         THEN CHOOSE x \in Leading(role) : TRUE
         ELSE Node

ValidateEventPostState ==
    \* FastLeaderElection.setPeerState emits proposedZxid, the zxid of the
    \* winning vote (FastLeaderElection.java:898-901): for a learner it names
    \* the elected leader's last logged position, not the learner's own.
    \* Peer probes report getLastLoggedZxid() = the in-memory database's
    \* lastProcessedZxid (QuorumPeer.java:1257-1262) -> `recovered`.
    CASE EventName = "ElectionWon" /\ role'[Node] /= "leading" /\ TxnId /= 0 ->
           \E x \in Server : ZxidMatches(recovered'[x])
      [] EventName \in {"PeerRoleChanged", "ElectionWon", "PhaseChanged"} ->
           IF TxnId = 0
           THEN TxnEp <= acceptedEpoch'[Node]
           ELSE ZxidMatches(recovered'[Node])
      [] EventName = "PeerDatabaseLoaded" ->
           /\ up'[Node]
           /\ ZxidMatches(recovered'[Node])
           /\ ZxidMatches(durable'[Node])
      [] EventName = "AcceptedEpochPersisted" ->
           acceptedEpoch'[Node] = TxnEp
      [] EventName = "CurrentEpochPersisted" ->
           currentEpoch'[Node] = TxnEp
      [] EventName = "FollowerRegistered" ->
           ZxidMatches(recovered'[Node])
      [] EventName = "SyncModeChanged" ->
           TxnId = 0 \/ ZxidMatches(recovered'[Node])
      \* The Zab1_0Test DIFF fixture names the DIFF zxid of an unrelated
      \* database (Zab1_0Test.java:721-755) and sends only (1,2); its directive
      \* zxid is not a position of the history it transfers.
      [] EventName = "SyncSelected" ->
           /\ syncJustified'[Node]
           /\ IF TraceScenario = "follower-diff" THEN TRUE
              ELSE ZxidMatches(recovered'[SyncLeader])
      [] EventName = "SnapshotInstalled" ->
           /\ ZxidMatches(snapshot'[Node])
           /\ ZxidMatches(durable'[Node])
      [] EventName = "NewLeaderAckSent" ->
           /\ newLeaderAcked'[Node]
           /\ TxnId = 0 /\ TxnEp = acceptedEpoch'[Node]
           /\ Len(queued'[Node]) = Len(proposed'[Node])
      [] EventName = "NewLeaderAckCounted" ->
           /\ Peer \in nlAcks'[Node]
           /\ TxnId = 0 /\ TxnEp = acceptedEpoch'[Node]
      [] EventName = "NewLeaderAckMismatch" ->
           Peer \notin nlAcks'[Node]
      \* The data-tree position reported right after startServing is the
      \* learner's in-memory database, now served as its applied prefix.
      [] EventName = "BroadcastReady" ->
           /\ zkState'[Node] = "running"
           /\ ZxidMatches(recovered'[Node])
           /\ ZxidMatches(applied'[Node])
      [] EventName = "ProposalQueued" ->
           /\ HasEntry(proposed'[Node], TxnEntry)
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
    \/ /\ \/ ActionStep \/ ObservedStep
       /\ ValidateCommonPostState
       /\ ValidateEventPostState
    \/ SilentBufferProposal
    \/ SilentLeaderCommit
    \/ SilentCrashBeforeReload

TraceInit ==
    /\ l = 1
    /\ up = [s \in Server |-> TRUE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ newLeaderAcked = [s \in Server |-> FALSE]
    /\ IF IsFixture
       THEN
         LET leader == "s1" IN
         LET follower == "s0" IN
         \* testNormalFollowerRun: SNAP of a database holding (1,1);
         \* testNormalFollowerRunWithDiff: DIFF that transfers only (1,2).
         LET seed == IF TraceScenario = "follower-diff"
                     THEN <<EntryFor(2, 1)>> ELSE <<EntryFor(1, 1)>> IN
         LET seedTxn == IF TraceScenario = "follower-diff" THEN 2 ELSE 1 IN
         /\ role = [s \in Server |-> IF s = leader THEN "leading" ELSE "following"]
         \* "We are simulating an established leader, so the epoch is 1"
         \* (Zab1_0Test.java:603, 736).
         /\ phase = [s \in Server |-> IF s = follower THEN "discovery" ELSE "broadcast"]
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
         /\ acked = [t \in Txn |-> IF t = seedTxn THEN Server ELSE {}]
         /\ commitCertified = [t \in Txn |-> t = seedTxn]
         /\ messages = {}
         /\ syncMode = [s \in Server |-> "NONE"]
         /\ syncSource = [s \in Server |-> Nil]
         /\ syncJustified = [s \in Server |-> s /= follower]
         /\ usedTxn = {seedTxn}
         /\ rollbackAuthorized = [s \in Server |-> FALSE]
         /\ zkState = [s \in Server |-> IF s = follower THEN "off" ELSE "running"]
         /\ leaderSummaryEpoch = [s \in Server |-> 0]
       ELSE
         /\ Init

TraceSpec == TraceInit /\ [][TraceNext]_traceAllVars
                         /\ WF_traceAllVars(TraceNext)

\* REQ-EVIDENCE TraceMatched
\* intent:   Trace validation eventually consumes every record of the selected trace, i.e. the whole trace is accepted by the model.
\* status:   model-internal
\* watch:    none in source/ (the trace files and the probes that emit these events are not part of this revision)
\* verified: update
\* review:   ok
TraceMatched == <>(l > Len(TraceLog))

\* Code-observation evidence for Update!UpdNewLeaderAckAfterDurable and
\* Update!UpdEstablishedHistoryDurableOnQuorum evaluated on real executions
\* (same formulas; Trace extends base, not MC, so they are restated here).
\* Used only by Trace-update-evidence.cfg, never by the conformance gate.
TraceUpdNewLeaderAckAfterDurable ==
    [][\A s \in Server :
         (~newLeaderAcked[s] /\ newLeaderAcked'[s]) => IsPrefix(proposed[s], durable[s])
      ]_traceAllVars

TraceUpdEstablishedHistoryDurableOnQuorum ==
    \A ld \in {x \in Server : up[x] /\ role[x] = "leading" /\ phase[x] = "broadcast"} :
        Cardinality({s \in Server : IsPrefix(committed[ld], durable[s])}) >= Quorum

=============================================================================
