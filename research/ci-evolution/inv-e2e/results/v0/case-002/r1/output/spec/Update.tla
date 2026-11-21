------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking lens over the updated reference suite.          *)
(* Source update: quorum/Learner.java syncWithLeader NEWLEADER/UPTODATE     *)
(* handling and ZooKeeperServer.java startupWithoutServing/startServing.   *)
(* All behaviour lives in base.tla / MC.tla; this module only selects      *)
(* Actions, defines update properties, an open environment, and scenario   *)
(* guidance constraints for hunts.                                         *)
(***************************************************************************)
EXTENDS MC

\* Scenario role names (assigned in cfg): SA epoch-1/2 leader, SB first
\* follower, SC late/second follower.  Used only by hunt guidance.
CONSTANTS SA, SB, SC
ASSUME {SA, SB, SC} \subseteq Server

(***************************************************************************)
(* Affected Actions: reference Actions whose implementation changed.       *)
(*  reference: base!LearnerNewLeader          code: quorum/Learner.java:726-746 *)
(*  reference: base!LearnerStartupWithoutServing code: Learner.java:749-751, *)
(*             ZooKeeperServer.java:669-704                                *)
(*  reference: base!LearnerLogPending         code: Learner.java:752-757    *)
(*  reference: base!LearnerAckNewLeader       code: Learner.java:757-760    *)
(*  reference: base!LearnerUpToDate           code: Learner.java:765-767,   *)
(*             ZooKeeperServer.java:677-680                                *)
(*  reference: base!LearnerLogAfterUpToDate / LearnerCommitAfterUpToDate   *)
(*             code: Learner.java:777-785 (now only post-NEWLEADER packets)*)
(*  reference: base!BeginElection / LearnerAbort (ExitHist: shutdown is a  *)
(*             no-op in the new INITIAL state)  code: ZooKeeperServer.java:784-805, *)
(*             LearnerZooKeeperServer.java:155-174                         *)
(***************************************************************************)
AffectedActions ==
    \/ \E s \in Server : MCLearnerNewLeader(s)
    \/ \E s \in Server : MCLearnerStartupWithoutServing(s)
    \/ \E s \in Server : MCLearnerLogPending(s)
    \/ \E s \in Server : MCLearnerAckNewLeader(s)
    \/ \E s \in Server : MCLearnerUpToDate(s)
    \/ \E s \in Server : MCLearnerLogAfterUpToDate(s)
    \/ \E s \in Server : MCLearnerCommitAfterUpToDate(s)
    \/ \E s \in Server : MCLearnerAbort(s)
    \/ \E s \in Server : MCBeginElection(s)

(***************************************************************************)
(* Interaction Actions: unchanged producers/consumers/faults of the        *)
(* changed state.  LearnerCommit is the unchanged consumer of the cleared  *)
(* packetsNotCommitted buffer (Learner.java:643-669); SelectSync /          *)
(* LeaderQueueNewLeader / Propose / Commit produce the packet order        *)
(* (LearnerHandler.java:550-601, Leader.java:1294-1330); FsyncOne/Crash    *)
(* decide durability; LeaderReceiveNewLeaderAck/LeaderBroadcast consume    *)
(* the NEWLEADER ACK; election actions consume persisted epoch/history.    *)
(***************************************************************************)
InteractionActions ==
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E l, s \in Server : MCLeaderQueueNewLeader(l, s)
    \/ \E s \in Server : MCLearnerProposal(s)
    \/ \E s \in Server : MCLearnerCommit(s)
    \/ \E m \in messages : MCLeaderReceiveNewLeaderAck(m)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E l, s \in Server : MCLeaderQueueUpToDate(l, s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)

\* Omitted reference Actions: TakeSnapshot and DropMessage.
OmittedContextActions ==
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E m \in messages : MCDropMessage(m)

(***************************************************************************)
(* EnvUpdate: rely for the omitted context.  It may replace one server's   *)
(* snapshot by its applied tree, or remove one message; nothing else       *)
(* (MC counters/canaries may record the event).                            *)
(***************************************************************************)
EnvFrame ==
    /\ UNCHANGED <<electionVars, proposed, queued, appended, durable, committed,
                   applied, recovered, acked, commitCertified, syncVars,
                   usedTxn, syncTarget, epochTarget, syncError>>
    /\ rollbackAuthorized' = [s \in Server |-> FALSE]
    /\ \E X \in SUBSET {"snapshot", "drop"} : seen' = seen \cup X
    /\ counters' \in {counters}
                     \cup (IF counters.snapshot < MaxSnapshot
                          THEN {[counters EXCEPT !.snapshot = @ + 1]} ELSE {})
                     \cup (IF counters.drop < MaxDrop
                          THEN {[counters EXCEPT !.drop = @ + 1]} ELSE {})

EnvUpdate ==
    /\ EnvFrame
    /\ \/ /\ UNCHANGED messages
          /\ \E s \in Server : /\ up[s] /\ zkState[s] = "running"
                               /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
       \/ /\ UNCHANGED snapshot
          /\ \E m \in messages : messages' = messages \ {m}

FocusedNext == (AffectedActions \/ InteractionActions) /\ UpdateEverCommitted
OpenNext == (AffectedActions \/ InteractionActions \/ EnvUpdate) /\ UpdateEverCommitted

FocusedSpec == MCInit /\ [][FocusedNext]_mcAllVars
OpenSpec == MCInit /\ [][OpenNext]_mcAllVars

\* Discharge obligation: every omitted real context step satisfies the rely.
DischargeStep == OmittedContextActions => EnvUpdate
DischargeContext == [][DischargeStep]_mcAllVars

(***************************************************************************)
(* Update properties.                                                      *)
(***************************************************************************)

\* U-P1 (new, Scenario U-NPE): no exception escapes Learner.syncWithLeader
\* from the unchanged COMMIT handler or FollowerZooKeeperServer.commit.
\* reference: base!LearnerCommit, base!LearnerCommitAfterUpToDate
NoSyncException == syncError = {}

\* U-P2 (new, Scenario U-DUR; the update's own stated intent in
\* Learner.java:748 "make sure sync the uncommitted logs before commit them
\* (ACK NEWLEADER)"): when a learner ACKs NEWLEADER, the history it was
\* synchronised to is durable at that learner.
\* reference: base!LearnerAckNewLeader
NewLeaderAckStep ==
    \A s \in Server :
        (syncStage[s] = "nlStarted" /\ syncStage'[s] = "nlAcked")
            => IsPrefix(syncTarget[s], durable'[s])
NewLeaderAckDurable == [][NewLeaderAckStep]_mcAllVars

\* U-P3 (revised from EpochHistoryConsistency, Scenario U-EPOCH): the
\* persisted current epoch and the history a server will recover / vote with
\* agree.  A crashed server's forced log, and a looking server's tree
\* (getLastLoggedZxid), contain the history certified by its current epoch.
\* reference: base!LearnerNewLeader, base!Crash, base!BeginElection
EpochHistoryRecoverable ==
    \A s \in Server :
        /\ (~up[s]) => IsPrefix(epochTarget[s], durable[s])
        /\ (up[s] /\ role[s] = "looking") => IsPrefix(epochTarget[s], DbPos(s))

\* U-P4 (interaction, Scenario U-LOSS): a committed history is never lost or
\* contradicted later (committed histories agree across time).
CommittedNeverLost == \A s \in Server : IsPrefix(committed[s], everCommitted)

\* U-P5 (interaction, Scenario U-LOSS): a newly established leader holds
\* every entry committed before it.
LeaderCompletenessStep ==
    \A l \in Server :
        (~Established(l) /\ Established(l)') => IsPrefix(everCommitted, committed'[l])
LeaderCompleteness == [][LeaderCompletenessStep]_mcAllVars

(***************************************************************************)
(* Scenario guidance (state constraints for hunts only; they restrict the  *)
(* explored behaviours and never add behaviour).                            *)
(***************************************************************************)
LeadersOf(e) == IF e \in Epoch THEN leadersByEpoch[e] ELSE {}

\* U-NPE: one epoch, SA leads, SB establishes with it, SC joins late.
GuideLateJoin ==
    /\ LeadersOf(1) \subseteq {SA}
    /\ (role[SC] = "following") => (phase[SA] = "broadcast")

\* U-NPE (strict variant): the commit quorum for the forwarded proposal is formed
\* by an already synchronised follower (SB in BROADCAST); SC's own ACKs never count.
GuideLateJoinStrict ==
    /\ GuideLateJoin
    /\ (role[SC] = "following") => (phase[SB] = "broadcast")
    /\ \A t \in Txn : SC \notin acked[t]

\* U-EPOCH / U-LOSS: SA leads epochs 1 and 2 (SB follows in 1, SC in 2),
\* SC leads epoch 3.
GuideEpochs ==
    /\ LeadersOf(1) \subseteq {SA}
    /\ LeadersOf(2) \subseteq {SA}
    /\ LeadersOf(3) \subseteq {SC}
    /\ acceptedEpoch[SC] /= 1
    /\ acceptedEpoch[SB] /= 2
    /\ (acceptedEpoch[SA] = 1 /\ role[SA] = "leading") => role[SC] = "looking"

\* U-LOSS (stronger guidance for deep simulation): SA leaves epoch 1 only after
\* its proposal is forced locally; SB stays out of epoch 2; SC out of epoch 1.
GuideLoss ==
    /\ GuideEpochs
    /\ (acceptedEpoch[SA] = 1 /\ role[SA] = "looking") => Len(durable[SA]) >= 1
    /\ (acceptedEpoch[SA] <= 1) => role[SC] = "looking"

\* U-LOSS tight guidance for BFS: additionally prune interleavings that cannot
\* matter for the storyline (SB/SC never force anything, SB stays out of
\* BROADCAST in epoch 1, only SA/SC collect votes).
GuideLossTight ==
    /\ GuideLoss
    /\ Len(appended[SB]) = 0
    /\ Len(appended[SC]) = 0
    /\ phase[SB] /= "broadcast"
    /\ \A s \in Server \ {SA, SC} : votes[s] \subseteq {s}

=============================================================================
