------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* ZooKeeper Zab reference model for the UPDATED source revision           *)
(* (artifact commit 2efbdfc, "update").                                    *)
(*                                                                         *)
(* Source paths are relative to zookeeper-server/src/main/java/org/apache/ *)
(* zookeeper/server/ in the updated tree.  Q/ abbreviates quorum/.         *)
(*                                                                         *)
(* Granularity (see ../update-analysis.md):                                *)
(*  - election/discovery: FLE vote, leader/follower decision, epoch        *)
(*    proposal (getEpochToPropose), registration (registerWithLeader),     *)
(*    epoch establishment (waitForEpochAck);                               *)
(*  - synchronization: the leader's LearnerHandler queue (lq) and the      *)
(*    learner's reply stream (fq) are FIFO TCP streams; every sync packet  *)
(*    the learner consumes is a separate step; the learner's in-memory     *)
(*    packetsNotCommitted / packetsCommitted buffers are explicit;         *)
(*  - follower/leader request pipelines: enqueue (queued), append          *)
(*    (appended, not forced), fsync (durable, then ACK), commit, apply.    *)
(*  durable[s] is the history that FileTxnSnapLog.restore would rebuild    *)
(*  (snapshot + forced log).                                               *)
(***************************************************************************)
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

CONSTANTS Server, Txn, MaxEpoch, Nil

ASSUME /\ Server /= {}
       /\ Txn /= {}
       /\ MaxEpoch \in Nat \ {0}
       /\ Nil \notin Server
       /\ Nil \notin Txn

Role == {"looking", "leading", "following"}
Phase == {"election", "discovery", "sync", "broadcast", "offline"}
SyncModes == {"NONE", "DIFF", "TRUNC", "SNAP"}
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
NoEntry == [id |-> Nil, epoch |-> 0]

\* Learner-side progress through Learner.registerWithLeader/syncWithLeader.
\*  none  : not registered with a leader
\*  reg   : ACKEPOCH written (Q/Learner.java:524-526)
\*  mode  : SYNCHRONIZATION phase entered, waiting for DIFF/TRUNC/SNAP
\*  pre   : sync loop before NEWLEADER (Q/Learner.java:619-711)
\*  nlack : NEWLEADER processed, NEWLEADER ACK not yet written (:740-759)
\*  post  : NEWLEADER ACK written, waiting for UPTODATE (:760-762)
\*  done  : UPTODATE processed and syncWithLeader returned (:764-786)
LStages == {"none", "reg", "mode", "pre", "nlack", "post", "done"}
\* Leader-side LearnerHandler progress for the connection of a learner.
LHStates == {"none", "synced", "nlsent", "waitstart", "running"}
\* ZooKeeperServer.state as relevant here (ZooKeeperServer.java:185-190).
ZkStates == {"stopped", "initial", "running"}

LTypes == {"DIFF", "TRUNC", "SNAP", "PROPOSAL", "COMMIT", "NEWLEADER", "UPTODATE"}
FKinds == {"NLACK", "UTDACK", "ACK"}

LPkt(t, e, h, ep) == [type |-> t, ent |-> e, hist |-> h, epoch |-> ep]
FPkt(k, e, ep) == [kind |-> k, ent |-> e, epoch |-> ep]

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES
    \* election / discovery
    up, role, phase, leaderOf, acceptedEpoch, currentEpoch, votes,
    leaderEpoch, epochAcks, leadersByEpoch,
    \* histories and pipelines
    queued, appended, durable, committed, applied, pendingTxns,
    \* learner synchronization state
    syncBase, pendingNC, pendingC, lstage, writeToTxnLog, zkState,
    syncMode, syncJustified,
    \* leader-side handlers and the two TCP streams per learner
    lhState, newLeaderAcks, lq, fq,
    \* commit bookkeeping
    acked, commitCertified, usedTxn,
    \* ghost / oracle state
    rollbackAuthorized, globalCommitted, nlAckMisread, syncNPE,
    unmatchedCommit

electionVars == <<role, phase, leaderOf, acceptedEpoch, currentEpoch, votes,
                  leaderEpoch, epochAcks, leadersByEpoch>>
logVars == <<queued, appended, durable, committed, applied, pendingTxns>>
learnerVars == <<syncBase, pendingNC, pendingC, lstage, writeToTxnLog,
                 zkState, syncMode, syncJustified>>
handlerVars == <<lhState, newLeaderAcks, lq, fq>>
commitVars == <<acked, commitCertified, usedTxn>>
ghostVars == <<globalCommitted, nlAckMisread, syncNPE, unmatchedCommit>>

allVars == <<up, electionVars, logVars, learnerVars, handlerVars, commitVars,
             rollbackAuthorized, ghostVars>>

----------------------------------------------------------------------------
(* Helpers *)

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
Suffix(h, n) == SubSeq(h, n + 1, Len(h))
MaxOf(S) == CHOOSE m \in S : \A x \in S : x <= m

\* zxid = (epoch, counter): the counter restarts at 1 in every epoch, so the
\* last zxid of a history is its last epoch and the number of its entries in
\* that epoch (ZxidUtils.makeZxid; Leader.lead sets (epoch, 0) at start).
ZxidOf(h) == <<LastEpoch(h),
               Cardinality({k \in 1..Len(h) : h[k].epoch = LastEpoch(h)})>>
ZxidGEq(a, b) == a[1] > b[1] \/ (a[1] = b[1] /\ a[2] >= b[2])
ZxidGT(a, b) == a[1] > b[1] \/ (a[1] = b[1] /\ a[2] > b[2])

\* Longest common prefix.
LCP(a, b) ==
    LET K == {k \in 0..Len(a) : k <= Len(b) /\ SubSeq(a, 1, k) = SubSeq(b, 1, k)}
    IN SubSeq(a, 1, MaxOf(K))

\* PROPOSAL+COMMIT pairs for committed proposals (LearnerHandler
\* queueCommittedProposals:1018-1021; Leader.startForwarding toBeApplied).
PC(h) == [i \in 1..(2 * Len(h)) |->
            IF i % 2 = 1 THEN LPkt("PROPOSAL", h[(i + 1) \div 2], <<>>, 0)
                         ELSE LPkt("COMMIT", h[i \div 2], <<>>, 0)]
\* PROPOSAL-only packets for outstanding proposals (Leader.startForwarding).
P(h) == [i \in 1..Len(h) |-> LPkt("PROPOSAL", h[i], <<>>, 0)]

\* Replace f[x] by v for every x in S.
SetAll(f, S, v) == [x \in DOMAIN f |-> IF x \in S THEN v ELSE f[x]]

\* The TCP connections that die when s leaves its role: a leader takes down
\* every LearnerHandler (Leader.shutdown), a learner its own connection.
Links(s) == IF role[s] = "leading" THEN {x \in Server : leaderOf[x] = s}
            ELSE {s}

\* Learners the leader forwards to (Leader.forwardingFollowers, added by
\* startForwarding inside LearnerHandler.syncFollower:920).
Forwarding(l) == {x \in Server : x /= l /\ leaderOf[x] = l /\ lhState[x] /= "none"}

\* LearnerMaster DB view used by LearnerHandler.syncFollower:788-923.
\* A leader that has not started serving uses the database loaded by
\* Leader.lead -> loadData (Leader.java:593), i.e. its whole recoverable log;
\* afterwards the committed log.  Outstanding proposals exist only after start.
LeaderHist(l) == IF phase[l] = "broadcast" THEN committed[l] ELSE durable[l]
LeaderSnapHist(l) == IF phase[l] = "broadcast" THEN applied[l] ELSE durable[l]
LeaderOutstanding(l) ==
    IF phase[l] = "broadcast" THEN Suffix(queued[l], Len(committed[l]))
    ELSE <<>>
InOutstanding(l, e) ==
    \E k \in (Len(committed[l]) + 1)..Len(queued[l]) : queued[l][k] = e

\* FLE totalOrderPredicate (FastLeaderElection.java:722-746): peer epoch,
\* then last zxid; the server-id tie break is left nondeterministic.
HistoryAtLeast(c, v) ==
    \/ currentEpoch[c] > currentEpoch[v]
    \/ /\ currentEpoch[c] = currentEpoch[v]
       /\ ZxidGEq(ZxidOf(durable[c]), ZxidOf(durable[v]))

\* StateSummary.isMoreRecentThan (Leader.waitForEpochAck:1448).
MoreRecent(s, l) ==
    \/ currentEpoch[s] > currentEpoch[l]
    \/ /\ currentEpoch[s] = currentEpoch[l]
       /\ ZxidGT(ZxidOf(durable[s]), ZxidOf(durable[l]))

ResetRollback == rollbackAuthorized' = [s \in Server |-> FALSE]

----------------------------------------------------------------------------
Init ==
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> 0]
    /\ currentEpoch = [s \in Server |-> 0]
    /\ votes = [s \in Server |-> {}]
    /\ leaderEpoch = [s \in Server |-> 0]
    /\ epochAcks = [s \in Server |-> {}]
    /\ leadersByEpoch = [e \in Epoch |-> {}]
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
    /\ zkState = [s \in Server |-> "stopped"]
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

----------------------------------------------------------------------------
(* Role exit shared by BeginElection and the learner exception path.       *)
(* QuorumPeer.run finally-blocks call follower.shutdown()/leader.shutdown()*)
(* -> zk.shutdown(); for a RUNNING server LearnerZooKeeperServer.shutdown: *)
(* 155-173 (and the leader's ProposalRequestProcessor chain) shut the      *)
(* SyncRequestProcessor down, which drains and forces its queue            *)
(* (SyncRequestProcessor.java:254-271).  UPDATE: a learner that fails      *)
(* between NEWLEADER and UPTODATE is INITIAL; canShutdown() is false       *)
(* (ZooKeeperServer.java:784-786), so nothing is stopped: its leaked       *)
(* SyncThread keeps appending/forcing the enqueued entries later           *)
(* (AppendOne/FsyncOne stay enabled; its ACKs go to a closed socket).      *)
(* The in-memory data tree is retained (shutdown(false) fast-forwards it). *)
\* UPDATE-MAP
\* code: ZooKeeperServer.java:784-786 with Q/Learner.java:751 (INITIAL state)
\* update: Update!EnvLeave (open spec) and CR finding D-6
RoleExit(s, newPhase) ==
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = newPhase]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ leaderEpoch' = [leaderEpoch EXCEPT ![s] = 0]
    /\ epochAcks' = [epochAcks EXCEPT ![s] = {}]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![s] = {}]
    /\ durable' = [durable EXCEPT ![s] = IF zkState[s] = "running" THEN queued[s] ELSE @]
    /\ appended' = [appended EXCEPT ![s] = IF zkState[s] = "running" THEN queued[s] ELSE @]
    /\ pendingTxns' = [pendingTxns EXCEPT ![s] = <<>>]
    /\ syncBase' = [syncBase EXCEPT ![s] = <<>>]
    /\ pendingNC' = [pendingNC EXCEPT ![s] = <<>>]
    /\ pendingC' = [pendingC EXCEPT ![s] = <<>>]
    /\ lstage' = [lstage EXCEPT ![s] = "none"]
    /\ writeToTxnLog' = [writeToTxnLog EXCEPT ![s] = FALSE]
    /\ zkState' = [zkState EXCEPT ![s] = "stopped"]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ lq' = SetAll(lq, Links(s), <<>>)
    /\ fq' = SetAll(fq, Links(s), <<>>)
    /\ lhState' = SetAll(lhState, Links(s), "none")

(* QuorumPeer.run: a follower/leader gives up (socket error, ping/sync     *)
(* timeout, lost quorum: Leader.lead:760-790) or a looking peer starts a   *)
(* new FLE round (FastLeaderElection.lookForLeader:917-960).               *)
BeginElection(s) ==
    /\ up[s]
    /\ RoleExit(s, "election")
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    queued, committed, applied, commitVars, ghostVars>>
    /\ ResetRollback

(* FLE: voter adopts candidate's vote (FastLeaderElection.java:722-746,    *)
(* 1001-1027).                                                             *)
CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking" /\ role[candidate] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ voter \notin votes[candidate]
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leaderEpoch, epochAcks, leadersByEpoch, logVars,
                    learnerVars, handlerVars, commitVars, ghostVars>>
    /\ ResetRollback

(* FLE quorum decision -> LEADING (FastLeaderElection.java:1029-1047,      *)
(* setPeerState:898-905); Leader.lead sets DISCOVERY and loads data        *)
(* (Leader.java:591-593).                                                  *)
ElectLeader(c) ==
    /\ up[c] /\ role[c] = "looking"
    /\ c \in votes[c] /\ Cardinality(votes[c]) >= Quorum
    \* ENV ASSUMPTION (D-6 abstraction): a leaked SyncThread has forced its
    \* queue before this peer finishes an election (finalizeWait >= 200 ms).
    /\ queued[c] = durable[c]
    /\ role' = [role EXCEPT ![c] = "leading"]
    /\ phase' = [phase EXCEPT ![c] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![c] = c]
    /\ leaderEpoch' = [leaderEpoch EXCEPT ![c] = 0]
    /\ epochAcks' = [epochAcks EXCEPT ![c] = {}]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![c] = {}]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    logVars, learnerVars, lhState, lq, fq, commitVars,
                    ghostVars>>
    /\ ResetRollback

(* FLE decision -> FOLLOWING, either inside a vote quorum for c or by       *)
(* joining an established ensemble (out-of-election notifications from the *)
(* LEADING peer, FastLeaderElection.java:1061-1120).  Follower.followLeader*)
(* sets DISCOVERY before connecting (Q/Follower.java:83-85).               *)
ElectFollow(s, c) ==
    /\ up[s] /\ s /= c /\ role[s] = "looking"
    /\ \/ /\ s \in votes[c] /\ c \in votes[c]
          /\ Cardinality(votes[c]) >= Quorum
       \/ /\ up[c] /\ role[c] = "leading"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leaderEpoch,
                    epochAcks, leadersByEpoch, logVars, learnerVars,
                    handlerVars, commitVars, ghostVars>>
    /\ ResetRollback

(* Leader.getEpochToPropose:1396-1430: once a quorum (including the        *)
(* leader) has sent FOLLOWERINFO, epoch = max(lastAcceptedEpoch)+1 and the *)
(* leader persists it (QuorumPeer.setAcceptedEpoch: file then field).      *)
LeaderProposeEpoch(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ leaderEpoch[l] = 0
    /\ \E Q \in SUBSET ({l} \cup {x \in Server : up[x] /\ role[x] = "following"
                                              /\ leaderOf[x] = l
                                              /\ phase[x] = "discovery"}) :
         /\ l \in Q /\ Cardinality(Q) >= Quorum
         /\ LET ep == MaxOf({acceptedEpoch[x] : x \in Q}) + 1 IN
            /\ ep <= MaxEpoch
            /\ leaderEpoch' = [leaderEpoch EXCEPT ![l] = ep]
            /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![l] = ep]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes, epochAcks,
                    leadersByEpoch, logVars, learnerVars, handlerVars,
                    commitVars, ghostVars>>
    /\ ResetRollback

(* Learner.registerWithLeader:483-536 after LEADERINFO: persist a greater  *)
(* epoch, then write ACKEPOCH; an equal epoch is acknowledged with -1 and  *)
(* is not counted by Leader.waitForEpochAck:1446-1457; a more recent       *)
(* follower summary is not counted either (the handler throws).            *)
AcceptEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ lstage[s] = "none"
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ up[l] /\ role[l] = "leading" /\ leaderEpoch[l] /= 0
       /\ leaderEpoch[l] >= acceptedEpoch[s]
       /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = leaderEpoch[l]]
       /\ epochAcks' =
            IF leaderEpoch[l] > acceptedEpoch[s] /\ phase[l] = "discovery"
               /\ ~MoreRecent(s, l)
            THEN [epochAcks EXCEPT ![l] = @ \cup {s}]
            ELSE epochAcks
    /\ lstage' = [lstage EXCEPT ![s] = "reg"]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes, leaderEpoch,
                    leadersByEpoch, logVars, syncBase, pendingNC, pendingC,
                    writeToTxnLog, zkState, syncMode, syncJustified,
                    handlerVars, commitVars, ghostVars>>
    /\ ResetRollback

(* Leader.lead:657-660: waitForEpochAck quorum, setCurrentEpoch(epoch),    *)
(* setZabState(SYNCHRONIZATION).  leadersByEpoch records established       *)
(* epochs (ghost).                                                         *)
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ leaderEpoch[l] /= 0
    /\ Cardinality(epochAcks[l] \cup {l}) >= Quorum
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = leaderEpoch[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ leadersByEpoch' = [leadersByEpoch EXCEPT ![leaderEpoch[l]] = @ \cup {l}]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes, leaderEpoch,
                    epochAcks, logVars, learnerVars, handlerVars, commitVars,
                    ghostVars>>
    /\ ResetRollback

(* Q/Follower.java:96-97: setZabState(SYNCHRONIZATION) after                *)
(* registerWithLeader returned; syncWithLeader then blocks in readPacket.  *)
EnterSyncPhase(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ lstage[s] = "reg"
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ lstage' = [lstage EXCEPT ![s] = "mode"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leaderEpoch, epochAcks, leadersByEpoch, logVars, syncBase,
                    pendingNC, pendingC, writeToTxnLog, zkState, syncMode,
                    syncJustified, handlerVars, commitVars, ghostVars>>
    /\ ResetRollback

----------------------------------------------------------------------------
(* Leader side of synchronization: LearnerHandler.run                      *)

ModeAllowed(l, s, mode) ==
    CASE mode = "DIFF"  -> IsPrefix(durable[s], LeaderHist(l))
      [] mode = "TRUNC" -> ~IsPrefix(durable[s], LeaderHist(l))
      [] mode = "SNAP"  -> TRUE

SyncPackets(l, s, mode) ==
    LET H == LeaderHist(l)
        O == P(LeaderOutstanding(l))
    IN CASE mode = "DIFF" ->
              <<LPkt("DIFF", NoEntry, <<>>, 0)>> \o PC(Suffix(H, Len(durable[s]))) \o O
         [] mode = "TRUNC" ->
              LET T == LCP(durable[s], H) IN
              <<LPkt("TRUNC", NoEntry, T, 0)>> \o PC(Suffix(H, Len(T))) \o O
         [] mode = "SNAP" ->
              LET S == LeaderSnapHist(l) IN
              <<LPkt("SNAP", NoEntry, S, 0)>> \o PC(Suffix(H, Len(S))) \o O

(* LearnerHandler.run:547-583 + syncFollower:774-933 under the committed-   *)
(* log read lock: choose DIFF / TRUNC(+DIFF) / SNAP, queue the sync packets *)
(* and the outstanding proposals, register for forwarding                  *)
(* (Leader.startForwarding).  SNAP is chosen by the leader whenever the     *)
(* learner falls outside the retained committed log or TRUNC would cross an *)
(* epoch (queueCommittedProposals:994-998); the model keeps it always      *)
(* possible.  The handler reaches syncFollower only after waitForEpochAck   *)
(* returned (LearnerHandler.run:545).                                      *)
LeaderSyncFollower(l, s, mode) ==
    /\ up[l] /\ up[s] /\ s /= l
    /\ role[l] = "leading"
    \* waitForEpochAck returned for this handler: electingFinished (an
    \* ACKEPOCH quorum) -- the leader thread may not yet have run
    \* setCurrentEpoch/SYNCHRONIZATION (Leader.lead:657-660).
    /\ \/ phase[l] \in {"sync", "broadcast"}
       \/ /\ phase[l] = "discovery" /\ leaderEpoch[l] /= 0
          /\ Cardinality(epochAcks[l] \cup {l}) >= Quorum
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ lstage[s] \in {"reg", "mode"}
    /\ acceptedEpoch[s] = leaderEpoch[l]
    /\ phase[l] = "broadcast" \/ ~MoreRecent(s, l)
    /\ lhState[s] = "none" /\ lq[s] = <<>>
    \* ENV ASSUMPTION (D-6 abstraction): the learner's log is quiescent when
    \* the leader reads its last zxid (FOLLOWERINFO/ACKEPOCH).
    /\ queued[s] = durable[s]
    /\ mode \in {"DIFF", "TRUNC", "SNAP"}
    /\ ModeAllowed(l, s, mode)
    /\ lq' = [lq EXCEPT ![s] = SyncPackets(l, s, mode)]
    /\ lhState' = [lhState EXCEPT ![s] = "synced"]
    /\ UNCHANGED <<up, electionVars, logVars, learnerVars, newLeaderAcks, fq,
                    commitVars, ghostVars>>
    /\ ResetRollback

(* LearnerHandler.run:590-604: queue NEWLEADER (after syncFollower returned *)
(* and, for SNAP, after the snapshot was streamed).  Forwarded proposals or *)
(* commits may already be queued in between.                               *)
LeaderSendNewLeader(l, s) ==
    /\ up[l] /\ role[l] = "leading" /\ leaderOf[s] = l /\ s /= l
    /\ lhState[s] = "synced"
    /\ lq' = [lq EXCEPT ![s] = Append(@, LPkt("NEWLEADER", NoEntry, <<>>, leaderEpoch[l]))]
    /\ lhState' = [lhState EXCEPT ![s] = "nlsent"]
    /\ UNCHANGED <<up, electionVars, logVars, learnerVars, newLeaderAcks, fq,
                    commitVars, ghostVars>>
    /\ ResetRollback

(* LearnerHandler.run:609-623: read the FIRST packet after NEWLEADER; any   *)
(* ACK is handed to Leader.waitForNewLeaderAck:1547-1588, which counts it   *)
(* only when its zxid equals the NEWLEADER zxid (epoch,0) and otherwise    *)
(* logs "different epoch" and returns.  The handler then waits for the     *)
(* leader to start.  nlAckMisread is an oracle flag for the second branch. *)
LeaderReadNewLeaderAck(l, s) ==
    /\ up[l] /\ role[l] = "leading" /\ leaderOf[s] = l /\ s /= l
    /\ lhState[s] = "nlsent"
    /\ fq[s] /= <<>>
    /\ LET a == Head(fq[s]) IN
       IF a.kind = "NLACK" /\ a.epoch = leaderEpoch[l]
       THEN /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = @ \cup {s}]
            /\ UNCHANGED nlAckMisread
       ELSE /\ UNCHANGED newLeaderAcks
            /\ nlAckMisread' = [nlAckMisread EXCEPT ![s] = TRUE]
    /\ fq' = [fq EXCEPT ![s] = Tail(@)]
    /\ lhState' = [lhState EXCEPT ![s] = "waitstart"]
    /\ UNCHANGED <<up, electionVars, logVars, learnerVars, lq, commitVars,
                    globalCommitted, syncNPE, unmatchedCommit>>
    /\ ResetRollback

(* Leader.lead:663-712: NEWLEADER quorum (the leader counts itself),        *)
(* startZkServer, setZabState(BROADCAST).  The leader's loaded history     *)
(* (Leader.lead -> loadData) becomes its committed log; the NEWLEADER      *)
(* quorum is the commit certificate of that initial history.               *)
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ Cardinality(newLeaderAcks[l] \cup {l}) >= Quorum
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ zkState' = [zkState EXCEPT ![l] = "running"]
    /\ committed' = [committed EXCEPT ![l] = durable[l]]
    /\ applied' = [applied EXCEPT ![l] = durable[l]]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(durable[l])]
    /\ globalCommitted' = globalCommitted \cup
                           {<<k, durable[l][k]>> : k \in 1..Len(durable[l])}
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leaderEpoch, epochAcks, leadersByEpoch, queued, appended,
                    durable, pendingTxns, syncBase, pendingNC, pendingC, lstage,
                    writeToTxnLog, syncMode, syncJustified, handlerVars, acked,
                    usedTxn, nlAckMisread, syncNPE, unmatchedCommit>>
    /\ ResetRollback

(* LearnerHandler.run:637-648: waitForStartup, then queue UPTODATE.         *)
LeaderSendUpToDate(l, s) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ leaderOf[s] = l /\ s /= l
    /\ lhState[s] = "waitstart"
    /\ lq' = [lq EXCEPT ![s] = Append(@, LPkt("UPTODATE", NoEntry, <<>>, 0))]
    /\ lhState' = [lhState EXCEPT ![s] = "running"]
    /\ UNCHANGED <<up, electionVars, logVars, learnerVars, newLeaderAcks, fq,
                    commitVars, ghostVars>>
    /\ ResetRollback

(* LearnerHandler.run:650-678 ACK -> Leader.processAck:827-889: ignore a    *)
(* zero-counter zxid (NEWLEADER/UPTODATE ACK) and non-outstanding zxids.    *)
LeaderProcessAck(l, s) ==
    /\ up[l] /\ role[l] = "leading" /\ leaderOf[s] = l /\ s /= l
    /\ lhState[s] = "running"
    /\ fq[s] /= <<>>
    /\ LET a == Head(fq[s]) IN
       acked' = IF a.kind = "ACK" /\ InOutstanding(l, a.ent)
                THEN [acked EXCEPT ![a.ent.id] = @ \cup {s}]
                ELSE acked
    /\ fq' = [fq EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, electionVars, logVars, learnerVars, lhState,
                    newLeaderAcks, lq, commitCertified, usedTxn, ghostVars>>
    /\ ResetRollback

----------------------------------------------------------------------------
(* Learner side of synchronization: Learner.syncWithLeader (updated)       *)

(* Q/Learner.java:557-612: consume DIFF / SNAP / TRUNC inside               *)
(* synchronized(zk).  DIFF keeps the database and logs later                *)
(* (writeToTxnLog = !snapshotNeeded = true); SNAP clears and deserializes   *)
(* the leader's data tree in memory; TRUNC truncates the log and reloads.   *)
LearnerReadMode(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ lstage[s] = "mode"
    /\ lq[s] /= <<>>
    /\ LET p == Head(lq[s]) IN
       /\ p.type \in {"DIFF", "TRUNC", "SNAP"}
       /\ syncMode' = [syncMode EXCEPT ![s] = p.type]
       /\ writeToTxnLog' = [writeToTxnLog EXCEPT ![s] = (p.type = "DIFF")]
       /\ CASE p.type = "DIFF" ->
                 /\ syncBase' = [syncBase EXCEPT ![s] = durable[s]]
                 /\ UNCHANGED <<queued, appended, durable>>
                 /\ ResetRollback
            [] p.type = "TRUNC" ->
                 \* ZKDatabase.truncateLog: FileTxnSnapLog.truncateLog, reload
                 /\ syncBase' = [syncBase EXCEPT ![s] = p.hist]
                 /\ durable' = [durable EXCEPT ![s] = p.hist]
                 /\ appended' = [appended EXCEPT ![s] = p.hist]
                 /\ queued' = [queued EXCEPT ![s] = p.hist]
                 /\ rollbackAuthorized' = [x \in Server |-> x = s]
            [] p.type = "SNAP" ->
                 \* deserializeSnapshot replaces the in-memory tree only
                 /\ syncBase' = [syncBase EXCEPT ![s] = p.hist]
                 /\ UNCHANGED <<queued, appended, durable>>
                 /\ ResetRollback
    /\ pendingNC' = [pendingNC EXCEPT ![s] = <<>>]
    /\ pendingC' = [pendingC EXCEPT ![s] = <<>>]
    /\ pendingTxns' = [pendingTxns EXCEPT ![s] = <<>>]
    /\ lstage' = [lstage EXCEPT ![s] = "pre"]
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, electionVars, committed, applied, zkState, syncJustified,
                    lhState, newLeaderAcks, fq, commitVars, ghostVars>>

(* Q/Learner.java:621-641: PROPOSAL -> packetsNotCommitted.add (before and  *)
(* after NEWLEADER).                                                       *)
LearnerSyncProposal(s) ==
    /\ up[s] /\ lstage[s] \in {"pre", "post"}
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "PROPOSAL"
    /\ pendingNC' = [pendingNC EXCEPT ![s] = Append(@, Head(lq[s]).ent)]
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, electionVars, logVars, syncBase, pendingC, lstage,
                    writeToTxnLog, zkState, syncMode, syncJustified, lhState,
                    newLeaderAcks, fq, commitVars, ghostVars>>
    /\ ResetRollback

(* Q/Learner.java:643-669 (unchanged code, changed pre-state): COMMIT.      *)
(*  pif = packetsNotCommitted.peekFirst(); pif.hdr... has no null check:   *)
(*  an empty buffer raises NullPointerException, caught by                 *)
(*  Follower.followLeader:121-128 -> socket closed -> role exit.           *)
(*  !writeToTxnLog: apply the matching head to the data tree (processTxn). *)
(*  writeToTxnLog : remember the zxid in packetsCommitted.                 *)
\* UPDATE-MAP
\* code: Q/Learner.java:757 (packetsNotCommitted.clear) feeding :645-646
\* update: Update!SyncCommitHasPendingProposal
LearnerSyncCommit(s) ==
    /\ up[s] /\ lstage[s] \in {"pre", "post"}
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "COMMIT"
    /\ LET e == Head(lq[s]).ent IN
       IF pendingNC[s] = <<>>
       THEN /\ syncNPE' = [syncNPE EXCEPT ![s] = TRUE]
            /\ RoleExit(s, "election")
            /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                            queued, committed, applied, commitVars,
                            globalCommitted, nlAckMisread, unmatchedCommit>>
       ELSE /\ IF ~writeToTxnLog[s]
               THEN IF Head(pendingNC[s]) = e
                    THEN /\ syncBase' = [syncBase EXCEPT ![s] = Append(@, e)]
                         /\ pendingNC' = [pendingNC EXCEPT ![s] = Tail(@)]
                         /\ UNCHANGED pendingC
                    ELSE UNCHANGED <<syncBase, pendingNC, pendingC>>
               ELSE /\ pendingC' = [pendingC EXCEPT ![s] = Append(@, e)]
                    /\ UNCHANGED <<syncBase, pendingNC>>
            /\ lq' = [lq EXCEPT ![s] = Tail(@)]
            /\ UNCHANGED <<up, electionVars, logVars, lstage, writeToTxnLog,
                            zkState, syncMode, syncJustified, lhState,
                            newLeaderAcks, fq, commitVars, ghostVars>>
    /\ ResetRollback

(* UPDATED Q/Learner.java:726-759, NEWLEADER (one learner-thread step;      *)
(* only volatile state lies between its persistent writes):                *)
(*  - SNAP/TRUNC: zk.takeSnapshot(syncSnapshot) persists the data tree     *)
(*    (restore then replays log records after the snapshot);              *)
(*  - self.setCurrentEpoch(newEpoch) (file, then field);                   *)
(*  - writeToTxnLog = true;                                                *)
(*  - NEW: setSyncMode(NONE); zk.startupWithoutServing() (state INITIAL,   *)
(*    SyncRequestProcessor/CommitProcessor threads started);               *)
(*  - NEW: fzk.logRequest for every packetsNotCommitted entry: pendingTxns *)
(*    .add + syncProcessor.processRequest -- an asynchronous enqueue       *)
(*    (FollowerZooKeeperServer.java:80-89), NOT a write or fsync;          *)
(*  - NEW: packetsNotCommitted.clear().                                    *)
(* The NEWLEADER ACK is a separate later step (LearnerAckNewLeader).        *)
\* UPDATE-MAP
\* code: Q/Learner.java:744-757; ZooKeeperServer.java:669-704
\* update: Update!AffectedActions (MCLearnerNewLeader), Update!CommittedQuorumDurable
LearnerNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ lstage[s] = "pre"
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "NEWLEADER"
    /\ LET snapNeeded == syncMode[s] /= "DIFF"
           replace == snapNeeded /\ ~IsPrefix(syncBase[s], durable[s])
           baseLog == IF replace THEN syncBase[s] ELSE durable[s]
           baseQ == IF replace THEN syncBase[s] ELSE queued[s]
           baseA == IF replace THEN syncBase[s] ELSE appended[s]
       IN /\ durable' = [durable EXCEPT ![s] = baseLog]
          /\ appended' = [appended EXCEPT ![s] = baseA]
          /\ queued' = [queued EXCEPT ![s] = baseQ \o pendingNC[s]]
          /\ rollbackAuthorized' = [x \in Server |-> x = s /\ replace]
    /\ pendingTxns' = [pendingTxns EXCEPT ![s] = @ \o pendingNC[s]]
    /\ pendingNC' = [pendingNC EXCEPT ![s] = <<>>]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
    /\ writeToTxnLog' = [writeToTxnLog EXCEPT ![s] = TRUE]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ zkState' = [zkState EXCEPT ![s] = "initial"]
    /\ lstage' = [lstage EXCEPT ![s] = "nlack"]
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes, leaderEpoch,
                    epochAcks, leadersByEpoch, committed, applied, syncBase,
                    pendingC, syncJustified, lhState, newLeaderAcks, fq,
                    commitVars, ghostVars>>

(* UPDATED Q/Learner.java:760: writePacket(ACK(newLeaderZxid), true).  The  *)
(* SyncRequestProcessor started at :751 may already have written ACKs of    *)
(* the enqueued proposals on the same stream (FsyncOne).                   *)
\* UPDATE-MAP
\* code: Q/Learner.java:760; Q/SendAckRequestProcessor.java:40-59
\* update: Update!AffectedActions (MCLearnerAckNewLeader), Update!NewLeaderAckFirst
LearnerAckNewLeader(s) ==
    /\ up[s] /\ lstage[s] = "nlack"
    /\ fq' = [fq EXCEPT ![s] = Append(@, FPkt("NLACK", NoEntry, acceptedEpoch[s]))]
    /\ lstage' = [lstage EXCEPT ![s] = "post"]
    /\ UNCHANGED <<up, electionVars, logVars, syncBase, pendingNC, pendingC,
                    writeToTxnLog, zkState, syncMode, syncJustified, lhState,
                    newLeaderAcks, lq, commitVars, ghostVars>>
    /\ ResetRollback

\* FollowerZooKeeperServer.commit:97-112 folded over packetsCommitted.
\* empty pendingTxns -> warn and skip; head mismatch -> System.exit
\* (UNMATCHED_TXN_COMMIT), reported through the flag and stopping the fold.
RECURSIVE CommitAll(_, _, _)
CommitAll(pt, cs, done) ==
    IF cs = <<>> THEN [rest |-> pt, done |-> done, bad |-> FALSE]
    ELSE IF pt = <<>> THEN CommitAll(pt, Tail(cs), done)
    ELSE IF Head(pt) /= Head(cs) THEN [rest |-> pt, done |-> done, bad |-> TRUE]
    ELSE CommitAll(Tail(pt), Tail(cs), Append(done, Head(cs)))

(* UPDATED Q/Learner.java:711-725 and 764-786, UPTODATE: break out of the   *)
(* loop, write ACK (:766), zk.startServing() (:767, state RUNNING), then    *)
(* log the packetsNotCommitted received after NEWLEADER (:779-782) and     *)
(* commit every packetsCommitted zxid (:783-785).  The served data tree is *)
(* the synchronized base; the deferred commits are handed to the           *)
(* CommitProcessor (ApplyOne applies them).                                *)
\* UPDATE-MAP
\* code: Q/Learner.java:764-786; ZooKeeperServer.java:676-679
\* update: Update!AffectedActions (MCLearnerUpToDate), Update!DeferredCommitMatchesPending
LearnerUpToDate(s) ==
    /\ up[s] /\ role[s] = "following" /\ lstage[s] = "post"
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "UPTODATE"
    /\ LET pt == pendingTxns[s] \o pendingNC[s]
           r == CommitAll(pt, pendingC[s], <<>>)
       IN /\ queued' = [queued EXCEPT ![s] = @ \o pendingNC[s]]
          /\ pendingTxns' = [pendingTxns EXCEPT ![s] = r.rest]
          /\ committed' = [committed EXCEPT ![s] = syncBase[s] \o r.done]
          /\ unmatchedCommit' = [unmatchedCommit EXCEPT ![s] = @ \/ r.bad]
    /\ applied' = [applied EXCEPT ![s] = syncBase[s]]
    /\ fq' = [fq EXCEPT ![s] = Append(@, FPkt("UTDACK", NoEntry, acceptedEpoch[s]))]
    /\ zkState' = [zkState EXCEPT ![s] = "running"]
    /\ pendingNC' = [pendingNC EXCEPT ![s] = <<>>]
    /\ pendingC' = [pendingC EXCEPT ![s] = <<>>]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
    /\ lstage' = [lstage EXCEPT ![s] = "done"]
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    \* The synchronized view replaces the learner's stale volatile view.
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<up, electionVars, appended, durable, syncBase, writeToTxnLog,
                    syncMode, lhState, newLeaderAcks, commitVars,
                    globalCommitted, nlAckMisread, syncNPE>>

(* Q/Follower.java:96-99: setZabState(BROADCAST) after syncWithLeader       *)
(* returned.                                                               *)
EnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ lstage[s] = "done" /\ currentEpoch[s] = acceptedEpoch[s]
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leaderEpoch, epochAcks, leadersByEpoch, logVars,
                    learnerVars, handlerVars, commitVars, ghostVars>>
    /\ ResetRollback

----------------------------------------------------------------------------
(* Broadcast                                                               *)

(* Leader.propose:1215-1257 (outstandingProposals.put; sendPacket to the     *)
(* forwarding learners) then ProposalRequestProcessor enqueues the leader's *)
(* own SyncRequestProcessor request.                                       *)
Propose(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ t \in Txn \ usedTxn
    /\ LET e == EntryFor(t, currentEpoch[l]) IN
       /\ queued' = [queued EXCEPT ![l] = Append(@, e)]
       /\ lq' = [x \in Server |-> IF x \in Forwarding(l)
                                  THEN Append(lq[x], LPkt("PROPOSAL", e, <<>>, 0))
                                  ELSE lq[x]]
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<up, electionVars, appended, durable, committed, applied,
                    pendingTxns, learnerVars, lhState, newLeaderAcks, fq,
                    acked, commitCertified, ghostVars>>
    /\ ResetRollback

(* Q/Follower.processPacket:165-185 PROPOSAL -> fzk.logRequest.             *)
ReceiveProposal(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "broadcast"
    /\ lstage[s] = "done"
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "PROPOSAL"
    /\ queued' = [queued EXCEPT ![s] = Append(@, Head(lq[s]).ent)]
    /\ pendingTxns' = [pendingTxns EXCEPT ![s] = Append(@, Head(lq[s]).ent)]
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, electionVars, appended, durable, committed, applied,
                    learnerVars, lhState, newLeaderAcks, fq, commitVars,
                    ghostVars>>
    /\ ResetRollback

(* SyncRequestProcessor.run:181-218: ZKDatabase.append (buffered stream).   *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ appended' = [appended EXCEPT ![s] = Append(@, queued[s][Len(appended[s]) + 1])]
    /\ UNCHANGED <<up, electionVars, queued, durable, committed, applied,
                    pendingTxns, learnerVars, handlerVars, commitVars,
                    ghostVars>>
    /\ ResetRollback

(* SyncRequestProcessor.flush:227-252: ZKDatabase.commit (flush + force),    *)
(* then the next processor: the leader's AckRequestProcessor               *)
(* (Leader.processAck for itself) or the learner's SendAckRequestProcessor  *)
(* (writes ACK(zxid) to the leader stream, Q/SendAckRequestProcessor:40-59).*)
(* A learner whose connection is gone (or whose processors leaked) cannot   *)
(* deliver the ACK.                                                        *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET e == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, e)]
       /\ IF role[s] = "leading" /\ phase[s] = "broadcast" /\ InOutstanding(s, e)
          THEN /\ acked' = [acked EXCEPT ![e.id] = @ \cup {s}]
               /\ UNCHANGED fq
          ELSE IF role[s] = "following" /\ lstage[s] \in {"nlack", "post", "done"}
               THEN /\ fq' = [fq EXCEPT ![s] = Append(@, FPkt("ACK", e, 0))]
                    /\ UNCHANGED acked
               ELSE UNCHANGED <<acked, fq>>
    /\ UNCHANGED <<up, electionVars, queued, appended, committed, applied,
                    pendingTxns, learnerVars, lhState, newLeaderAcks, lq,
                    commitCertified, usedTxn, ghostVars>>
    /\ ResetRollback

(* Leader.tryToCommit:890-965: only the next outstanding proposal, with a    *)
(* quorum of ACKs; commit() sends COMMIT to the forwarding learners.        *)
Commit(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ Len(committed[l]) < Len(queued[l])
    /\ LET k == Len(committed[l]) + 1
           e == queued[l][k]
       IN /\ Cardinality(acked[e.id]) >= Quorum
          /\ committed' = [committed EXCEPT ![l] = Append(@, e)]
          /\ commitCertified' = [commitCertified EXCEPT ![e.id] = TRUE]
          /\ globalCommitted' = globalCommitted \cup {<<k, e>>}
          /\ lq' = [x \in Server |-> IF x \in Forwarding(l)
                                     THEN Append(lq[x], LPkt("COMMIT", e, <<>>, 0))
                                     ELSE lq[x]]
    /\ UNCHANGED <<up, electionVars, queued, appended, durable, applied,
                    pendingTxns, learnerVars, lhState, newLeaderAcks, fq,
                    acked, usedTxn, nlAckMisread, syncNPE, unmatchedCommit>>
    /\ ResetRollback

(* Q/Follower.processPacket:203-211 COMMIT -> FollowerZooKeeperServer.commit*)
ReceiveCommit(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "broadcast"
    /\ lstage[s] = "done"
    /\ lq[s] /= <<>> /\ Head(lq[s]).type = "COMMIT"
    /\ LET e == Head(lq[s]).ent IN
       IF pendingTxns[s] = <<>>
       THEN UNCHANGED <<committed, pendingTxns, unmatchedCommit>>
       ELSE IF Head(pendingTxns[s]) /= e
            THEN /\ unmatchedCommit' = [unmatchedCommit EXCEPT ![s] = TRUE]
                 /\ UNCHANGED <<committed, pendingTxns>>
            ELSE /\ committed' = [committed EXCEPT ![s] = Append(@, e)]
                 /\ pendingTxns' = [pendingTxns EXCEPT ![s] = Tail(@)]
                 /\ UNCHANGED unmatchedCommit
    /\ lq' = [lq EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, electionVars, queued, appended, durable, applied,
                    learnerVars, lhState, newLeaderAcks, fq, commitVars,
                    globalCommitted, nlAckMisread, syncNPE>>
    /\ ResetRollback

(* CommitProcessor -> FinalRequestProcessor -> ZooKeeperServer.processTxn    *)
(* (ZooKeeperServer.java:1747-1785) applies the next certified commit.     *)
ApplyOne(s) ==
    /\ up[s] /\ Len(applied[s]) < Len(committed[s])
    /\ LET e == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[e.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, e)]
    /\ UNCHANGED <<up, electionVars, queued, appended, durable, committed,
                    pendingTxns, learnerVars, handlerVars, commitVars,
                    ghostVars>>
    /\ ResetRollback

----------------------------------------------------------------------------
(* Faults                                                                  *)

(* Fail-stop process crash: every volatile structure is lost; the forced    *)
(* log/snapshot history (durable) and the epoch files survive.             *)
Crash(s) ==
    /\ up[s]
    /\ up' = [up EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "offline"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ leaderEpoch' = [leaderEpoch EXCEPT ![s] = 0]
    /\ epochAcks' = [epochAcks EXCEPT ![s] = {}]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![s] = {}]
    /\ queued' = [queued EXCEPT ![s] = durable[s]]
    /\ appended' = [appended EXCEPT ![s] = durable[s]]
    /\ committed' = [committed EXCEPT ![s] = <<>>]
    /\ applied' = [applied EXCEPT ![s] = <<>>]
    /\ pendingTxns' = [pendingTxns EXCEPT ![s] = <<>>]
    /\ syncBase' = [syncBase EXCEPT ![s] = <<>>]
    /\ pendingNC' = [pendingNC EXCEPT ![s] = <<>>]
    /\ pendingC' = [pendingC EXCEPT ![s] = <<>>]
    /\ lstage' = [lstage EXCEPT ![s] = "none"]
    /\ writeToTxnLog' = [writeToTxnLog EXCEPT ![s] = FALSE]
    /\ zkState' = [zkState EXCEPT ![s] = "stopped"]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ lq' = SetAll(lq, Links(s), <<>>)
    /\ fq' = SetAll(fq, Links(s), <<>>)
    /\ lhState' = SetAll(lhState, Links(s), "none")
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, votes, leadersByEpoch, durable,
                    commitVars, ghostVars>>

(* Restart: QuorumPeer.loadDataBase/restore rebuilds the tree from durable  *)
(* state; the peer starts in LOOKING.                                      *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ votes' = [votes EXCEPT ![s] = {}]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, leaderEpoch,
                    epochAcks, leadersByEpoch, logVars, learnerVars,
                    handlerVars, commitVars, ghostVars>>
    /\ ResetRollback

----------------------------------------------------------------------------
Next ==
    \/ \E s \in Server : BeginElection(s)
    \/ \E v, c \in Server : CastVote(v, c)
    \/ \E c \in Server : ElectLeader(c)
    \/ \E s, c \in Server : ElectFollow(s, c)
    \/ \E l \in Server : LeaderProposeEpoch(l)
    \/ \E s \in Server : AcceptEpoch(s)
    \/ \E l \in Server : FinishDiscovery(l)
    \/ \E s \in Server : EnterSyncPhase(s)
    \/ \E l, s \in Server, m \in {"DIFF", "TRUNC", "SNAP"} : LeaderSyncFollower(l, s, m)
    \/ \E l, s \in Server : LeaderSendNewLeader(l, s)
    \/ \E l, s \in Server : LeaderReadNewLeaderAck(l, s)
    \/ \E l \in Server : LeaderBroadcast(l)
    \/ \E l, s \in Server : LeaderSendUpToDate(l, s)
    \/ \E l, s \in Server : LeaderProcessAck(l, s)
    \/ \E s \in Server : LearnerReadMode(s)
    \/ \E s \in Server : LearnerSyncProposal(s)
    \/ \E s \in Server : LearnerSyncCommit(s)
    \/ \E s \in Server : LearnerNewLeader(s)
    \/ \E s \in Server : LearnerAckNewLeader(s)
    \/ \E s \in Server : LearnerUpToDate(s)
    \/ \E s \in Server : EnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : Propose(l, t)
    \/ \E s \in Server : ReceiveProposal(s)
    \/ \E s \in Server : AppendOne(s)
    \/ \E s \in Server : FsyncOne(s)
    \/ \E l \in Server : Commit(l)
    \/ \E s \in Server : ReceiveCommit(s)
    \/ \E s \in Server : ApplyOne(s)
    \/ \E s \in Server : Crash(s)
    \/ \E s \in Server : Restart(s)

Spec == Init /\ [][Next]_allVars

----------------------------------------------------------------------------
(* Properties                                                              *)

LPktSet == [type : LTypes, ent : Entry \cup {NoEntry}, hist : Seq(Entry), epoch : Epoch]
FPktSet == [kind : FKinds, ent : Entry \cup {NoEntry}, epoch : Epoch]

TypeOK ==
    /\ up \in [Server -> BOOLEAN]
    /\ role \in [Server -> Role]
    /\ phase \in [Server -> Phase]
    /\ leaderOf \in [Server -> (Server \cup {Nil})]
    /\ acceptedEpoch \in [Server -> Epoch]
    /\ currentEpoch \in [Server -> Epoch]
    /\ votes \in [Server -> SUBSET Server]
    /\ leaderEpoch \in [Server -> Epoch]
    /\ epochAcks \in [Server -> SUBSET Server]
    /\ leadersByEpoch \in [Epoch -> SUBSET Server]
    /\ queued \in [Server -> Seq(Entry)]
    /\ appended \in [Server -> Seq(Entry)]
    /\ durable \in [Server -> Seq(Entry)]
    /\ committed \in [Server -> Seq(Entry)]
    /\ applied \in [Server -> Seq(Entry)]
    /\ pendingTxns \in [Server -> Seq(Entry)]
    /\ syncBase \in [Server -> Seq(Entry)]
    /\ pendingNC \in [Server -> Seq(Entry)]
    /\ pendingC \in [Server -> Seq(Entry)]
    /\ lstage \in [Server -> LStages]
    /\ writeToTxnLog \in [Server -> BOOLEAN]
    /\ zkState \in [Server -> ZkStates]
    /\ syncMode \in [Server -> SyncModes]
    /\ syncJustified \in [Server -> BOOLEAN]
    /\ lhState \in [Server -> LHStates]
    /\ newLeaderAcks \in [Server -> SUBSET Server]
    /\ lq \in [Server -> Seq(LPktSet)]
    /\ fq \in [Server -> Seq(FPktSet)]
    /\ acked \in [Txn -> SUBSET Server]
    /\ commitCertified \in [Txn -> BOOLEAN]
    /\ usedTxn \subseteq Txn
    /\ rollbackAuthorized \in [Server -> BOOLEAN]
    /\ \A p \in globalCommitted : p[1] \in Nat \ {0} /\ p[2] \in Entry
    /\ nlAckMisread \in [Server -> BOOLEAN]
    /\ syncNPE \in [Server -> BOOLEAN]
    /\ unmatchedCommit \in [Server -> BOOLEAN]

\* At most one leader establishes (finishes discovery for) each epoch.
ElectionSafety == \A e \in Epoch : Cardinality(leadersByEpoch[e]) <= 1

\* REVISED (Chapter 2): two leaders may concurrently *propose* the same
\* epoch in discovery (getEpochToPropose is per leader); the promised
\* property is about live leaders that established the epoch.
OneActiveLeaderPerEpoch ==
    \A e \in Epoch \ {0} :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ phase[s] \in {"sync", "broadcast"}
                                    /\ currentEpoch[s] = e}) <= 1

CommittedHistoriesPrefix ==
    \A a, b \in Server : IsPrefix(committed[a], committed[b]) \/
                          IsPrefix(committed[b], committed[a])

\* NEW (general Zab safety, needed because crash resets volatile views):
\* no two different entries are ever committed at the same position.
CommittedAgreement ==
    \A p, q \in globalCommitted : p[1] = q[1] => p[2] = q[2]

ApplyRequiresCommitCertificate ==
    \A s \in Server :
        /\ IsPrefix(applied[s], committed[s])
        /\ \A k \in 1..Len(applied[s]) : commitCertified[applied[s][k].id]

PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])

EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]

NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ CommittedAgreement /\
          ApplyRequiresCommitCertificate /\ PipelinePrefix /\
          EpochHistoryConsistency /\ SyncCompletionJustified


=============================================================================
