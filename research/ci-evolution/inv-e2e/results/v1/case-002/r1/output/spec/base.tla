------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* ZooKeeper Zab reference model for the UPDATED source revision           *)
(* (artifact commit "update").  The prior V0 model is preserved under       *)
(* /work/previous/.specula-output/spec/base.tla; this module is the single  *)
(* behavioral owner of the new-version semantics.                          *)
(*                                                                         *)
(* Source paths (zookeeper-server/src/main/java/org/apache/zookeeper/...):  *)
(*   QP  = server/quorum/QuorumPeer.java      FLE = .../FastLeaderElection  *)
(*   Ldr = server/quorum/Leader.java          LH  = .../LearnerHandler.java *)
(*   L   = server/quorum/Learner.java         F   = .../Follower.java       *)
(*   FZK = server/quorum/FollowerZooKeeperServer.java                       *)
(*   LZK = server/quorum/LearnerZooKeeperServer.java                        *)
(*   ZKS = server/ZooKeeperServer.java        SRP = server/SyncRequestProcessor.java *)
(*   ZKD = server/ZKDatabase.java                                           *)
(*                                                                         *)
(* State meanings (revised, see analysis-report.md "Representation"):      *)
(*   applied   - in-memory ZKDatabase data tree history.  It is the basis  *)
(*               of the FLE vote zxid (QP:1257-1262 getLastLoggedZxid) and *)
(*               of a new leader's loaded database (ZKS:480-512 loadData). *)
(*   committed - prefix this server knows to be committed.                 *)
(*   proposed/queued/appended/durable - learner/leader request pipeline;   *)
(*               durable = fsynced transaction-log history.               *)
(*   snapshot  - newest persisted snapshot history.                        *)
(*   Persisted(s) - what FileTxnSnapLog.restore rebuilds.                  *)
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
\* ZKS:185-190 State {INITIAL, RUNNING, SHUTDOWN, ERROR}.  "NONE" = no request
\* processors exist for the current role session (never started / shut down /
\* crashed).  "INITIAL" is reachable for a learner only through the updated
\* ZKS:673 startupWithoutServing; "RUNNING" through startup()/startServing().
ZkStates == {"NONE", "INITIAL", "RUNNING"}
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
\* "nlack" is the learner's ACK of NEWLEADER (L:760), consumed by
\* LH:613-624 and Ldr:1546-1586 waitForNewLeaderAck.
MsgKind == {"proposal", "ack", "commit", "nlack"}
Message == [kind : MsgKind, from : Server, to : Server,
            id : Txn \cup {Nil}, epoch : Epoch]

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES up, role, phase, leaderOf,
          acceptedEpoch, currentEpoch,
          votes, leadersByEpoch,
          proposed, queued, appended, durable, committed, applied,
          snapshot,
          acked, commitCertified, messages,
          syncMode, syncSource, syncJustified,
          usedTxn, rollbackAuthorized,
          \* ---- update-required state (UPDATE-MAP: see Update.tla header) ----
          epochSet,     \* session epoch settled: learner wrote ACKEPOCH (L:524-526);
                        \* leader completed getEpochToPropose (Ldr:1407-1411)
          syncBuf,      \* L:559 packetsNotCommitted (volatile, local)
          syncCommits,  \* L:558 packetsCommitted (volatile, local)
          syncStarted,  \* learner consumed a DIFF/TRUNC/SNAP directive in this session
          pending,      \* FZK:80 pendingTxns of the current FollowerZooKeeperServer
          nlAckSent,    \* learner processed NEWLEADER and wrote its ACK (L:760)
          nlAcks,       \* leader newLeaderProposal ack set (Ldr:1546-1586)
          zkState       \* ZooKeeperServer state of the current role session

electionVars == <<role, phase, leaderOf, acceptedEpoch, currentEpoch,
                  votes, leadersByEpoch, epochSet>>
histVars == <<proposed, queued, appended, durable, committed, applied, snapshot>>
syncVars == <<syncMode, syncSource, syncJustified, syncBuf, syncCommits,
              syncStarted, pending, nlAckSent, nlAcks>>

allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             usedTxn, rollbackAuthorized,
             epochSet, syncBuf, syncCommits, syncStarted, pending, nlAckSent,
             nlAcks, zkState>>

-----------------------------------------------------------------------------
(* Helpers *)

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
Comparable(a, b) == IsPrefix(a, b) \/ IsPrefix(b, a)
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
Range(h) == {h[k] : k \in 1..Len(h)}
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
\* zxid counter of the last entry: counters restart at 1 in every epoch and
\* increase by one per proposal (Ldr:1236-1252 propose, ZxidUtils).
ZxidCounter(h) == Cardinality({k \in 1..Len(h) : h[k].epoch = LastEpoch(h)})
ZxidGE(a, b) == \/ LastEpoch(a) > LastEpoch(b)
                \/ /\ LastEpoch(a) = LastEpoch(b)
                   /\ ZxidCounter(a) >= ZxidCounter(b)
ZxidGT(a, b) == ZxidGE(a, b) /\ ~ZxidGE(b, a)
Suffix(h, n) == IF n >= Len(h) THEN <<>> ELSE SubSeq(h, n + 1, Len(h))
Min(a, b) == IF a <= b THEN a ELSE b
CommonPrefix(a, b) ==
    LET n == CHOOSE k \in 0..Min(Len(a), Len(b)) :
               /\ SubSeq(a, 1, k) = SubSeq(b, 1, k)
               /\ \/ k = Min(Len(a), Len(b))
                  \/ a[k + 1] /= b[k + 1]
    IN SubSeq(a, 1, n)
Longer(a, b) == IF Len(a) >= Len(b) THEN a ELSE b
SetMax(S) == CHOOSE x \in S : \A y \in S : y <= x

\* FileTxnSnapLog.restore: newest snapshot plus later fsynced log records.
Persisted(s) == IF IsPrefix(durable[s], snapshot[s]) THEN snapshot[s] ELSE durable[s]

\* An entry already handed to the learner pipeline or data tree.
Known(s, e) == e \in Range(applied[s]) \cup Range(proposed[s]) \cup Range(syncBuf[s])
CommitKnown(s, e) == e \in Range(committed[s]) \cup Range(syncCommits[s])

\* Leader-side histories transmitted by LH:775-933 syncFollower/startForwarding.
\* Before activation the leader sends its loaded committedLog (all of its
\* in-memory data tree) as PROPOSAL+COMMIT pairs; after activation it sends the
\* committed log plus outstanding proposals (Ldr:1625-1660 startForwarding).
\* Ldr.outstandingProposals: current-epoch proposals not yet committed (a
\* leader's log may also hold older records its data tree never applied).
Outstanding(l) == SelectSeq(proposed[l], LAMBDA e : e.epoch = currentEpoch[l]
                                                   /\ e \notin Range(committed[l]))
LeaderHist(l) == IF zkState[l] = "RUNNING" THEN committed[l] \o Outstanding(l)
                 ELSE applied[l]
LeaderCommitHist(l) == IF zkState[l] = "RUNNING" THEN committed[l] ELSE applied[l]

\* Ldr:1442-1466 waitForEpochAck: StateSummary.isMoreRecentThan.
MoreRecent(s, l) == \/ currentEpoch[s] > currentEpoch[l]
                    \/ /\ currentEpoch[s] = currentEpoch[l]
                       /\ ZxidGT(applied[s], applied[l])

\* A leader whose epoch was proposed (Ldr:1396-1430 getEpochToPropose).
Established(l) == role[l] = "leading" /\ epochSet[l]

EpochAckers(l) ==
    {l} \cup {s \in Server : /\ s /= l /\ up[s]
                             /\ role[s] = "following" /\ leaderOf[s] = l
                             /\ epochSet[s]
                             /\ acceptedEpoch[s] = acceptedEpoch[l]
                             /\ ~MoreRecent(s, l)}

\* Ldr:1442-1466 electionFinished is a sticky flag set when the epoch-ACK
\* quorum (evaluated on each learner's ACKEPOCH-time StateSummary) forms.
\* It is observable afterwards only through a learner whose LearnerHandler
\* already passed waitForEpochAck (it has started synchronizing with l in
\* this epoch); a learner that has since persisted l's epoch at NEWLEADER is
\* no longer "more recent" in the sense of its earlier ACKEPOCH summary.
ElectionFinished(l) ==
    \/ Cardinality(EpochAckers(l)) >= Quorum
    \/ \E s \in Server : /\ s /= l /\ syncStarted[s] /\ syncSource[s] = l
                        /\ acceptedEpoch[s] = acceptedEpoch[l]

\* electionFinished (Ldr:1458-1462) or already persisted by the leader thread.
EpochReady(l) == /\ up[l] /\ Established(l)
                 /\ \/ currentEpoch[l] = acceptedEpoch[l]
                    \/ ElectionFinished(l)

\* LH passes waitForEpochAck for learner s.
LeaderReadyFor(l, s) ==
    /\ l /= s /\ EpochReady(l)
    /\ epochSet[s] /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ (currentEpoch[l] = acceptedEpoch[l] \/ ~MoreRecent(s, l))

\* Learners registered in Ldr.forwardingFollowers after startForwarding.
Forwarding(s, l) == /\ s /= l /\ up[s]
                    /\ role[s] = "following" /\ leaderOf[s] = l
                    /\ phase[s] \in {"sync", "broadcast"}
                    /\ syncStarted[s]
                    /\ acceptedEpoch[s] = acceptedEpoch[l]

ActiveLeader(l) == up[l] /\ role[l] = "leading" /\ zkState[l] = "RUNNING"

NoRollback == rollbackAuthorized' = [s \in Server |-> FALSE]
DropTo(s) == {m \in messages : m.to /= s}

-----------------------------------------------------------------------------
Init ==
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> 0]
    /\ currentEpoch = [s \in Server |-> 0]
    /\ votes = [s \in Server |-> {s}]
    /\ leadersByEpoch = [e \in Epoch |-> {}]
    /\ proposed = [s \in Server |-> <<>>]
    /\ queued = [s \in Server |-> <<>>]
    /\ appended = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> <<>>]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ usedTxn = {}
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ epochSet = [s \in Server |-> FALSE]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ syncStarted = [s \in Server |-> FALSE]
    /\ pending = [s \in Server |-> <<>>]
    /\ nlAckSent = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ zkState = [s \in Server |-> "NONE"]

-----------------------------------------------------------------------------
(***************************************************************************)
(* Election and discovery                                                   *)
(***************************************************************************)

(* FileTxnSnapLog.fastForwardFromEdits (FileTxnSnapLog.java:317-333) replays *)
(* logged records with zxid > dataTree.lastProcessedZxid.  A leader's       *)
(* startZkServer sets lastProcessedZxid to (epoch, 0) (Ldr:1536), so logged   *)
(* records of older epochs that its data tree never applied are skipped.     *)
FastForwardFloor(s) == IF role[s] = "leading" THEN currentEpoch[s]
                       ELSE LastEpoch(applied[s])
FastForwardReplay(s) ==
    SelectSeq(queued[s], LAMBDA e : e \notin Range(applied[s])
                                    /\ e.epoch >= FastForwardFloor(s))

(* QP:1468-1495 a FOLLOWING/LEADING session ends: follower.shutdown() /      *)
(* leader.shutdown() then updateServerState -> setPeerState(LOOKING), which   *)
(* nests setZabState(ELECTION) (QP:853-861).                                 *)
(* Shutdown effects (LZK:155-173, ZKS:803-851):                              *)
(*  - canShutdown() (ZKS:784) holds only for RUNNING/ERROR.  Then processors   *)
(*    are drained (SRP:252-268 shutdown flushes) and zkDb.fastForwardDataBase *)
(*    replays the log into the data tree (ZKS:845).  ABSTRACTION: the model   *)
(*    performs the flush before the fast-forward; LZK shuts the sync processor *)
(*    down after ZKS.shutdown, see analysis-report "Abstractions".            *)
(*  - In INITIAL (updated learner between NEWLEADER and UPTODATE) or before    *)
(*    startup, shutdown is skipped: no fast-forward (the data tree keeps its   *)
(*    pre-sync position) and a started SyncRequestProcessor is leaked: it     *)
(*    keeps appending/fsyncing its queue (AppendOne/FsyncOne stay enabled).   *)
(*  - QuorumPeer.syncMode is never reset here (only L:564-590, L:750 write it). *)
BeginElection(s) ==
    /\ up[s]
    /\ role[s] /= "looking"
    /\ IF zkState[s] = "RUNNING"
       THEN /\ durable' = [durable EXCEPT ![s] = queued[s]]
            /\ appended' = [appended EXCEPT ![s] = queued[s]]
            /\ applied' = [applied EXCEPT ![s] = @ \o FastForwardReplay(s)]
       ELSE UNCHANGED <<durable, appended, applied>>
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ epochSet' = [epochSet EXCEPT ![s] = FALSE]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ syncStarted' = [syncStarted EXCEPT ![s] = FALSE]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ nlAckSent' = [nlAckSent EXCEPT ![s] = FALSE]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ zkState' = [zkState EXCEPT ![s] = "NONE"]
    /\ messages' = DropTo(s)
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    proposed, queued, committed, snapshot, acked,
                    commitCertified, usedTxn, syncMode>>
    /\ NoRollback

(* QP:1396-1457 LOOKING case: a new lookForLeader round (or the LOOKING       *)
(* re-assertion after an election exception/shutdown) while already LOOKING. *)
RestartElectionRound(s) ==
    /\ up[s] /\ role[s] = "looking" /\ phase[s] = "election"
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* FLE totalOrderPredicate (FLE:722-746): peer epoch (currentEpoch, FLE      *)
(* getPeerEpoch), then last zxid of the in-memory database                   *)
(* (QP:1257-1262), then server id (left nondeterministic).                   *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ ZxidGE(applied[candidate], applied[voter])

\* A LOOKING voter also adopts the vote of a peer that already decided
\* LEADING (FLE:1055-1080 notifications from LEADING/FOLLOWING peers,
\* outofelection + checkLeader), so a late peer can join an elected leader.
CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate] /\ voter /= candidate
    /\ role[voter] = "looking" /\ role[candidate] \in {"looking", "leading"}
    /\ voter \notin votes[candidate]
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* FLE:1029-1047 quorum for self, then QP.setPeerState(LEADING).             *)
WinElection(c) ==
    /\ up[c] /\ role[c] = "looking" /\ phase[c] = "election"
    /\ c \in votes[c]
    /\ Cardinality(votes[c]) >= Quorum
    /\ role' = [role EXCEPT ![c] = "leading"]
    /\ leaderOf' = [leaderOf EXCEPT ![c] = c]
    /\ UNCHANGED <<up, phase, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* FLE:1029-1047 quorum observed for another server -> FOLLOWING.            *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s]
    /\ role[s] = "looking" /\ phase[s] = "election"
    /\ s \in votes[l]
    /\ Cardinality(votes[l]) >= Quorum
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ UNCHANGED <<up, phase, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* Ldr:591-593 lead(): setZabState(DISCOVERY); zk.loadData() keeps the      *)
(* initialized data tree and takes a clean snapshot (ZKS:499-511).           *)
StartLeading(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "election"
    /\ phase' = [phase EXCEPT ![l] = "discovery"]
    /\ snapshot' = [snapshot EXCEPT ![l] = applied[l]]
    /\ nlAcks' = [nlAcks EXCEPT ![l] = {}]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, syncBuf, syncCommits,
                    nlAckSent, usedTxn, epochSet, zkState, syncStarted, pending>>
    /\ NoRollback

(* F:86 followLeader(): setZabState(DISCOVERY).                              *)
StartFollowing(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "election"
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* Ldr:1396-1430 getEpochToPropose: epoch = 1 + max accepted epoch among the *)
(* connecting participants; setAcceptedEpoch once a quorum (with the leader) *)
(* connected.  The leadersByEpoch freshness guard is the prior abstraction   *)
(* that keeps ElectionSafety structural (prior base.tla WinElection).        *)
Connecting(l) == {l} \cup {s \in Server : /\ s /= l /\ up[s]
                                          /\ role[s] = "following"
                                          /\ leaderOf[s] = l
                                          /\ phase[s] = "discovery"}
LeaderProposeEpoch(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ ~epochSet[l]
    /\ Cardinality(Connecting(l)) >= Quorum
    /\ LET ep == SetMax({acceptedEpoch[x] : x \in Connecting(l)}) + 1 IN
       /\ ep <= MaxEpoch
       /\ leadersByEpoch[ep] = {}
       /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![l] = ep]
       /\ leadersByEpoch' = [leadersByEpoch EXCEPT ![ep] = {l}]
    /\ epochSet' = [epochSet EXCEPT ![l] = TRUE]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes,
                    histVars, acked, commitCertified, messages, syncVars,
                    usedTxn, zkState>>
    /\ NoRollback

(* L:503-511 registerWithLeader: persist a strictly newer accepted epoch.    *)
AcceptEpoch(s) ==
    LET l == leaderOf[s] IN
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ l \in Server /\ up[l] /\ Established(l)
    /\ acceptedEpoch[s] < acceptedEpoch[l]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = acceptedEpoch[l]]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* L:512-526: equal epochs -> ACKEPOCH carrying lastLoggedZxid/currentEpoch.  *)
SendAckEpoch(s) ==
    LET l == leaderOf[s] IN
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ l \in Server /\ up[l] /\ Established(l)
    /\ ~epochSet[s]
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ epochSet' = [epochSet EXCEPT ![s] = TRUE]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, zkState>>
    /\ NoRollback

(* Ldr:659 after waitForEpochAck quorum: self.setCurrentEpoch(epoch).        *)
LeaderPersistEpoch(l) ==
    /\ up[l] /\ Established(l) /\ phase[l] = "discovery"
    /\ currentEpoch[l] < acceptedEpoch[l]
    /\ ElectionFinished(l)
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* Ldr:660-663 setZabState(SYNCHRONIZATION); waitForNewLeaderAck(self).      *)
LeaderStartSync(l) ==
    /\ up[l] /\ Established(l) /\ phase[l] = "discovery"
    /\ currentEpoch[l] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ nlAcks' = [nlAcks EXCEPT ![l] = @ \cup {l}]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, syncBuf,
                    syncCommits, nlAckSent, usedTxn, epochSet, zkState, syncStarted, pending>>
    /\ NoRollback

-----------------------------------------------------------------------------
(***************************************************************************)
(* Learner synchronization (L:546-806 syncWithLeader)                        *)
(***************************************************************************)

(* F:108 setZabState(SYNCHRONIZATION) after registerWithLeader returns.      *)
EnterSyncPhase(s) ==
    LET l == leaderOf[s] IN
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ l \in Server /\ epochSet[s]
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ syncSource' = [syncSource EXCEPT ![s] = l]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncMode, syncJustified, syncBuf, syncCommits,
                    nlAckSent, nlAcks, usedTxn, epochSet, zkState, syncStarted, pending>>
    /\ NoRollback

SyncPre(s) ==
    LET l == syncSource[s] IN
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ l \in Server /\ leaderOf[s] = l
    /\ ~syncStarted[s] /\ ~syncJustified[s]
    /\ LeaderReadyFor(l, s)

(* LH:836-842 / LH:862-866 DIFF: the learner's data tree is a prefix of the  *)
(* leader's committed log (peerLastZxid <= maxCommittedLog; a learner ahead  *)
(* of maxCommittedLog gets TRUNC, LH:845-853, even if the extra records are  *)
(* outstanding proposals); outstanding proposals follow via startForwarding. *)
(* L:561-564 DIFF keeps the data tree, writeToTxnLog=TRUE,                   *)
(* so every following PROPOSAL/COMMIT is buffered (L:621-669).  The DIFF     *)
(* packets queued under the log read lock are consumed atomically here       *)
(* (purely local buffering, no persistent or externally visible effect).    *)
SyncDiff(s) ==
    LET l == syncSource[s] IN
    /\ SyncPre(s)
    /\ IsPrefix(applied[s], LeaderCommitHist(l))
    /\ syncMode' = [syncMode EXCEPT ![s] = "DIFF"]
    /\ syncStarted' = [syncStarted EXCEPT ![s] = TRUE]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = Suffix(LeaderHist(l), Len(applied[s]))]
    /\ syncCommits' = [syncCommits EXCEPT ![s] =
                         Suffix(LeaderCommitHist(l), Len(applied[s]))]
    /\ committed' = [committed EXCEPT ![s] =
                       CommonPrefix(applied[s], LeaderCommitHist(l))]
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    applied, snapshot, acked, commitCertified, messages,
                    syncSource, syncJustified, nlAckSent, nlAcks, usedTxn,
                    zkState, pending>>
    /\ rollbackAuthorized' = [x \in Server |-> x = s]

(* LH:845-853 TRUNC (learner ahead of maxCommittedLog); L:587-597           *)
(* truncateLog closes, truncates and reloads the database (ZKD:599-614).     *)
(* writeToTxnLog=FALSE until NEWLEADER.                                     *)
SyncTrunc(s) ==
    LET l == syncSource[s]
        tgt == LeaderCommitHist(l) IN
    /\ SyncPre(s)
    /\ IsPrefix(tgt, applied[s]) /\ applied[s] /= tgt
    /\ IsPrefix(tgt, durable[s])
    /\ syncMode' = [syncMode EXCEPT ![s] = "TRUNC"]
    /\ syncStarted' = [syncStarted EXCEPT ![s] = TRUE]
    /\ durable' = [durable EXCEPT ![s] = tgt]
    /\ appended' = [appended EXCEPT ![s] = tgt]
    /\ queued' = [queued EXCEPT ![s] = tgt]
    /\ proposed' = [proposed EXCEPT ![s] = tgt]
    /\ applied' = [applied EXCEPT ![s] = tgt]
    /\ committed' = [committed EXCEPT ![s] = tgt]
    /\ snapshot' = [snapshot EXCEPT ![s] = CommonPrefix(snapshot[s], tgt)]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = Suffix(LeaderHist(l), Len(tgt))]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ UNCHANGED <<up, electionVars, acked, commitCertified, messages,
                    syncSource, syncJustified, nlAckSent, nlAcks, usedTxn,
                    zkState, pending>>
    /\ rollbackAuthorized' = [x \in Server |-> x = s]

(* LH:557-583 SNAP; L:565-586 deserializeSnapshot replaces the data tree.    *)
(* toBeApplied PROPOSAL/COMMIT pairs arrive before NEWLEADER and are applied  *)
(* in memory (L:656-665, writeToTxnLog=FALSE); outstanding proposals stay in *)
(* packetsNotCommitted.  ABSTRACTION: SNAP is offered whenever the learner   *)
(* is not prefix-comparable with the leader or has an empty data tree        *)
(* (prior model guard); the txn-log-gap selection is not modeled.            *)
SyncSnap(s) ==
    LET l == syncSource[s]
        tgt == LeaderCommitHist(l) IN
    /\ SyncPre(s)
    /\ \/ ~Comparable(applied[s], LeaderCommitHist(l))
       \/ applied[s] = <<>>
    /\ syncMode' = [syncMode EXCEPT ![s] = "SNAP"]
    /\ syncStarted' = [syncStarted EXCEPT ![s] = TRUE]
    /\ applied' = [applied EXCEPT ![s] = tgt]
    /\ committed' = [committed EXCEPT ![s] = tgt]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = Suffix(LeaderHist(l), Len(tgt))]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    snapshot, acked, commitCertified, messages, syncSource,
                    syncJustified, nlAckSent, nlAcks, usedTxn, zkState, pending>>
    /\ rollbackAuthorized' = [x \in Server |-> x = s]

(* NEWLEADER and UPTODATE are read by the same learner thread; no packet is  *)
(* consumed between L:726 and L:760 or between L:711 and the end of          *)
(* syncWithLeader.                                                           *)
InNewLeaderWindow(s) == syncJustified[s] /\ ~nlAckSent[s]
SyncLoopOpen(s) == /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
                   /\ syncStarted[s]
                   /\ ~InNewLeaderWindow(s)
                   /\ zkState[s] /= "RUNNING"

(* L:621-642 PROPOSAL during synchronization -> packetsNotCommitted.        *)
ReceiveSyncProposal(m) ==
    LET s == m.to
        l == m.from
        e == EntryFor(m.id, m.epoch) IN
    /\ m \in messages /\ m.kind = "proposal"
    /\ SyncLoopOpen(s) /\ syncSource[s] = l
    /\ e \in Range(proposed[l])
    /\ ~Known(s, e)
    /\ \A k \in 1..Len(proposed[l]) :
          (proposed[l][k] = e) =>
              \A j \in 1..(k - 1) : proposed[l][j].epoch = e.epoch => Known(s, proposed[l][j])
    /\ syncBuf' = [syncBuf EXCEPT ![s] = Append(@, e)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                    syncMode, syncSource, syncJustified, syncCommits,
                    nlAckSent, nlAcks, usedTxn, zkState, syncStarted, pending>>
    /\ NoRollback

(* L:643-669 COMMIT during synchronization: applied in memory while         *)
(* writeToTxnLog is FALSE (SNAP/TRUNC before NEWLEADER), else recorded in    *)
(* packetsCommitted.                                                         *)
ReceiveSyncCommit(m) ==
    LET s == m.to
        l == m.from
        e == EntryFor(m.id, m.epoch) IN
    /\ m \in messages /\ m.kind = "commit"
    /\ SyncLoopOpen(s) /\ syncSource[s] = l
    /\ Known(s, e) /\ ~CommitKnown(s, e)
    /\ e \in Range(committed[l])
    /\ \A k \in 1..Len(committed[l]) :
          (committed[l][k] = e) =>
              \A j \in 1..(k - 1) : CommitKnown(s, committed[l][j])
    /\ IF syncMode[s] \in {"SNAP", "TRUNC"} /\ ~syncJustified[s]
       THEN /\ syncBuf[s] /= <<>> /\ Head(syncBuf[s]) = e
            /\ applied' = [applied EXCEPT ![s] = Append(@, e)]
            /\ committed' = [committed EXCEPT ![s] = Append(@, e)]
            /\ syncBuf' = [syncBuf EXCEPT ![s] = Tail(@)]
            /\ UNCHANGED syncCommits
       ELSE /\ syncCommits' = [syncCommits EXCEPT ![s] = Append(@, e)]
            /\ UNCHANGED <<applied, committed, syncBuf>>
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    snapshot, acked, commitCertified, syncMode, syncSource,
                    syncJustified, nlAckSent, nlAcks, usedTxn, zkState, syncStarted, pending>>
    /\ NoRollback

(* NEWLEADER, part 1 (L:726-746): SNAP/TRUNC take a snapshot of the data     *)
(* tree (L:739-741), then setCurrentEpoch(newEpoch) persists the epoch file  *)
(* (L:743, QP:2160-2164), then writeToTxnLog = TRUE.                         *)
(* UPDATE-MAP                                                                *)
(* code: L:726-746 (unchanged statements, now followed by L:748-760)        *)
(* update: Update!AffectedActions                                            *)
PersistCurrentEpoch(s) ==
    LET l == syncSource[s] IN
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncStarted[s] /\ ~syncJustified[s]
    /\ l \in Server /\ up[l] /\ role[l] = "leading"
    /\ acceptedEpoch[l] = acceptedEpoch[s]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
    /\ IF syncMode[s] \in {"SNAP", "TRUNC"}
       THEN /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
            /\ durable' = [durable EXCEPT ![s] = applied[s]]
            /\ appended' = [appended EXCEPT ![s] = applied[s]]
            /\ queued' = [queued EXCEPT ![s] = applied[s]]
            /\ proposed' = [proposed EXCEPT ![s] = applied[s]]
            /\ rollbackAuthorized' = [x \in Server |-> x = s]
       ELSE /\ UNCHANGED <<snapshot, durable, appended, queued, proposed>>
            /\ NoRollback
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, committed, applied, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncBuf, syncCommits, nlAckSent, nlAcks, usedTxn,
                    epochSet, zkState, syncStarted, pending>>

(* UPDATE-MAP                                                                *)
(* code: L:750 setSyncMode(NONE) moved from after the loop into NEWLEADER     *)
(* update: Update!AffectedActions                                            *)
ClearSyncMode(s) ==
    /\ up[s] /\ phase[s] = "sync"
    /\ InNewLeaderWindow(s)
    /\ syncMode[s] /= "NONE"
    /\ zkState[s] = "NONE"
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                    messages, syncSource, syncJustified, syncBuf, syncCommits,
                    nlAckSent, nlAcks, usedTxn, zkState, syncStarted, pending>>
    /\ NoRollback

(* UPDATE-MAP                                                                *)
(* code: L:751 zk.startupWithoutServing(); ZKS:673-696 (state INITIAL)       *)
(* update: Update!AffectedActions                                            *)
StartupWithoutServing(s) ==
    /\ up[s] /\ phase[s] = "sync"
    /\ InNewLeaderWindow(s)
    /\ syncMode[s] = "NONE"
    /\ zkState[s] = "NONE"
    /\ zkState' = [zkState EXCEPT ![s] = "INITIAL"]
    /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn>>
    /\ NoRollback

(* FZK:82-89 logRequest: pendingTxns.add + SyncRequestProcessor enqueue     *)
(* (SRP:291-297 processRequest only queues; append/fsync happen on the       *)
(* SyncThread).  Updated call sites: L:752-757 (NEWLEADER, before the ACK)   *)
(* and L:778-782 (after UPTODATE, proposals received after NEWLEADER).       *)
(* A record already in the learner pipeline is not appended twice (model     *)
(* convenience for the leaked-processor case; see analysis-report).         *)
(* UPDATE-MAP                                                                *)
(* code: L:752-757 (new), L:778-782 (retained)                               *)
(* update: Update!AffectedActions                                            *)
LogSyncProposal(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncBuf[s] /= <<>>
    /\ \/ InNewLeaderWindow(s) /\ zkState[s] = "INITIAL"
       \/ nlAckSent[s] /\ zkState[s] = "RUNNING"
    /\ LET e == Head(syncBuf[s]) IN
       /\ pending' = [pending EXCEPT ![s] = Append(@, e)]
       /\ IF e \in Range(proposed[s])
          THEN UNCHANGED <<proposed, queued>>
          ELSE /\ proposed' = [proposed EXCEPT ![s] = Append(@, e)]
               /\ queued' = [queued EXCEPT ![s] = Append(@, e)]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, electionVars, appended, durable, committed, applied,
                    snapshot, acked, commitCertified, messages, syncMode,
                    syncSource, syncJustified, syncCommits, nlAckSent, nlAcks,
                    usedTxn, zkState, syncStarted>>
    /\ NoRollback

(* L:760 writePacket(ACK newLeaderZxid, true) after packetsNotCommitted was   *)
(* handed to the SyncRequestProcessor (not after it was fsynced).            *)
(* UPDATE-MAP                                                                *)
(* code: L:748-760                                                           *)
(* update: Update!AffectedActions, Update!CommittedPersistedOnQuorum          *)
SendNewLeaderAck(s) ==
    LET l == syncSource[s] IN
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ InNewLeaderWindow(s)
    /\ syncMode[s] = "NONE" /\ zkState[s] = "INITIAL"
    /\ syncBuf[s] = <<>>
    /\ l \in Server
    /\ nlAckSent' = [nlAckSent EXCEPT ![s] = TRUE]
    /\ messages' = messages \cup
          {[kind |-> "nlack", from |-> s, to |-> l, id |-> Nil,
            epoch |-> acceptedEpoch[s]]}
    /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                    syncMode, syncSource, syncJustified, syncBuf, syncCommits,
                    nlAcks, usedTxn, zkState, syncStarted, pending>>
    /\ NoRollback

(* LH:613-624 first packet after NEWLEADER; Ldr:1546-1586 addAck while the   *)
(* NEWLEADER quorum is not formed (later acks are consumed without effect).  *)
ReceiveNewLeaderAck(m) ==
    LET l == m.to IN
    /\ m \in messages /\ m.kind = "nlack"
    /\ up[l]
    /\ nlAcks' = IF /\ role[l] = "leading"
                    /\ acceptedEpoch[l] = m.epoch
                    /\ zkState[l] = "NONE"
                 THEN [nlAcks EXCEPT ![l] = @ \cup {m.from}]
                 ELSE nlAcks
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                    syncMode, syncSource, syncJustified, syncBuf, syncCommits,
                    nlAckSent, usedTxn, zkState, syncStarted, pending>>
    /\ NoRollback

(* LH:635-643 the leader sends UPTODATE after waitForStartup; L:711-725      *)
(* UPTODATE, L:765-767 ACK then zk.startServing() (ZKS:677-680, RUNNING).    *)
UpToDateReady(s) ==
    LET l == syncSource[s] IN
    /\ l \in Server
    /\ zkState[l] = "RUNNING" /\ role[l] = "leading"
    /\ acceptedEpoch[l] = acceptedEpoch[s]
    /\ ~\E m \in messages : m.kind = "nlack" /\ m.from = s /\ m.to = l

(* UPDATE-MAP                                                                *)
(* code: L:765-767 zk.startServing() replaces zk.startup()                   *)
(* update: Update!AffectedActions                                            *)
StartServing(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ nlAckSent[s] /\ zkState[s] = "INITIAL"
    /\ UpToDateReady(s)
    /\ zkState' = [zkState EXCEPT ![s] = "RUNNING"]
    /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn>>
    /\ NoRollback

(* L:783-785 fzk.commit(zxid) for packetsCommitted (FZK:97-111): the commit   *)
(* must match the next pending transaction.                                  *)
CommitSyncPacket(s) ==
    LET e == Head(syncCommits[s]) IN
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ zkState[s] = "RUNNING" /\ nlAckSent[s]
    /\ syncBuf[s] = <<>> /\ syncCommits[s] /= <<>>
    /\ pending[s] /= <<>> /\ Head(pending[s]) = e
    /\ committed' = [committed EXCEPT ![s] = Append(@, e)]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = Tail(@)]
    /\ pending' = [pending EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    applied, snapshot, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, syncBuf, nlAckSent,
                    nlAcks, usedTxn, zkState, syncStarted>>
    /\ NoRollback

(* F:110 setZabState(BROADCAST) after syncWithLeader returns.                *)
EnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ zkState[s] = "RUNNING" /\ nlAckSent[s]
    /\ syncBuf[s] = <<>> /\ syncCommits[s] = <<>>
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

-----------------------------------------------------------------------------
(***************************************************************************)
(* Leader activation and broadcast                                           *)
(***************************************************************************)

(* Ldr:663-676 NEWLEADER quorum, Ldr:1497-1537 startZkServer: lastCommitted  *)
(* and the loaded database (every logged transaction, ZKS:480-512) become    *)
(* served state; zk.startup() (RUNNING).                                     *)
LeaderActivate(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ zkState[l] = "NONE"
    /\ l \in nlAcks[l]
    /\ Cardinality(nlAcks[l]) >= Quorum
    /\ committed' = [committed EXCEPT ![l] = applied[l]]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(applied[l])]
    /\ zkState' = [zkState EXCEPT ![l] = "RUNNING"]
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    applied, snapshot, acked, messages, syncVars, usedTxn>>
    /\ NoRollback

(* Ldr:712 setZabState(BROADCAST).                                          *)
LeaderEnterBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ zkState[l] = "RUNNING"
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, histVars, acked, commitCertified,
                    messages, syncVars, usedTxn, epochSet, zkState>>
    /\ NoRollback

(* Ldr:1236-1253 propose: outstandingProposals.put then sendPacket to the     *)
(* forwarding followers; ProposalRequestProcessor then queues the local      *)
(* SyncRequestProcessor write.                                               *)
Propose(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ zkState[l] = "RUNNING"
    /\ t \in Txn \ usedTxn
    /\ LET e == EntryFor(t, currentEpoch[l]) IN
       /\ proposed' = [proposed EXCEPT ![l] = Append(@, e)]
       /\ queued' = [queued EXCEPT ![l] = Append(@, e)]
       /\ messages' = messages \cup
             {[kind |-> "proposal", from |-> l, to |-> s,
               id |-> t, epoch |-> currentEpoch[l]] :
                 s \in {x \in Server : Forwarding(x, l)}}
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<up, electionVars, appended, durable, committed, applied,
                    snapshot, acked, commitCertified, syncVars, zkState>>
    /\ NoRollback

(* F:165-185 PROPOSAL in broadcast -> FZK.logRequest (FIFO channel).          *)
ReceiveProposal(m) ==
    LET s == m.to
        l == m.from
        e == EntryFor(m.id, m.epoch) IN
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "broadcast"
    /\ leaderOf[s] = l /\ currentEpoch[s] = m.epoch
    /\ e \in Range(proposed[l])
    /\ ~Known(s, e)
    /\ \A k \in 1..Len(proposed[l]) :
          (proposed[l][k] = e) =>
              \A j \in 1..(k - 1) : proposed[l][j].epoch = e.epoch => Known(s, proposed[l][j])
    /\ proposed' = [proposed EXCEPT ![s] = Append(@, e)]
    /\ queued' = [queued EXCEPT ![s] = Append(@, e)]
    /\ pending' = [pending EXCEPT ![s] = Append(@, e)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, electionVars, appended, durable, committed, applied,
                    snapshot, acked, commitCertified, syncMode, syncSource,
                    syncJustified, syncBuf, syncCommits, syncStarted, nlAckSent,
                    nlAcks, usedTxn, zkState>>
    /\ NoRollback

(* SRP:181-183 ZKDatabase.append (buffered FileTxnLog stream).               *)
AppendOne(s) ==
    /\ up[s]
    /\ Len(appended[s]) < Len(queued[s])
    /\ appended' = [appended EXCEPT ![s] = Append(@, queued[s][Len(appended[s]) + 1])]
    /\ UNCHANGED <<up, electionVars, proposed, queued, durable, committed,
                    applied, snapshot, acked, commitCertified, messages,
                    syncVars, usedTxn, zkState>>
    /\ NoRollback

(* SRP:227-249 flush: ZKDatabase.commit (fsync) then the ACK processor       *)
(* (leader AckRequestProcessor / learner SendAckRequestProcessor).           *)
FsyncOne(s) ==
    /\ up[s]
    /\ Len(durable[s]) < Len(appended[s])
    /\ LET e == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, e)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![e.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE /\ acked' = acked
               /\ messages' =
                    IF role[s] = "following" /\ leaderOf[s] \in Server
                    THEN messages \cup
                           {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                             id |-> e.id, epoch |-> e.epoch]}
                    ELSE messages
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, committed,
                    applied, snapshot, commitCertified, syncVars, usedTxn,
                    zkState>>
    /\ NoRollback

(* LH:654-662 ACK in the handler loop -> Ldr:975-1030 processAck: counted    *)
(* only for an outstanding proposal of the receiving leader's epoch.         *)
DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack"
    /\ up[m.to]
    /\ acked' = IF /\ role[m.to] = "leading"
                   /\ zkState[m.to] = "RUNNING"
                   /\ currentEpoch[m.to] = m.epoch
                THEN [acked EXCEPT ![m.id] = @ \cup {m.from}]
                ELSE acked
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, electionVars, histVars, commitCertified, syncVars,
                    usedTxn, zkState>>
    /\ NoRollback

(* Ldr:930-960 tryToCommit: next outstanding zxid with quorum ACKs, then     *)
(* Ldr:1139 commit(zxid) to forwarding followers.                            *)
Commit(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ zkState[l] = "RUNNING"
    /\ Outstanding(l) /= <<>>
    /\ LET e == Head(Outstanding(l)) IN
       /\ e.id = t
       /\ Cardinality(acked[t]) >= Quorum
       /\ committed' = [committed EXCEPT ![l] = Append(@, e)]
       /\ commitCertified' = [commitCertified EXCEPT ![t] = TRUE]
       /\ messages' = messages \cup
            {[kind |-> "commit", from |-> l, to |-> s,
              id |-> t, epoch |-> e.epoch] :
                 s \in {x \in Server : Forwarding(x, l)}}
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    applied, snapshot, acked, syncVars, usedTxn, zkState>>
    /\ NoRollback

(* F:204-206 COMMIT in broadcast -> FZK.commit: matches the pending head.     *)
ReceiveCommit(m) ==
    LET s == m.to
        e == EntryFor(m.id, m.epoch) IN
    /\ m \in messages /\ m.kind = "commit"
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "broadcast"
    /\ leaderOf[s] = m.from /\ currentEpoch[s] = m.epoch
    /\ pending[s] /= <<>> /\ Head(pending[s]) = e
    /\ committed' = [committed EXCEPT ![s] = Append(@, e)]
    /\ pending' = [pending EXCEPT ![s] = Tail(@)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    applied, snapshot, acked, commitCertified, syncMode,
                    syncSource, syncJustified, syncBuf, syncCommits, syncStarted,
                    nlAckSent, nlAcks, usedTxn, zkState>>
    /\ NoRollback

(* CommitProcessor -> FinalRequestProcessor -> ZKS:1761-1790 processTxn.      *)
ApplyOne(s) ==
    /\ up[s] /\ zkState[s] /= "NONE"
    /\ Len(applied[s]) < Len(committed[s])
    /\ IsPrefix(applied[s], committed[s])
    /\ LET e == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[e.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, e)]
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    committed, snapshot, acked, commitCertified, messages,
                    syncVars, usedTxn, zkState>>
    /\ NoRollback

(* SRP:183-200 / ZKS:514-540 takeSnapshot of the in-memory data tree.         *)
TakeSnapshot(s) ==
    /\ up[s] /\ snapshot[s] /= applied[s]
    /\ IsPrefix(snapshot[s], applied[s])
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                    committed, applied, acked, commitCertified, messages,
                    syncVars, usedTxn, zkState>>
    /\ NoRollback

-----------------------------------------------------------------------------
(***************************************************************************)
(* Faults                                                                    *)
(***************************************************************************)

(* Fail-stop process crash: queued/appended-but-unforced records are lost    *)
(* (FileTxnLog buffers until commit/force), volatile state is lost; epoch    *)
(* files, fsynced log records and snapshots survive.                          *)
Crash(s) ==
    /\ up[s]
    /\ up' = [up EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "offline"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ votes' = [votes EXCEPT ![s] = {}]
    /\ proposed' = [proposed EXCEPT ![s] = durable[s]]
    /\ queued' = [queued EXCEPT ![s] = durable[s]]
    /\ appended' = [appended EXCEPT ![s] = durable[s]]
    /\ committed' = [committed EXCEPT ![s] = <<>>]
    /\ applied' = [applied EXCEPT ![s] = <<>>]
    /\ epochSet' = [epochSet EXCEPT ![s] = FALSE]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ syncStarted' = [syncStarted EXCEPT ![s] = FALSE]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ nlAckSent' = [nlAckSent EXCEPT ![s] = FALSE]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ zkState' = [zkState EXCEPT ![s] = "NONE"]
    /\ messages' = DropTo(s)
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, leadersByEpoch, durable,
                    snapshot, acked, commitCertified, usedTxn>>

(* QP startup: loadDataBase -> FileTxnSnapLog.restore (snapshot + log).       *)
Restart(s) ==
    /\ ~up[s]
    /\ LET r == Persisted(s) IN
       /\ applied' = [applied EXCEPT ![s] = r]
       /\ durable' = [durable EXCEPT ![s] = r]
       /\ appended' = [appended EXCEPT ![s] = r]
       /\ queued' = [queued EXCEPT ![s] = r]
       /\ proposed' = [proposed EXCEPT ![s] = r]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, committed, snapshot, acked,
                    commitCertified, messages, syncVars, usedTxn,
                    epochSet, zkState>>
    /\ NoRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                    syncVars, usedTxn, zkState>>
    /\ NoRollback

-----------------------------------------------------------------------------
Next ==
    \/ \E s \in Server : BeginElection(s)
    \/ \E s \in Server : RestartElectionRound(s)
    \/ \E v, c \in Server : CastVote(v, c)
    \/ \E s \in Server : WinElection(s)
    \/ \E s, l \in Server : FollowLeader(s, l)
    \/ \E s \in Server : StartLeading(s)
    \/ \E s \in Server : StartFollowing(s)
    \/ \E s \in Server : LeaderProposeEpoch(s)
    \/ \E s \in Server : AcceptEpoch(s)
    \/ \E s \in Server : SendAckEpoch(s)
    \/ \E s \in Server : LeaderPersistEpoch(s)
    \/ \E s \in Server : LeaderStartSync(s)
    \/ \E s \in Server : EnterSyncPhase(s)
    \/ \E s \in Server : SyncDiff(s)
    \/ \E s \in Server : SyncTrunc(s)
    \/ \E s \in Server : SyncSnap(s)
    \/ \E m \in messages : ReceiveSyncProposal(m)
    \/ \E m \in messages : ReceiveSyncCommit(m)
    \/ \E s \in Server : PersistCurrentEpoch(s)
    \/ \E s \in Server : ClearSyncMode(s)
    \/ \E s \in Server : StartupWithoutServing(s)
    \/ \E s \in Server : LogSyncProposal(s)
    \/ \E s \in Server : SendNewLeaderAck(s)
    \/ \E m \in messages : ReceiveNewLeaderAck(m)
    \/ \E s \in Server : StartServing(s)
    \/ \E s \in Server : CommitSyncPacket(s)
    \/ \E s \in Server : EnterBroadcast(s)
    \/ \E s \in Server : LeaderActivate(s)
    \/ \E s \in Server : LeaderEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : Propose(l, t)
    \/ \E m \in messages : ReceiveProposal(m)
    \/ \E s \in Server : AppendOne(s)
    \/ \E s \in Server : FsyncOne(s)
    \/ \E m \in messages : DeliverAck(m)
    \/ \E l \in Server, t \in Txn : Commit(l, t)
    \/ \E m \in messages : ReceiveCommit(m)
    \/ \E s \in Server : ApplyOne(s)
    \/ \E s \in Server : TakeSnapshot(s)
    \/ \E s \in Server : Crash(s)
    \/ \E s \in Server : Restart(s)
    \/ \E m \in messages : DropMessage(m)

Spec == Init /\ [][Next]_allVars

-----------------------------------------------------------------------------
(* Properties kept in the reference *)

TypeOK ==
    /\ up \in [Server -> BOOLEAN]
    /\ role \in [Server -> Role]
    /\ phase \in [Server -> Phase]
    /\ leaderOf \in [Server -> (Server \cup {Nil})]
    /\ acceptedEpoch \in [Server -> Epoch]
    /\ currentEpoch \in [Server -> Epoch]
    /\ votes \in [Server -> SUBSET Server]
    /\ leadersByEpoch \in [Epoch -> SUBSET Server]
    /\ proposed \in [Server -> Seq(Entry)]
    /\ queued \in [Server -> Seq(Entry)]
    /\ appended \in [Server -> Seq(Entry)]
    /\ durable \in [Server -> Seq(Entry)]
    /\ committed \in [Server -> Seq(Entry)]
    /\ applied \in [Server -> Seq(Entry)]
    /\ snapshot \in [Server -> Seq(Entry)]
    /\ acked \in [Txn -> SUBSET Server]
    /\ commitCertified \in [Txn -> BOOLEAN]
    /\ messages \subseteq Message
    /\ syncMode \in [Server -> SyncModes]
    /\ syncSource \in [Server -> (Server \cup {Nil})]
    /\ syncJustified \in [Server -> BOOLEAN]
    /\ usedTxn \subseteq Txn
    /\ rollbackAuthorized \in [Server -> BOOLEAN]
    /\ epochSet \in [Server -> BOOLEAN]
    /\ syncBuf \in [Server -> Seq(Entry)]
    /\ syncCommits \in [Server -> Seq(Entry)]
    /\ syncStarted \in [Server -> BOOLEAN]
    /\ pending \in [Server -> Seq(Entry)]
    /\ nlAckSent \in [Server -> BOOLEAN]
    /\ nlAcks \in [Server -> SUBSET Server]
    /\ zkState \in [Server -> ZkStates]

ElectionSafety == \A e \in Epoch : Cardinality(leadersByEpoch[e]) <= 1

\* Representation migration: "leading" no longer implies an established
\* epoch (FLE decision and getEpochToPropose are now separate steps); the
\* prior meaning is "leading with a proposed epoch".
OneActiveLeaderPerEpoch ==
    \A e \in Epoch :
        Cardinality({s \in Server : /\ up[s] /\ Established(s)
                                    /\ acceptedEpoch[s] = e}) <= 1

CommittedHistoriesPrefix ==
    \A a, b \in Server : Comparable(committed[a], committed[b])

\* Revised ApplyRequiresCommitCertificate: a data tree may legitimately
\* contain restored or fast-forwarded uncommitted records while the server is
\* not serving (FileTxnSnapLog.restore, ZKS:845); delivery to clients requires
\* commit (zookeeperInternals.md:117-118).
ServingApplyCommitted ==
    \A s \in Server :
        (up[s] /\ zkState[s] = "RUNNING") =>
            /\ IsPrefix(applied[s], committed[s])
            /\ \A k \in 1..Len(applied[s]) : commitCertified[applied[s][k].id]

PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])
        /\ IsPrefix(queued[s], proposed[s])
        /\ up[s] => IsPrefix(snapshot[s], applied[s])

EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s] /\ nlAckSent[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]

NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ ServingApplyCommitted /\
          PipelinePrefix /\ EpochHistoryConsistency /\ SyncCompletionJustified

ModelSymmetry == Permutations(Server)

=============================================================================
