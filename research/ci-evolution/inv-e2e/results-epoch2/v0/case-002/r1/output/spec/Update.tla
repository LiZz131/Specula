------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking view over the completed reference/MC suite.     *)
(* No behaviour is defined here: every action is an MC wrapper of a base   *)
(* action.  Source delta: quorum/Learner.java:744-767 and                  *)
(* ZooKeeperServer.java:669-704 (artifact commit 2efbdfc vs 1414ebf).      *)
(***************************************************************************)
EXTENDS MC

-----------------------------------------------------------------------------
(* Affected Actions: directly changed reference actions.                   *)

\* reference: base!LearnerNewLeaderStartup  code: quorum/Learner.java:748-751
\* reference: base!LearnerLogPendingOne     code: quorum/Learner.java:752-757
\* reference: base!LearnerSendNewLeaderAck  code: quorum/Learner.java:757-760
\* reference: base!LearnerUptodateStartServing code: quorum/Learner.java:711-725, :762-767
\* reference: base!LearnerUptodateLogOne     code: quorum/Learner.java:776-782
\* reference: base!LearnerUptodateCommitOne  code: quorum/Learner.java:783-785
AffectedActions ==
    \/ \E s \in Server : MCLearnerNewLeaderStartup(s)
    \/ \E s \in Server : MCLearnerLogPendingOne(s)
    \/ \E s \in Server : MCLearnerSendNewLeaderAck(s)
    \/ \E s \in Server : MCLearnerUptodateStartServing(s)
    \/ \E s \in Server : MCLearnerUptodateLogOne(s)
    \/ \E s \in Server : MCLearnerUptodateCommitOne(s)

(* Interaction Actions: unchanged producers/consumers/faults of the change.*)
\*  producer: SyncWithLeader (fills packetsNotCommitted/packetsCommitted),
\*            LearnerNewLeaderPersist (NEWLEADER epoch file) -- Learner.java:557-743
\*  consumer: LeaderStartZkServer (counts NEWLEADER ACKs, serves) -- Leader.java:661-688
\*            ReceiveProposal/ReceiveCommit during the NEWLEADER..UPTODATE window
\*            CastVote/WinElection (consume the tree zxid) -- QuorumPeer.java:1257
\*  persistence: AppendOne/FsyncOne (asynchronous flush of logRequest)
\*  fault/recovery: ServerShutdown (canShutdown guard), Crash, Restart
InteractionActions ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s \in Server, mode \in SyncModes \ {"NONE"} : MCSyncWithLeader(s, mode)
    \/ \E s \in Server : MCLearnerNewLeaderPersist(s)
    \/ \E l \in Server : MCLeaderStartZkServer(l)
    \/ \E l \in Server : MCLeaderEnterBroadcast(l)
    \/ \E s \in Server : MCLearnerEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCServerShutdown(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)

(* Omitted context: message loss and periodic snapshots.                   *)
OmittedContext ==
    \/ \E m \in messages : MCDropMessage(m)
    \/ \E s \in Server : MCTakeSnapshot(s)

\* Rely for the omitted context (base variables only): it may only remove an
\* in-flight message, or replace a RUNNING server's snapshot by its current
\* tree.  Every other update-visible variable (logs, trees, commits,
\* sync/NEWLEADER state, epochs, votes, ghosts) is preserved.
EnvDrop ==
    \E m \in messages :
        /\ messages' = messages \ {m}
        /\ UNCHANGED <<serverVars, logVars, acked, commitCertified, syncVars,
                        usedTxn, maxCommitted, ackedHist, treeFloor>>
EnvSnapshot ==
    \E s \in Server :
        /\ up[s] /\ zkState[s] = "RUNNING"
        /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
        /\ UNCHANGED <<serverVars, proposed, queued, appended, durable,
                        committed, applied, acked, commitCertified, messages,
                        syncVars, usedTxn, maxCommitted, ackedHist, treeFloor>>
EnvUpdateBase == (EnvDrop \/ EnvSnapshot) /\ rollbackAuthorized' = [x \in Server |-> FALSE]
\* In the open spec the environment is unbounded (no MC counters): a sound
\* over-approximation of the bounded real context.
EnvUpdate == EnvUpdateBase /\ UNCHANGED <<counters, seen>>

FocusNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

-----------------------------------------------------------------------------
(* Scenario checkpoint (DIFFSyncConsistencyTest precondition):             *)
(* every server is LOOKING, exactly one server has an uncommitted txn      *)
(* durably logged and in its tree, nothing was ever quorum-committed.      *)
(* Reachability from MCInit is witnessed by Update-checkpoint-witness.cfg   *)
(* (invariant NotCheckpointReached).                                        *)
CheckpointReached ==
    \E a \in Server :
       /\ \A s \in Server :
            /\ up[s] /\ role[s] = "looking" /\ zkState[s] = "OFF"
            /\ queued[s] = durable[s] /\ appended[s] = durable[s]
            /\ pending[s] = <<>>
       /\ Len(durable[a]) = 1 /\ applied[a] = durable[a]
       /\ \A s \in Server \ {a} : durable[s] = <<>> /\ applied[s] = <<>>
       /\ maxCommitted = <<>>
       /\ messages = {}
NotCheckpointReached == ~CheckpointReached

\* Concrete checkpoint state copied from the witness
\* (spec/output/mc-checkpoint-witness-r2.log, state 16: s1 led epoch 1 with
\* s2's NEWLEADER ACK, s2 left, s1 proposed t1 and shut down), re-expressed
\* over CHOOSEn server names (symmetric in Server).  MC fault counters are
\* reset: they bound exploration, not reachability.
\* CheckpointWitnessMatches (FocusWitness.cfg) re-checks FocusInit against it.
CkA == CHOOSE x \in Server : TRUE
CkB == CHOOSE x \in Server \ {CkA} : TRUE
CkC == CHOOSE x \in Server \ {CkA, CkB} : TRUE
CkT == CHOOSE t \in Txn : TRUE
CkEnt == [id |-> CkT, epoch |-> 1, ctr |-> 1]

FocusInit ==
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> IF s = CkC THEN 0 ELSE 1]
    /\ currentEpoch = [s \in Server |-> IF s = CkC THEN 0 ELSE 1]
    /\ votes = [s \in Server |-> {}]
    /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {CkA} ELSE {}]
    /\ proposed = [s \in Server |-> <<>>]
    /\ queued = [s \in Server |-> IF s = CkA THEN <<CkEnt>> ELSE <<>>]
    /\ appended = [s \in Server |-> IF s = CkA THEN <<CkEnt>> ELSE <<>>]
    /\ durable = [s \in Server |-> IF s = CkA THEN <<CkEnt>> ELSE <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> IF s = CkA THEN <<CkEnt>> ELSE <<>>]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ pending = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ zkState = [s \in Server |-> "OFF"]
    /\ learnerStep = [s \in Server |-> "none"]
    /\ nlAcks = [s \in Server |-> {}]
    /\ usedTxn = {CkT}
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ maxCommitted = <<>>
    /\ ackedHist = [s \in Server |-> <<>>]
    /\ treeFloor = [s \in Server |-> IF s = CkA THEN Zx(1, 0) ELSE NoZxid]
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0, shutdown |-> 0]
    /\ seen = {}

-----------------------------------------------------------------------------
(* Entry points *)

\* 1. Full update check: update properties over the complete MCNext.
UpdateFullSpec == MCSpec
\* 1b. Full update check from the reachable scenario checkpoint.
UpdateFullFromCheckpointSpec == FocusInit /\ [][MCNext]_<<allVars, mcVars>>
\* 2. Concrete focused check.
FocusSpec == FocusInit /\ [][FocusNext]_<<allVars, mcVars>>
\* 3. Open focused check (omitted context replaced by the rely).
OpenFocusSpec == FocusInit /\ [][OpenUpdateNext]_<<allVars, mcVars>>

\* 4. Discharge: every omitted real context step satisfies the rely.
DischargeContext == [][OmittedContext => EnvUpdateBase]_<<allVars, mcVars>>

-----------------------------------------------------------------------------
(* Update-specific properties                                              *)

\* U1 (new; Scenario U-1/U-2/U-3).  Zab leader completeness: a serving
\* leader's committed history contains every quorum-committed entry from an
\* earlier epoch.  The update's stated intent (Learner.java:747 comment) is
\* that a NEWLEADER quorum certifies the synchronized history.
\* reference: base!LeaderStartZkServer, base!Commit (ghost maxCommitted)
LeaderCompleteness ==
    \A l \in Server :
        (up[l] /\ role[l] = "leading" /\ zkState[l] = "RUNNING") =>
          \A k \in 1..Len(maxCommitted) :
             maxCommitted[k].epoch < currentEpoch[l] =>
               /\ k <= Len(committed[l])
               /\ committed[l][k] = maxCommitted[k]

\* U2 (new; interaction through old consumers).  Commit knowledge of every
\* active role instance agrees with every quorum-committed history.
CommittedAgreesWithQuorumHistory ==
    \A s \in Server :
        (up[s] /\ role[s] \in {"leading", "following"}) =>
            Comparable(committed[s], maxCommitted)

\* U3 (new; Scenario U-1).  NEWLEADER ACK durability: while a follower's
\* NEWLEADER ACK may be counted, everything it handed to the txn log has
\* reached disk ("make sure sync the uncommitted logs before commit them
\* (ACK NEWLEADER)", Learner.java:747).
\* reference: base!LearnerLogPendingOne, base!LearnerSendNewLeaderAck, base!FsyncOne
NewLeaderAckImpliesDurable ==
    \A s \in Server :
        (up[s] /\ learnerStep[s] = "acked") => durable[s] = queued[s]

\* U4 (new; Scenario U-2).  A peer that acknowledged NEWLEADER keeps
\* advertising (FLE vote / FOLLOWERINFO zxid = tree) at least the history it
\* attested until it synchronizes again.
\* reference: base!ServerShutdown, base!Restart, base!HistoryAtLeast
AckedHistoryRetained ==
    \A s \in Server :
        (up[s] /\ role[s] = "looking") =>
            ZxidGE(LastLogged(s), LastZ(ackedHist[s]))

\* Structural property keeping focused checking meaningful.
UpdateStructural ==
    \A s \in Server :
        /\ learnerStep[s] /= "none" => (role[s] = "following" /\ phase[s] = "sync")
        /\ zkState[s] = "INITIAL" => learnerStep[s] \in {"started", "acked"}
        /\ learnerStep[s] = "serving" => zkState[s] = "RUNNING"
        /\ pending[s] /= <<>> => learnerStep[s] /= "none"

\* Hunt filter for an already-analysed, update-independent counterexample
\* (spec/output/mc-update-focus-compl-bfs-r2.log, finding MC-2): TRUNC to a
\* zxid absent from the learner's log keeps the next entry
\* (FileTxnLog.truncate).  Pruning those states lets the update hunts reach
\* the update properties; the standard MC.cfg keeps exploring them.
FilterTruncExtraEntry ==
    \A s \in Server : ~(/\ syncMode[s] = "TRUNC" /\ learnerStep[s] = "synced"
                        /\ applied[s] /= committed[s])
FocusConstraint == DepthBound /\ FilterTruncExtraEntry

\* Reachability canaries for update Scenarios (expected violations).
NotEstablishedAfterCheckpoint == "established" \notin seen
NotSkippedShutdownAfterAck == "shutdownSkippedAfterAck" \notin seen
NotPendingLoggedAcked == ~({"pendingLogged", "nlAck"} \subseteq seen)
NotUptodateAfterLogging == ~({"pendingLogged", "uptodate"} \subseteq seen)
NotReElectionAfterSkippedShutdown ==
    ~(/\ "shutdownSkippedAfterAck" \in seen
      /\ \E l \in Server : role[l] = "leading" /\ zkState[l] = "RUNNING"
                            /\ currentEpoch[l] >= 3)

=============================================================================
