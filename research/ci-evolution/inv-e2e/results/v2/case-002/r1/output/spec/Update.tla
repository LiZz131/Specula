------------------------------ MODULE Update ------------------------------
(* Update-focused checking lens over the complete updated reference (base/MC).
   It defines no implementation behavior of its own: every action below is an
   MC wrapper of a reference action.

   Source update (neutral commit "update"):
     Learner.syncWithLeader NEWLEADER branch (Learner.java:745-760) now
       - clears the sync mode, calls zk.startupWithoutServing() (request
         processors started, server state INITIAL),
       - hands every buffered packetsNotCommitted proposal to
         FollowerZooKeeperServer.logRequest (asynchronous SyncRequestProcessor
         enqueue) and clears the buffer,
       - then writes ACK(NEWLEADER);
     after UPTODATE it calls zk.startServing() (RUNNING) instead of
     zk.startup() (Learner.java:766-767; ZooKeeperServer.java:669-704).
   Stated intent (Learner.java:757): "make sure sync the uncommitted logs before
   commit them (ACK NEWLEADER)".

   Section 1 = Affected/Interaction actions, Section 2 = environment and
   discharge, Section 3 = update properties, Section 4 = focused initial
   states and specs. *)
EXTENDS MC, UpdateProps

\* ---------------------------------------------------------------------------
\* Section 1: actions
\* ---------------------------------------------------------------------------

\* Directly changed reference actions.
\* reference: base!ReceiveSyncPayload  code: Learner.java:559-641 (buffer consumed at NEWLEADER)
\* reference: base!ClearSyncMode       code: Learner.java:749-750 (moved before the ACK)
\* reference: base!AckNewLeader        code: Learner.java:745-760
\* reference: base!EnterBroadcast      code: Learner.java:711-725, 765-785
AffectedActions ==
    \/ \E s \in Server : MCReceiveSyncPayload(s)
    \/ \E s \in Server : MCClearSyncMode(s)
    \/ \E s \in Server : MCAckNewLeader(s)
    \/ \E s \in Server : MCEnterBroadcast(s)

\* Unchanged producers/consumers/faults of the changed result.
\*  - LeaderBroadcast consumes NEWLEADER ACKs and commits the leader history
\*    (Leader.java:663, 1547-1585, 688).
\*  - AppendOne/FsyncOne are the asynchronous SyncRequestProcessor stages that
\*    the changed code now feeds before the ACK (SyncRequestProcessor.java:166-250).
\*  - Crash/Restart cross the changed durability boundary.
\*  - BeginElection leaves a role; with server state INITIAL (updated code) the
\*    shutdown is a no-op and the pipeline keeps running (LearnerZooKeeperServer.java:155-172).
\*  - The election/discovery/sync chain establishes AckNewLeader's precondition
\*    and re-election consumes the durable result.
InteractionActions ==
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E s \in Server : MCPersistCurrentEpoch(s)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)

\* Omitted reference context (cannot change update-visible state).
OmittedContextStep ==
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E m \in messages : MCDropMessage(m)

\* ---------------------------------------------------------------------------
\* Section 2: environment (rely) for the omitted context, and discharge
\* ---------------------------------------------------------------------------

\* Update-visible state that the environment must preserve.
UpdateVisible == <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                   votes, leadersByEpoch, proposed, queued, appended, durable,
                   committed, applied, recovered, acked, commitCertified,
                   syncMode, syncSource, syncJustified, usedTxn,
                   pendingSync, nlAckSent, nlAcks, certEpoch, memHist>>

\* The environment may only (a) move a snapshot to the applied prefix within
\* the snapshot budget, or (b) drop one in-flight message within the drop budget.
EnvUpdate ==
    /\ UNCHANGED UpdateVisible
    /\ rollbackAuthorized' = [s \in Server |-> FALSE]
    /\ \/ /\ \E s \in Server :
               /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
               /\ snapshot[s] /= applied[s]
          /\ counters.snapshot < MaxSnapshot
          /\ counters' = [counters EXCEPT !.snapshot = @ + 1]
          /\ seen' = seen \cup {"snapshot"}
          /\ UNCHANGED messages
       \/ /\ \E m \in messages : messages' = messages \ {m}
          /\ counters.drop < MaxDrop
          /\ counters' = [counters EXCEPT !.drop = @ + 1]
          /\ seen' = seen \cup {"drop"}
          /\ UNCHANGED snapshot

OpenUpdateNext ==
    \/ AffectedActions
    \/ InteractionActions
    \/ EnvUpdate

\* Discharge obligation: every omitted real context step satisfies the rely.
DischargeContext == [][OmittedContextStep => EnvUpdate]_<<allVars, mcVars>>

\* ---------------------------------------------------------------------------
\* Section 3: update properties
\* ---------------------------------------------------------------------------

\* Update property predicates are defined in UpdateProps.tla (shared with the
\* trace witnesses and evidence states).  NewLeaderAckDurable is the temporal
\* (action) form of UpdateProps!NewLeaderAckDurableStep.
NewLeaderAckDurable == [][NewLeaderAckDurableStep]_<<allVars, mcVars>>

\* Witness target: an epoch-2 leader activated after BOTH other servers
\* acknowledged NEWLEADER (expected to be VIOLATED; precondition of U4 ghost hunt).
NotBothAckedActivated ==
    ~(\E x \in Server : /\ role[x] = "leading" /\ phase[x] = "broadcast"
                         /\ acceptedEpoch[x] = 2 /\ nlAcks[x] = Server
                         /\ \A y \in Server \ {x} : durable[y] = <<>>)

\* Update reachability canaries (model-internal; expected to be VIOLATED).
NotNewLeaderAckWithLog == "nlack-logged" \notin seen
NotUpToDateReached == "uptodate" \notin seen
NotHistoryActivated == "activate-history" \notin seen
NotRecoveryAfterUpdate ==
    ~({"nlack-logged", "crash", "restart", "activate-history"} \subseteq seen)

\* ---------------------------------------------------------------------------
\* Section 4: focused initial states and specs
\* ---------------------------------------------------------------------------

\* Generic epoch-1 aftermath: every server is LOOKING in epoch 1, the epoch-1
\* proposal T1 is uncommitted and durable on an arbitrary nonempty subset that
\* includes the epoch-1 leader.  These are the precondition states of the update
\* scenarios (re-election with heterogeneous logs); RecoveryShape is the
\* reachability witness target from MCInit (spec/output/update/reach-recovery-shape.log).
T1 == CHOOSE t \in Txn : TRUE
E1 == <<EntryFor(T1, 1)>>

\* Core of the epoch-1 aftermath family: everything except inert bookkeeping
\* (votes, stale epoch-1 messages that no epoch>=2 learner can accept, ACK sets).
RecoveryCore(ldr, has) ==
      /\ ldr \in has
      /\ has /= Server
      /\ up = [s \in Server |-> TRUE]
      /\ role = [s \in Server |-> "looking"]
      /\ phase = [s \in Server |-> "election"]
      /\ leaderOf = [s \in Server |-> Nil]
      /\ acceptedEpoch = [s \in Server |-> 1]
      /\ currentEpoch = [s \in Server |-> 1]
      /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {ldr} ELSE {}]
      /\ durable = [s \in Server |-> IF s \in has THEN E1 ELSE <<>>]
      /\ appended = durable
      /\ queued = durable
      /\ proposed = durable
      /\ committed = [s \in Server |-> <<>>]
      /\ applied = [s \in Server |-> <<>>]
      /\ snapshot = [s \in Server |-> <<>>]
      /\ recovered = [s \in Server |-> <<>>]
      /\ commitCertified = [t \in Txn |-> FALSE]
      /\ syncMode = [s \in Server |-> "NONE"]
      /\ syncSource = [s \in Server |-> Nil]
      /\ syncJustified = [s \in Server |-> FALSE]
      /\ usedTxn = {T1}
      /\ rollbackAuthorized = [s \in Server |-> FALSE]
      /\ pendingSync = [s \in Server |-> <<>>]
      /\ nlAckSent = [s \in Server |-> FALSE]
      /\ nlAcks = [s \in Server |-> {}]
      /\ certEpoch = [t \in Txn |-> 0]
      /\ memHist = durable

RecoveryInit ==
    \E ldr \in Server, has \in SUBSET Server :
      /\ RecoveryCore(ldr, has)
      /\ votes = [s \in Server |-> {s}]
      /\ acked = [t \in Txn |-> IF t = T1 THEN has ELSE {}]
      /\ messages = {}
      /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
      /\ seen = {}

\* Reachability target (spec/output/update/Update-reach-recovery-shape.log):
\* a state of the complete MCSpec from MCInit that matches RecoveryCore.
RecoveryShape == \E ldr \in Server, has \in SUBSET Server : RecoveryCore(ldr, has)
NotRecoveryShape == ~RecoveryShape

\* Reachable post-activation precondition (an "mc" state): the final state of
\* the U2 counterexample spec/output/update/Update-focused-quorumdurable-r1.log
\* (reached from RecoveryInit in 13 steps): leader l activated epoch 2 and
\* committed T1 after counting follower f's NEWLEADER ACK, while f holds T1
\* only in its SyncRequestProcessor queue; o is still LOOKING in epoch 1.
\* Used for consequence hunts (crash / aborted-sync interaction) whose full
\* path from RecoveryInit exceeds the BFS budget.
PostActivationInit ==
    \E l, f, o \in Server :
      /\ Cardinality({l, f, o}) = 3
      /\ up = [s \in Server |-> TRUE]
      /\ role = [s \in Server |-> IF s = l THEN "leading" ELSE IF s = f THEN "following" ELSE "looking"]
      /\ phase = [s \in Server |-> IF s = l THEN "broadcast" ELSE IF s = f THEN "sync" ELSE "election"]
      /\ leaderOf = [s \in Server |-> IF s \in {l, f} THEN l ELSE Nil]
      /\ acceptedEpoch = [s \in Server |-> IF s \in {l, f} THEN 2 ELSE 1]
      /\ currentEpoch = [s \in Server |-> IF s \in {l, f} THEN 2 ELSE 1]
      /\ votes = [s \in Server |-> IF s = l THEN {l, f} ELSE {s}]
      /\ leadersByEpoch = [e \in Epoch |-> IF e \in {1, 2} THEN {l} ELSE {}]
      /\ proposed = [s \in Server |-> IF s \in {l, f} THEN E1 ELSE <<>>]
      /\ queued = proposed
      /\ appended = [s \in Server |-> IF s = l THEN E1 ELSE <<>>]
      /\ durable = appended
      /\ committed = [s \in Server |-> IF s = l THEN E1 ELSE <<>>]
      /\ applied = [s \in Server |-> <<>>]
      /\ snapshot = [s \in Server |-> <<>>]
      /\ recovered = [s \in Server |-> IF s \in {l, f} THEN E1 ELSE <<>>]
      /\ acked = [t \in Txn |-> IF t = T1 THEN {l} ELSE {}]
      /\ commitCertified = [t \in Txn |-> t = T1]
      /\ messages = {}
      /\ syncMode = [s \in Server |-> "NONE"]
      /\ syncSource = [s \in Server |-> IF s = f THEN l ELSE Nil]
      /\ syncJustified = [s \in Server |-> s = f]
      /\ usedTxn = {T1}
      /\ rollbackAuthorized = [s \in Server |-> FALSE]
      /\ pendingSync = [s \in Server |-> <<>>]
      /\ nlAckSent = [s \in Server |-> s = f]
      /\ nlAcks = [s \in Server |-> IF s = l THEN {l, f} ELSE {}]
      /\ certEpoch = [t \in Txn |-> IF t = T1 THEN 2 ELSE 0]
      /\ memHist = [s \in Server |-> IF s = l THEN E1 ELSE <<>>]
      /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
      /\ seen = {}

\* Reachable precondition of the U4 ghost/divergence hunt: the final state of
\* spec/output/update/final-reach-bothacked.log (21 steps from RecoveryInit):
\* leader l activated epoch 2 after BOTH learners ACKed NEWLEADER with T1 only
\* queued (not durable, not in their in-memory databases).
PostActivation2Init ==
    \E l, f, o \in Server :
      /\ Cardinality({l, f, o}) = 3
      /\ up = [s \in Server |-> TRUE]
      /\ role = [s \in Server |-> IF s = l THEN "leading" ELSE "following"]
      /\ phase = [s \in Server |-> IF s = l THEN "broadcast" ELSE "sync"]
      /\ leaderOf = [s \in Server |-> l]
      /\ acceptedEpoch = [s \in Server |-> 2]
      /\ currentEpoch = [s \in Server |-> 2]
      /\ votes = [s \in Server |-> IF s = l THEN {l, f} ELSE {s}]
      /\ leadersByEpoch = [e \in Epoch |-> IF e \in {1, 2} THEN {l} ELSE {}]
      /\ proposed = [s \in Server |-> E1]
      /\ queued = proposed
      /\ appended = [s \in Server |-> IF s = l THEN E1 ELSE <<>>]
      /\ durable = appended
      /\ committed = [s \in Server |-> IF s = l THEN E1 ELSE <<>>]
      /\ applied = [s \in Server |-> <<>>]
      /\ snapshot = [s \in Server |-> <<>>]
      /\ recovered = [s \in Server |-> E1]
      /\ acked = [t \in Txn |-> IF t = T1 THEN {l} ELSE {}]
      /\ commitCertified = [t \in Txn |-> t = T1]
      /\ messages = {}
      /\ syncMode = [s \in Server |-> "NONE"]
      /\ syncSource = [s \in Server |-> IF s = l THEN Nil ELSE l]
      /\ syncJustified = [s \in Server |-> s /= l]
      /\ usedTxn = {T1}
      /\ rollbackAuthorized = [s \in Server |-> FALSE]
      /\ pendingSync = [s \in Server |-> <<>>]
      /\ nlAckSent = [s \in Server |-> s /= l]
      /\ nlAcks = [s \in Server |-> IF s = l THEN Server ELSE {}]
      /\ certEpoch = [t \in Txn |-> IF t = T1 THEN 2 ELSE 0]
      /\ memHist = [s \in Server |-> IF s = l THEN E1 ELSE <<>>]
      /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
      /\ seen = {}

FocusedNext == AffectedActions \/ InteractionActions

\* Full update check: complete MCNext from MCInit (MC.tla MCSpec).
UpdateFullSpec == MCSpec
\* Concrete focused check from the epoch-1 aftermath.
UpdateFocusedSpec == RecoveryInit /\ [][FocusedNext]_<<allVars, mcVars>>
\* Full concrete behavior from the epoch-1 aftermath (focused-only findings must
\* also be admitted here).
UpdateRecoveryFullSpec == RecoveryInit /\ [][MCNext]_<<allVars, mcVars>>
\* Consequence hunts from the reachable post-activation state.
UpdateFocusedFromActivationSpec == PostActivationInit /\ [][FocusedNext]_<<allVars, mcVars>>
UpdateFullFromActivationSpec == PostActivationInit /\ [][MCNext]_<<allVars, mcVars>>
UpdateFocusedFromActivation2Spec == PostActivation2Init /\ [][FocusedNext]_<<allVars, mcVars>>
UpdateFullFromActivation2Spec == PostActivation2Init /\ [][MCNext]_<<allVars, mcVars>>
\* Open focused check with the environment rely.
UpdateOpenSpec == RecoveryInit /\ [][OpenUpdateNext]_<<allVars, mcVars>>

=============================================================================
