------------------------------ MODULE Trace ------------------------------
(***************************************************************************)
(* Trace validation for the updated reference.  Every NDJSON event either  *)
(* FIRES the base Action it instruments (with post- or pre-state field     *)
(* checks according to the probe's capture point) or is a CHECK-only      *)
(* observation of an Action that already fired in the same learner/leader *)
(* step.  Silent steps are restricted to: FLE votes (CastVote, not         *)
(* instrumented), the test-fixture leader of Zab1_0Test-style              *)
(* conversations (not implementation code), and "early" firing of an       *)
(* Action whose post-probe was serialized after a dependent probe of       *)
(* another thread (probe-ordering race; the later probe is then CHECK).    *)
(***************************************************************************)
EXTENDS base, Json, IOUtils, Sequences, TLC

JsonFile == IF "JSON" \in DOMAIN IOEnv
            THEN IOEnv.JSON
            ELSE "../traces/follower-diff.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x : "tag" \in DOMAIN x /\ x.tag = "trace"))

TraceScenario == TraceLog[1].scenario

FixtureScenarios == {"follower-snap", "follower-diff",
                     "diff-commit-after-newleader", "diff-ack-before-newleader-ack"}
IsFixture == TraceScenario \in FixtureScenarios
FixtureFollower == "s0"
FixtureLeader == "s1"

\* Constant overrides (Trace.cfg): Server <- TraceServers, Txn <- TraceTxns
TraceServers ==
    IF IsFixture THEN {FixtureFollower, FixtureLeader}
    ELSE {TraceLog[k].event.node : k \in 1..Len(TraceLog)} \ {"s-1"}
TraceTxns ==
    {<<TraceLog[k].event.txnEpoch, TraceLog[k].event.txnCounter>> :
        k \in {j \in 1..Len(TraceLog) : TraceLog[j].event.txnCounter > 0}}

EventNames == {
    "PeerRoleChanged", "ElectionWon", "PhaseChanged", "AcceptedEpochPersisted",
    "FollowerRegistered", "CurrentEpochPersisted", "LeaderSyncQueued",
    "NewLeaderQueued", "SyncModeChanged", "SyncSelected", "SnapshotInstalled",
    "LearnerSyncProposal", "LearnerSyncCommit", "NewLeaderReceived",
    "NewLeaderAckSent", "NewLeaderAckRead", "UpToDateQueued",
    "UpToDateReceived", "BroadcastReady", "LeaderAckReceived", "LeaderProposed",
    "LeaderCommitted", "ProposalQueued", "CommitDelivered", "TxnAppended",
    "TxnDurable", "TxnApplied", "AckSent"}

TraceInputOK ==
    /\ Len(TraceLog) > 0
    /\ \A k \in 1..Len(TraceLog) :
         LET r == TraceLog[k] IN
         /\ {"tag", "scenario", "seq", "timeMillis", "timeNanos", "thread", "event"}
               \subseteq DOMAIN r
         /\ r.scenario = TraceScenario /\ r.seq = k
         /\ {"name", "node", "peer", "info", "zxid", "txnEpoch", "txnCounter", "state"}
               \subseteq DOMAIN r.event
         /\ r.event.name \in EventNames
         /\ r.event.txnEpoch \in (-1)..MaxEpoch
         /\ {"acceptedEpoch", "currentEpoch", "role", "phase", "syncMode"}
               \subseteq DOMAIN r.event.state
         /\ r.event.state.syncMode \in SyncModes

ASSUME TraceInputOK

VARIABLE l
traceAllVars == <<allVars, l>>

logline == TraceLog[l]
Ev == logline.event
N == Ev.node
PeerN == Ev.peer
St == Ev.state
Ent == EntryFor(<<Ev.txnEpoch, Ev.txnCounter>>, Ev.txnEpoch)
IsName(nm) == l <= Len(TraceLog) /\ Ev.name = nm

Range(h) == {h[k] : k \in 1..Len(h)}
Last(h) == h[Len(h)]
ZxidMatches(h) ==
    IF Ev.txnCounter <= 0 THEN Len(h) = 0 \/ LastEpoch(h) <= MaxEpoch
    ELSE Len(h) > 0 /\ Last(h) = Ent

TraceRole(r) == CASE r = "following" -> "following"
                  [] r = "leading" -> "leading"
                  [] OTHER -> "looking"
TracePhase(p) == CASE p = "discovery" -> "discovery"
                   [] p = "synchronization" -> "sync"
                   [] p = "broadcast" -> "broadcast"
                   [] OTHER -> "election"

\* The Zab1_0Test fixture never changes the follower's public peer state.
RoleChecked(n) == ~(IsFixture /\ n = FixtureFollower)

\* Peer fields captured by the probe, compared with a chosen model state.
FieldsMatch(n, ae, ce, rl, ph, sm) ==
    /\ St.acceptedEpoch >= 0 => ae[n] = St.acceptedEpoch
    /\ St.currentEpoch >= 0 => ce[n] = St.currentEpoch
    /\ (St.role /= "unknown" /\ RoleChecked(n)) => rl[n] = TraceRole(St.role)
    /\ St.phase /= "unknown" => ph[n] = TracePhase(St.phase)
    /\ St.role /= "unknown" => sm[n] = St.syncMode
VPost == FieldsMatch(N, acceptedEpoch', currentEpoch', role', phase', syncMode')
VPre == FieldsMatch(N, acceptedEpoch, currentEpoch, role, phase, syncMode)
\* FLE decision probes run before Zab DISCOVERY: the event's role is the
\* role the next ElectLeader/ElectFollow step assigns.
VProspectiveRole ==
    FieldsMatch(N, acceptedEpoch, currentEpoch,
                [role EXCEPT ![N] = TraceRole(St.role)], phase, syncMode)

Stutter == UNCHANGED allVars

AckHeadMatches(q) ==
    /\ q /= <<>>
    /\ IF Ev.txnCounter <= 0
       THEN Head(q).kind \in {"NLACK", "UTDACK"} /\ Head(q).epoch = Ev.txnEpoch
       ELSE Head(q) = FPkt("ACK", Ent, 0)

----------------------------------------------------------------------------
(* Event steps                                                             *)

OnPeerRoleChanged ==
    /\ IsName("PeerRoleChanged")
    /\ IF St.role = "looking"
       THEN IF role[N] /= "looking" THEN BeginElection(N) /\ VPost
            ELSE Stutter /\ VPre
       ELSE Stutter /\ VProspectiveRole

OnElectionWon ==
    /\ IsName("ElectionWon")
    /\ Stutter /\ VProspectiveRole

OnPhaseChanged ==
    /\ IsName("PhaseChanged")
    /\ CASE TracePhase(St.phase) = "election" ->
              IF role[N] /= "looking" THEN BeginElection(N) /\ VPost
              ELSE Stutter /\ VPre
         [] TracePhase(St.phase) = "discovery" ->
              IF St.role = "leading" THEN ElectLeader(N) /\ VPost
              ELSE \E c \in Server : ElectFollow(N, c) /\ VPost
         [] TracePhase(St.phase) = "sync" ->
              IF role[N] = "leading" THEN FinishDiscovery(N) /\ VPost
              ELSE EnterSyncPhase(N) /\ VPost
         [] TracePhase(St.phase) = "broadcast" ->
              IF role[N] = "leading"
              THEN IF phase[N] = "broadcast" THEN Stutter /\ VPre
                   ELSE LeaderBroadcast(N) /\ VPost
              ELSE EnterBroadcast(N) /\ VPost

OnAcceptedEpochPersisted ==
    /\ IsName("AcceptedEpochPersisted")
    /\ IF role[N] = "leading"
       THEN LeaderProposeEpoch(N) /\ VPost /\ acceptedEpoch'[N] = Ev.txnEpoch
       ELSE \* registerWithLeader persists the leader's epoch before ACKEPOCH;
            \* the Action fires at FollowerRegistered.
            /\ Stutter
            /\ leaderOf[N] \in Server
            /\ St.acceptedEpoch = leaderEpoch[leaderOf[N]]
            /\ Ev.txnEpoch = leaderEpoch[leaderOf[N]]
            /\ FieldsMatch(N, [acceptedEpoch EXCEPT ![N] = St.acceptedEpoch],
                           currentEpoch, role, phase, syncMode)

OnFollowerRegistered ==
    /\ IsName("FollowerRegistered")
    /\ AcceptEpoch(N) /\ VPost

OnCurrentEpochPersisted ==
    /\ IsName("CurrentEpochPersisted")
    /\ IF role[N] = "leading"
       THEN \* Leader.lead:658 precedes SYNCHRONIZATION (FinishDiscovery fires there)
            /\ Stutter
            /\ St.currentEpoch = leaderEpoch[N] /\ Ev.txnEpoch = leaderEpoch[N]
            /\ FieldsMatch(N, acceptedEpoch, [currentEpoch EXCEPT ![N] = St.currentEpoch],
                           role, phase, syncMode)
       ELSE \* inside the NEWLEADER step that already fired; the probe runs
            \* before setSyncMode(NONE) (Q/Learner.java:743-750), so the mode
            \* field is the pre-step mode (checked at the next SyncModeChanged)
            /\ Stutter /\ lstage[N] = "nlack"
            /\ currentEpoch[N] = Ev.txnEpoch
            /\ FieldsMatch(N, acceptedEpoch, currentEpoch, role, phase,
                           [syncMode EXCEPT ![N] = St.syncMode])
            /\ St.syncMode \in {"DIFF", "TRUNC", "SNAP"}

OnLeaderSyncQueued ==
    /\ IsName("LeaderSyncQueued")
    /\ LeaderSyncFollower(N, PeerN, Ev.info) /\ VPost

OnNewLeaderQueued ==
    /\ IsName("NewLeaderQueued")
    /\ IF lhState[PeerN] = "synced"
       THEN LeaderSendNewLeader(N, PeerN) /\ VPost
       ELSE Stutter /\ VPre /\ lhState[PeerN] \in {"nlsent", "waitstart", "running"}

OnSyncModeChanged ==
    /\ IsName("SyncModeChanged")
    /\ IF St.syncMode /= "NONE"
       THEN LearnerReadMode(N) /\ VPost
       ELSE Stutter /\ VPre

OnSyncSelected ==
    /\ \/ IsName("SyncSelected") \/ IsName("SnapshotInstalled")
    /\ Stutter /\ VPre
    /\ lstage[N] = "pre"
    /\ syncMode[N] \in {"SNAP", "TRUNC"} => ZxidMatches(syncBase[N])

OnLearnerSyncProposal ==
    /\ IsName("LearnerSyncProposal")
    /\ LearnerSyncProposal(N) /\ VPost
    /\ Last(pendingNC'[N]) = Ent

OnLearnerSyncCommit ==
    /\ IsName("LearnerSyncCommit")
    /\ lq[N] /= <<>> /\ Head(lq[N]).ent = Ent
    /\ LearnerSyncCommit(N) /\ VPre

OnNewLeaderReceived ==
    /\ IsName("NewLeaderReceived")
    /\ Ev.txnEpoch = acceptedEpoch[N]
    /\ LearnerNewLeader(N) /\ VPre

OnNewLeaderAckSent ==
    /\ IsName("NewLeaderAckSent")
    /\ IF lstage[N] = "nlack"
       THEN LearnerAckNewLeader(N) /\ VPost
       ELSE Stutter /\ VPre /\ lstage[N] \in {"post", "done"}

OnNewLeaderAckRead ==
    /\ IsName("NewLeaderAckRead")
    /\ AckHeadMatches(fq[PeerN])
    /\ LeaderReadNewLeaderAck(N, PeerN) /\ VPost

OnUpToDateQueued ==
    /\ IsName("UpToDateQueued")
    /\ IF lhState[PeerN] = "waitstart"
       THEN LeaderSendUpToDate(N, PeerN) /\ VPost
       ELSE Stutter /\ VPre /\ lhState[PeerN] = "running"

OnUpToDateReceived ==
    /\ IsName("UpToDateReceived")
    /\ LearnerUpToDate(N) /\ VPre

OnBroadcastReady ==
    /\ IsName("BroadcastReady")
    /\ Stutter /\ VPre /\ lstage[N] = "done" /\ zkState[N] = "running"
    /\ ZxidMatches(applied[N])

OnLeaderAckReceived ==
    /\ IsName("LeaderAckReceived")
    /\ IF AckHeadMatches(fq[PeerN])
       THEN LeaderProcessAck(N, PeerN) /\ VPost
       ELSE \* processed early (SilentProcessAck): the probe follows
            \* processAck, whose tryToCommit emitted LeaderCommitted first
            Stutter /\ VPre /\ Ev.txnCounter > 0 /\ PeerN \in acked[Ent.id]

OnLeaderProposed ==
    /\ IsName("LeaderProposed")
    /\ IF Ent.id \notin usedTxn
       THEN Propose(N, Ent.id) /\ VPost /\ Last(queued'[N]) = Ent
       ELSE Stutter /\ VPre /\ Ent \in Range(queued[N])

OnLeaderCommitted ==
    /\ IsName("LeaderCommitted")
    /\ IF Ent \notin Range(committed[N])
       THEN Commit(N) /\ VPost /\ Last(committed'[N]) = Ent
       ELSE Stutter /\ VPre

OnProposalQueued ==
    /\ IsName("ProposalQueued")
    /\ IF lstage[N] = "done" /\ phase[N] = "broadcast"
       THEN ReceiveProposal(N) /\ VPost /\ Last(queued'[N]) = Ent
       ELSE \* fzk.logRequest inside the NEWLEADER / UPTODATE step
            Stutter /\ VPre /\ lstage[N] \in {"nlack", "done"}
            /\ Ent \in Range(queued[N]) /\ Ent \in Range(pendingTxns[N]) \cup Range(committed[N])

OnCommitDelivered ==
    /\ IsName("CommitDelivered")
    /\ IF /\ lstage[N] = "done" /\ phase[N] = "broadcast"
          /\ lq[N] /= <<>> /\ Head(lq[N]) = LPkt("COMMIT", Ent, <<>>, 0)
       THEN ReceiveCommit(N) /\ VPost /\ Last(committed'[N]) = Ent
       ELSE \* UPTODATE fold, or handed to the CommitProcessor early (the
            \* probe follows commitProcessor.commit; SilentReceiveCommit)
            Stutter /\ VPre /\ lstage[N] = "done" /\ Ent \in Range(committed[N])

OnTxnAppended ==
    /\ IsName("TxnAppended")
    /\ AppendOne(N) /\ Last(appended'[N]) = Ent

OnTxnDurable ==
    /\ IsName("TxnDurable")
    /\ FsyncOne(N) /\ Last(durable'[N]) = Ent

OnTxnApplied ==
    /\ IsName("TxnApplied")
    /\ ApplyOne(N) /\ Last(applied'[N]) = Ent

\* SendAckRequestProcessor probe (SyncThread, after writePacket): the ACK of
\* this durable entry was produced by FsyncOne; the peer fields are read
\* concurrently by another thread and are not compared.
OnAckSent ==
    /\ IsName("AckSent")
    /\ Stutter
    /\ Ent \in Range(durable[N])
    /\ (IsFixture /\ lstage[N] /= "none") => FPkt("ACK", Ent, 0) \in Range(fq[N])

EventStep ==
    \/ OnPeerRoleChanged \/ OnElectionWon \/ OnPhaseChanged
    \/ OnAcceptedEpochPersisted \/ OnFollowerRegistered \/ OnCurrentEpochPersisted
    \/ OnLeaderSyncQueued \/ OnNewLeaderQueued \/ OnSyncModeChanged \/ OnSyncSelected
    \/ OnLearnerSyncProposal \/ OnLearnerSyncCommit \/ OnNewLeaderReceived
    \/ OnNewLeaderAckSent \/ OnNewLeaderAckRead \/ OnUpToDateQueued
    \/ OnUpToDateReceived \/ OnBroadcastReady \/ OnLeaderAckReceived
    \/ OnLeaderProposed \/ OnLeaderCommitted \/ OnProposalQueued
    \/ OnCommitDelivered \/ OnTxnAppended \/ OnTxnDurable \/ OnTxnApplied
    \/ OnAckSent

----------------------------------------------------------------------------
(* Silent steps (do not consume an event)                                  *)

ElectionEventNext ==
    /\ l <= Len(TraceLog)
    /\ \/ Ev.name \in {"PeerRoleChanged", "ElectionWon"}
       \/ Ev.name = "PhaseChanged" /\ TracePhase(St.phase) = "discovery"
    /\ St.role \in {"leading", "following"}

\* The peer that the trace shows becoming LEADING in the current election
\* (lookahead to the first leading role/phase probe at or after l).
TargetCandidate ==
    LET K == {k \in l..Len(TraceLog) :
                /\ TraceLog[k].event.name \in {"PeerRoleChanged", "ElectionWon", "PhaseChanged"}
                /\ TraceLog[k].event.state.role = "leading"}
    IN IF K = {} THEN Nil
       ELSE TraceLog[CHOOSE k \in K : \A j \in K : k <= j].event.node

\* FLE notifications are not instrumented: votes for the candidate that the
\* trace shows winning (any voter that the reference allows).
SilentVote ==
    /\ ElectionEventNext
    /\ TargetCandidate \in Server
    /\ \E v \in Server : CastVote(v, TargetCandidate)

\* Probe-ordering races (post-probe of an Action serialized after a probe
\* of another thread that depends on it).
SilentAckNewLeader ==
    /\ IsName("NewLeaderAckRead") /\ Ev.txnCounter = 0
    /\ PeerN \in Server /\ lstage[PeerN] = "nlack" /\ fq[PeerN] = <<>>
    /\ LearnerAckNewLeader(PeerN)

SilentLeaderBroadcast ==
    /\ \/ IsName("UpToDateQueued") /\ N \in Server /\ phase[N] = "sync"
          /\ LeaderBroadcast(N)
       \/ IsName("UpToDateReceived") /\ leaderOf[N] \in Server
          /\ phase[leaderOf[N]] = "sync" /\ LeaderBroadcast(leaderOf[N])

SilentSendUpToDate ==
    /\ IsName("UpToDateReceived") /\ N \in Server
    /\ lq[N] = <<>> /\ lhState[N] = "waitstart" /\ leaderOf[N] \in Server
    /\ LeaderSendUpToDate(leaderOf[N], N)

SilentSendNewLeader ==
    /\ IsName("NewLeaderReceived") /\ N \in Server
    /\ lq[N] = <<>> /\ lhState[N] = "synced" /\ leaderOf[N] \in Server
    /\ LeaderSendNewLeader(leaderOf[N], N)

SilentPropose ==
    /\ IsName("ProposalQueued") /\ N \in Server
    /\ lstage[N] = "done" /\ phase[N] = "broadcast" /\ leaderOf[N] \in Server
    /\ Ent.id \notin usedTxn
    /\ Propose(leaderOf[N], Ent.id)

\* LearnerHandler ACK probe is emitted after Leader.processAck returned;
\* the commit it triggers (tryToCommit -> commit) is probed inside.
\* Also needed when a learner's COMMIT probe precedes the leader's probes.
CommitLeader ==
    IF IsName("LeaderCommitted") THEN N
    ELSE IF IsName("CommitDelivered") /\ N \in Server THEN leaderOf[N] ELSE Nil
SilentProcessAck ==
    /\ CommitLeader \in Server
    /\ Ent \notin Range(committed[CommitLeader])
    /\ \E s \in Server :
         /\ lhState[s] = "running" /\ leaderOf[s] = CommitLeader /\ fq[s] /= <<>>
         /\ Head(fq[s]) = FPkt("ACK", Ent, 0)
         /\ LeaderProcessAck(CommitLeader, s)

\* FollowerZooKeeperServer.commit probes after commitProcessor.commit; the
\* CommitProcessor thread may apply (TxnApplied) before that probe.
SilentReceiveCommit ==
    /\ IsName("TxnApplied") /\ N \in Server
    /\ role[N] = "following" /\ phase[N] = "broadcast" /\ lstage[N] = "done"
    /\ Ent \notin Range(committed[N])
    /\ lq[N] /= <<>> /\ Head(lq[N]) = LPkt("COMMIT", Ent, <<>>, 0)
    /\ ReceiveCommit(N)

SilentCommit ==
    /\ IsName("CommitDelivered") /\ N \in Server
    /\ lstage[N] = "done" /\ phase[N] = "broadcast" /\ leaderOf[N] \in Server
    /\ ~(lq[N] /= <<>> /\ Head(lq[N]).type = "COMMIT")
    /\ Commit(leaderOf[N])

FixtureSnapHist ==
    LET K == {k \in 1..Len(TraceLog) : TraceLog[k].event.name = "SnapshotInstalled"}
    IN IF K = {} THEN <<>>
       ELSE LET r == TraceLog[CHOOSE k \in K : \A j \in K : k <= j].event IN
            IF r.txnCounter <= 0 THEN <<>>
            ELSE <<EntryFor(<<r.txnEpoch, r.txnCounter>>, r.txnEpoch)>>

\* Test-fixture leader (Zab1_0Test conversation): supplies exactly the packet
\* the next learner event consumes, and certifies the commits it sends.
FixtureSend ==
    /\ IsFixture /\ l <= Len(TraceLog) /\ N = FixtureFollower
    /\ lq[N] = <<>>
    /\ LET pkt ==
           CASE Ev.name = "SyncModeChanged" /\ St.syncMode = "SNAP" ->
                  LPkt("SNAP", NoEntry, FixtureSnapHist, 0)
             [] Ev.name = "SyncModeChanged" /\ St.syncMode = "DIFF" ->
                  LPkt("DIFF", NoEntry, <<>>, 0)
             [] Ev.name = "LearnerSyncProposal" -> LPkt("PROPOSAL", Ent, <<>>, 0)
             [] Ev.name = "LearnerSyncCommit" -> LPkt("COMMIT", Ent, <<>>, 0)
             [] Ev.name = "NewLeaderReceived" -> LPkt("NEWLEADER", NoEntry, <<>>, Ev.txnEpoch)
             [] Ev.name = "UpToDateReceived" -> LPkt("UPTODATE", NoEntry, <<>>, 0)
             [] OTHER -> LPkt("NONE", NoEntry, <<>>, 0)
       IN /\ pkt.type /= "NONE"
          /\ lq' = [lq EXCEPT ![N] = <<pkt>>]
          /\ commitCertified' =
                CASE pkt.type = "COMMIT" -> [commitCertified EXCEPT ![Ent.id] = TRUE]
                  [] pkt.type = "SNAP" ->     \* a leader snapshot is committed state
                       [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(pkt.hist)]
                  [] OTHER -> commitCertified
    /\ UNCHANGED <<up, electionVars, logVars, learnerVars, lhState, newLeaderAcks,
                    fq, acked, usedTxn, rollbackAuthorized, ghostVars>>

SilentStep ==
    \/ SilentVote \/ SilentAckNewLeader \/ SilentLeaderBroadcast
    \/ SilentSendUpToDate \/ SilentSendNewLeader \/ SilentPropose \/ SilentCommit
    \/ SilentProcessAck \/ SilentReceiveCommit
    \/ FixtureSend

----------------------------------------------------------------------------
TraceInit ==
    /\ l = 1
    /\ IF IsFixture
       THEN \* Zab1_0Test fixture: an established epoch-1 leader process s1
            /\ up = [s \in Server |-> TRUE]
            /\ role = [s \in Server |-> IF s = FixtureLeader THEN "leading" ELSE "looking"]
            /\ phase = [s \in Server |-> IF s = FixtureLeader THEN "broadcast" ELSE "election"]
            /\ leaderOf = [s \in Server |-> IF s = FixtureLeader THEN s ELSE Nil]
            /\ acceptedEpoch = [s \in Server |-> IF s = FixtureLeader THEN 1 ELSE 0]
            /\ currentEpoch = [s \in Server |-> IF s = FixtureLeader THEN 1 ELSE 0]
            /\ votes = [s \in Server |-> {}]
            /\ leaderEpoch = [s \in Server |-> IF s = FixtureLeader THEN 1 ELSE 0]
            /\ epochAcks = [s \in Server |-> {}]
            /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {FixtureLeader} ELSE {}]
            /\ queued = [s \in Server |-> <<>>]
            /\ appended = [s \in Server |-> <<>>]
            /\ durable = [s \in Server |-> <<>>]
            /\ committed = [s \in Server |-> <<>>]
            /\ applied = [s \in Server |-> <<>>]
            /\ pendingTxns = [s \in Server |-> <<>>]
            /\ syncBase = [s \in Server |-> <<>>]
            /\ pendingNC = [s \in Server |-> <<>>]
            /\ pendingC = [s \in Server |-> <<>>]
            /\ lstage = [s \in Server |-> "none"]
            /\ writeToTxnLog = [s \in Server |-> FALSE]
            /\ zkState = [s \in Server |-> IF s = FixtureLeader THEN "running" ELSE "stopped"]
            /\ syncMode = [s \in Server |-> "NONE"]
            /\ syncJustified = [s \in Server |-> FALSE]
            /\ lhState = [s \in Server |-> "none"]
            /\ newLeaderAcks = [s \in Server |-> {}]
            /\ lq = [s \in Server |-> <<>>]
            /\ fq = [s \in Server |-> <<>>]
            /\ acked = [t \in Txn |-> {}]
            /\ commitCertified = [t \in Txn |-> FALSE]
            /\ usedTxn = {}
            /\ rollbackAuthorized = [s \in Server |-> FALSE]
            /\ globalCommitted = {}
            /\ nlAckMisread = [s \in Server |-> FALSE]
            /\ syncNPE = [s \in Server |-> FALSE]
            /\ unmatchedCommit = [s \in Server |-> FALSE]
       ELSE Init

TraceNext ==
    \/ /\ l <= Len(TraceLog)
       /\ EventStep
       /\ l' = l + 1
    \/ /\ l <= Len(TraceLog)
       /\ SilentStep
       /\ UNCHANGED l

TraceSpec == TraceInit /\ [][TraceNext]_traceAllVars

\* Existential completion (replay is nondeterministic only through silent
\* votes / follower-leader choice / early firing): TLC checks temporal
\* properties after generating all successors of a state; if the BFS queue
\* drains while every explored state still has l <= Len, no behavior of the
\* reference consumes the whole trace.  Run with -workers 1.
TraceMatched ==
    [](l <= Len(TraceLog) => [](TLCGet("queue") > 0 \/ l > Len(TraceLog)))

\* Witness formulation: a violation of this invariant is a reference
\* behavior that consumed every event with all checks active.
TraceIncomplete == l <= Len(TraceLog)

\* Votes of a non-LOOKING peer cannot enable any Action (ElectLeader needs a
\* LOOKING candidate; ElectFollow toward a LEADING peer uses the join path;
\* RoleExit resets the vote set), so they are masked in the VIEW.
TraceView == <<l, up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
               [c \in Server |-> IF role[c] = "looking" THEN votes[c] ELSE {}],
               leaderEpoch, epochAcks, leadersByEpoch, logVars, learnerVars,
               handlerVars, commitVars, rollbackAuthorized, ghostVars>>

\* Debug aid: TLCGet("level") / l in the failure output.
TraceAlias == [l |-> l, event |-> IF l <= Len(TraceLog) THEN TraceLog[l].event ELSE "done",
               role |-> role, phase |-> phase, lstage |-> lstage, lhState |-> lhState,
               lq |-> lq, fq |-> fq, durable |-> durable, queued |-> queued,
               committed |-> committed, applied |-> applied, pendingNC |-> pendingNC,
               pendingTxns |-> pendingTxns, votes |-> votes]

=============================================================================
