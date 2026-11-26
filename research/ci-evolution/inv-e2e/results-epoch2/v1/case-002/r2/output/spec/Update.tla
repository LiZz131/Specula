------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking view for the "update" revision.                 *)
(*                                                                         *)
(* Source delta (case-002):                                                *)
(*  - Learner.java:744-760: at NEWLEADER the learner now clears the sync   *)
(*    mode, starts the request processors without serving                 *)
(*    (ZooKeeperServer.startupWithoutServing), hands every buffered        *)
(*    packetsNotCommitted entry to FollowerZooKeeperServer.logRequest and  *)
(*    only then writes the NEWLEADER ACK.                                  *)
(*  - Learner.java:763-767 / ZooKeeperServer.java:669-704: after UPTODATE  *)
(*    only startServing() (state RUNNING) remains.                         *)
(* Reference owners: base!LearnerNewLeader, base!LearnerAckNewLeader,      *)
(* base!EnterBroadcast (behaviour selected by NewLeaderLogsPending).       *)
(*                                                                         *)
(* This module defines no environment rely (EnvUpdate): every focused      *)
(* next-state relation below is a restriction of MC!MCNext, so each        *)
(* focused counterexample is also a behaviour of the full reference.       *)
(* Focused checks never replace the full-MCNext checks (Update-full.cfg).  *)
(***************************************************************************)
EXTENDS MC, UpdateProps

vars == <<allVars, mcVars>>

(* ---------------- Affected Actions (directly changed) ---------------- *)
\* reference: base!LearnerNewLeader   code: Learner.java:726-758
\* reference: base!LearnerAckNewLeader code: Learner.java:760
\* reference: base!EnterBroadcast     code: Learner.java:763-785, ZooKeeperServer.java:678-681
AffectedActions ==
    \/ \E s \in Server : MCLearnerNewLeader(s)
    \/ \E s \in Server : MCLearnerAckNewLeader(s)
    \/ \E s \in Server : MCEnterBroadcast(s)

(* ---------------- Interaction Actions (unchanged context) ------------- *)
\* producers of the NEWLEADER precondition: election/discovery/sync selection
\* consumer of the ACK: Leader.waitForNewLeaderAck -> startZkServer (LeaderBroadcast)
\* changed atomicity boundary: SyncRequestProcessor append/fsync vs ACK
\* fault boundary: crash/restart dropping the non-durable handed-off history
InteractionActions ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)

\* Omitted concrete context (new-epoch broadcast traffic): MCPropose,
\* MCReceiveProposal, MCObserveCommit, MCDeliverAck, MCCommit,
\* MCReceiveCommit, MCApplyOne, MCTakeSnapshot, MCDropMessage.  They are
\* exercised only by the full-MCNext campaign (Update-full.cfg).
FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_vars

(* ---------------- Update properties ----------------------------------- *)
\* Defined in UpdateProps.tla (EXTENDS base only) so that the same operators are
\* evaluated on trace-derived states (spec/evidence/) and in every Update cfg:
\* AckedHistoryHandedOff (U1), NewLeaderAckDurable (U2),
\* CommittedSurvivesLeaderChange (U3).

(* ---------------- Seeded focused entry point --------------------------- *)
\* UpdateSeedState is a full-MCNext state reached by TLC from MCInit (see
\* spec/output/incr/update-seed-canary.log and spec/UpdateSeed.tla): one
\* server durably logged an uncommitted epoch-1 proposal, every server is back
\* in LOOKING with a drained pipeline, and nothing has been committed yet.
NotUpdateSeed ==
    ~(/\ \A s \in Server : up[s] /\ role[s] = "looking" /\ Drained(s)
      /\ \E l \in Server :
            /\ Len(durable[l]) = 1 /\ durable[l][1].epoch = 1
            /\ \A x \in Server \ {l} : durable[x] = <<>>
      /\ everCommitted = {})

(* ---------------- Hypothetical-fix control (NOT the implementation) ---- *)
\* Control for U2/U3 only: identical to FocusedNext except that the NEWLEADER
\* ACK additionally waits for the handed-off history to be durable.  Used to
\* show the properties are satisfiable/non-vacuous and that the violations
\* isolate the ACK-before-fsync window; never reported as implementation.
FixedAckNewLeader(s) == /\ Drained(s) /\ MCLearnerAckNewLeader(s)
FixedControlNext ==
    \/ \E s \in Server : MCLearnerNewLeader(s)
    \/ \E s \in Server : FixedAckNewLeader(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ InteractionActions

=============================================================================
