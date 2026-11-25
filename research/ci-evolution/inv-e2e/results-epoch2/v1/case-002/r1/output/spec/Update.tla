------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking lens over the V1 reference (base/MC).          *)
(* Source update (neutral commits baseline -> update):                    *)
(*   quorum/Learner.java:726-767  NEWLEADER branch now calls               *)
(*       zk.startupWithoutServing(), logs packetsNotCommitted via          *)
(*       FollowerZooKeeperServer.logRequest, and only then writes the      *)
(*       NEWLEADER ACK; setSyncMode(NONE)/setSoTimeout moved before the    *)
(*       ACK; after UPTODATE zk.startServing() replaces zk.startup().      *)
(*   ZooKeeperServer.java:669-680  startup() split into                   *)
(*       startupWithServerState(RUNNING|INITIAL) + startServing().          *)
(* No behavior is defined here: every Action below is an MC wrapper of a   *)
(* reference Action in base.tla.                                           *)
(***************************************************************************)
EXTENDS MC, UpdateProps

(* ---------------- Affected Actions (directly changed) ------------------ *)
\* reference: base!FollowerProcessNewLeader, base!FollowerSendNewLeaderAck
\* code: quorum/Learner.java:726-760
\* reference: base!LeaderProcessNewLeaderAck (txn ACK can now precede the
\*   NEWLEADER ACK) -- code: quorum/Learner.java:751-760, LearnerHandler.java:606-623
\* reference: base!FollowerProcessUpToDate -- code: quorum/Learner.java:711-725,765-785
\* reference: base!BeginElection (INITIAL-state exit skips shutdown)
\*   -- code: ZooKeeperServer.java:669-680,784-807; LearnerZooKeeperServer.java:155-172
\* reference: base!LeaderBroadcast (NEWLEADER-ACK quorum gate; V1 repair the
\*   update depends on) -- code: quorum/Leader.java:663-712
AffectedActions ==
    \/ \E s \in Server : MCFollowerProcessNewLeader(s)
    \/ \E s \in Server : MCFollowerSendNewLeaderAck(s)
    \/ \E m \in nlAckMsgs : MCLeaderProcessNewLeaderAck(m)
    \/ \E s \in Server : MCFollowerProcessUpToDate(s)
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E l \in Server : MCLeaderBroadcast(l)

(* ---------------- Interaction Actions (unchanged, high risk) ----------- *)
\* producer of packetsNotCommitted: base!SelectSync (LearnerHandler.syncFollower)
\* asynchronous durability + ACK ordering: base!AppendOne, base!FsyncOne
\*   (SyncRequestProcessor.java:156-252, SendAckRequestProcessor.java)
\* fault/recovery: base!Crash, base!Restart (FileTxnSnapLog.restore)
\* consumers of the persisted epoch / in-memory history: base!CastVote,
\*   base!WinElection (FastLeaderElection.java:867-884; ZooKeeperServer.loadData)
\* precondition establishment: FollowLeader, AcceptEpoch, FinishDiscovery,
\*   EnterSyncPhase; producer of a leader-only durable suffix: Propose;
\*   leader ACK accounting: DeliverAck; NEWLEADER ACK loss: DropNewLeaderAck.
InteractionActions ==
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E m \in nlAckMsgs : MCDropNewLeaderAck(m)

(* ---------------- Omitted context (covered by EnvUpdate) --------------- *)
OmittedContextActions ==
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E m \in messages : MCDropMessage(m)

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_vars

(***************************************************************************)
(* EnvUpdate: rely for the omitted context.  Evidence: the omitted Actions *)
(* never touch election/sync/NEWLEADER state, epochs, durable/appended,     *)
(* recovered, acked, ack messages or NEWLEADER ACKs; they only (a) extend   *)
(* a broadcasting follower's proposed/queued with the leader's next entry,  *)
(* (b) extend committed by an entry certified by an established leader with *)
(* quorum ACKs, (c) apply a certified committed entry, (d) take a snapshot  *)
(* of applied, and (e) add/remove non-ACK messages or drop messages.        *)
(***************************************************************************)
AckMsgs(M) == {m \in M : m.kind = "ack"}

EnvFrame ==
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, recovered,
                    acked, syncMode, syncSource, syncJustified, usedTxn,
                    syncBuf, syncKind, nlState, nlAckMsgs, nlAcks,
                    ackShadowed, zkState>>
    /\ ResetRollback
    /\ AckMsgs(messages') \subseteq AckMsgs(messages)

\* (a) ReceiveProposal: broadcasting follower appends its leader's next entry.
EnvLearnProposal(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "broadcast"
    /\ leaderOf[s] \in Server
    /\ Len(proposed[s]) < Len(proposed[leaderOf[s]])
    /\ IsPrefix(proposed[s], proposed[leaderOf[s]])
    /\ LET ent == proposed[leaderOf[s]][Len(proposed[s]) + 1] IN
       /\ proposed' = [proposed EXCEPT ![s] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<committed, applied, snapshot, commitCertified, certEpoch>>

\* (b) Commit / ReceiveCommit: certified extension of committed.
EnvCommit(s) ==
    /\ up[s] /\ Len(committed[s]) < Len(proposed[s])
    /\ LET ent == proposed[s][Len(committed[s]) + 1] IN
       /\ \/ /\ role[s] = "leading" /\ phase[s] = "broadcast"
             /\ Cardinality(acked[ent.id]) >= Quorum
          \/ /\ role[s] = "following" /\ phase[s] = "broadcast"
             /\ commitCertified[ent.id]
       /\ committed' = [committed EXCEPT ![s] = Append(@, ent)]
       /\ commitCertified' = [commitCertified EXCEPT ![ent.id] = TRUE]
       /\ certEpoch' = [certEpoch EXCEPT ![ent.id] =
                          IF @ = 0 /\ role[s] = "leading" THEN currentEpoch[s] ELSE @]
    /\ UNCHANGED <<proposed, queued, applied, snapshot>>

\* (c) ApplyOne.
EnvApply(s) ==
    /\ up[s] /\ Len(applied[s]) < Len(committed[s])
    /\ commitCertified[committed[s][Len(applied[s]) + 1].id]
    /\ applied' = [applied EXCEPT ![s] = Append(@, committed[s][Len(applied[s]) + 1])]
    /\ UNCHANGED <<proposed, queued, committed, snapshot, commitCertified, certEpoch>>

\* (d) TakeSnapshot.
EnvSnapshot(s) ==
    /\ up[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<proposed, queued, committed, applied, commitCertified, certEpoch>>

\* (e) message-only steps
EnvMessagesOnly ==
    UNCHANGED <<proposed, queued, committed, applied, snapshot, commitCertified, certEpoch>>

\* Relational rely used by the discharge obligation.
EnvUpdateRel ==
    /\ EnvFrame
    /\ \/ \E s \in Server : EnvLearnProposal(s)
       \/ \E s \in Server : EnvCommit(s)
       \/ \E s \in Server : EnvApply(s)
       \/ \E s \in Server : EnvSnapshot(s)
       \/ EnvMessagesOnly

\* Constructive environment for the open focused spec (messages unchanged;
\* only ACK messages are read by the concrete focused Actions).
EnvUpdate ==
    /\ messages' = messages     \* assigned first: EnvFrame reads messages'
    /\ UNCHANGED mcVars
    /\ EnvUpdateRel

OpenUpdateNext == FocusedNext \/ EnvUpdate
OpenSpec == MCInit /\ [][OpenUpdateNext]_vars

\* Discharge: every omitted real context step satisfies the rely (+frame).
DischargeContext == [][OmittedContextActions => EnvUpdateRel]_vars

(***************************************************************************)
(* Update properties.  Requirement evidence (non-implementation):          *)
(*  R1 Learner.java:748 "make sure sync the uncommitted logs before commit  *)
(*     them (ACK NEWLEADER)".                                               *)
(*  R2 DIFFSyncConsistencyTest (added by the update): followers that "ACK   *)
(*     NEWLEADER (which makes leader think she has the quorum support, but  *)
(*     actually not afterwards)" and fail "without persisting the proposals *)
(*     from DIFF sync" must not lose the leader's view: "followers should   *)
(*     have the same view after we shutdown this leader, otherwise it's a   *)
(*     violation of ZAB"; assertion "Data inconsistency detected!".        *)
(*  R3 Leader.java:652-655 "We have to get at least a majority of servers   *)
(*     in sync with us. We do this by waiting for the NEWLEADER packet to   *)
(*     get acknowledged".                                                   *)
(*  R4 LearnerHandler.java:606-611 "Have to wait for the first ACK ..." and *)
(*     :614-617 "Next packet was supposed to be an ACK"; Leader.java:988-993 *)
(*     ("We no longer process NEWLEADER ack with this method").             *)
(*  R5 ZooKeeperServer.java:844 "This will fast forward the database to the *)
(*     latest recorded transactions"; QuorumPeer.getLastLoggedZxid name.    *)
(***************************************************************************)

\* P1-P5 and NotCertifiedLossReached are defined in UpdateProps.tla (a pure
\* state-predicate module over base variables, shared with the Trace evidence
\* module TraceUpdateEvidence.tla); they are update properties owned by this lens.

=============================================================================
