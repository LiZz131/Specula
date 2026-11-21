------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking lens for the source update                       *)
(*   "baseline" -> "update" (Learner.syncWithLeader NEWLEADER handling and  *)
(*   ZooKeeperServer.startupWithoutServing/startServing).                   *)
(* All behavior is owned by base.tla/MC.tla; this module only selects       *)
(* actions, defines update properties, focused/open specs and discharge.    *)
(*                                                                         *)
(* Source -> reference -> Update mapping                                     *)
(*   L:743      setCurrentEpoch (unchanged, now followed by logging)          *)
(*              -> base!PersistCurrentEpoch      -> AffectedActions         *)
(*   L:750      setSyncMode(NONE) moved into NEWLEADER                         *)
(*              -> base!ClearSyncMode            -> AffectedActions         *)
(*   L:751, ZKS:673-696 startupWithoutServing (INITIAL)                       *)
(*              -> base!StartupWithoutServing    -> AffectedActions         *)
(*   L:752-757  logRequest(packetsNotCommitted) before the NEWLEADER ACK       *)
(*              -> base!LogSyncProposal          -> AffectedActions         *)
(*   L:760      ACK NEWLEADER after enqueueing (not after fsync)              *)
(*              -> base!SendNewLeaderAck         -> AffectedActions,        *)
(*                 CommittedPersistedOnQuorum, LeaderCompleteness           *)
(*   L:765-767, ZKS:677-680 startServing (RUNNING) replaces startup()          *)
(*              -> base!StartServing             -> AffectedActions         *)
(*   ZKS:784 canShutdown with the new INITIAL learner state (unchanged code,  *)
(*              newly reachable after logging) -> base!BeginElection        *)
(*                                                -> InteractionActions      *)
(*   Variables zkState/syncBuf/syncCommits/nlAckSent/nlAcks/epochSet are     *)
(*   reference state introduced to express the changed ordering; their      *)
(*   effect is observed through CommittedPersistedOnQuorum and              *)
(*   LeaderCompleteness below.                                              *)
(***************************************************************************)
EXTENDS MC, UpdateProps

-----------------------------------------------------------------------------
(* Affected actions: MC forms of every directly changed reference action. *)
AffectedActions ==
    \/ \E s \in Server : MCPersistCurrentEpoch(s)
    \/ \E s \in Server : MCClearSyncMode(s)
    \/ \E s \in Server : MCStartupWithoutServing(s)
    \/ \E s \in Server : MCLogSyncProposal(s)
    \/ \E s \in Server : MCSendNewLeaderAck(s)
    \/ \E s \in Server : MCStartServing(s)

(* Interaction actions kept concrete: producers of the sync buffer, the     *)
(* persistence consumer (SyncRequestProcessor), the NEWLEADER-quorum        *)
(* consumer (leader activation), crash/restart/re-election, and the         *)
(* INITIAL-state shutdown path.                                             *)
InteractionActions ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E s \in Server : MCRestartElectionRound(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCStartLeading(s)
    \/ \E s \in Server : MCStartFollowing(s)
    \/ \E s \in Server : MCLeaderProposeEpoch(s)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E s \in Server : MCSendAckEpoch(s)
    \/ \E s \in Server : MCLeaderPersistEpoch(s)
    \/ \E s \in Server : MCLeaderStartSync(s)
    \/ \E s \in Server : MCEnterSyncPhase(s)
    \/ \E s \in Server : MCSyncDiff(s)
    \/ \E s \in Server : MCSyncTrunc(s)
    \/ \E s \in Server : MCSyncSnap(s)
    \/ \E m \in messages : MCReceiveSyncProposal(m)
    \/ \E m \in messages : MCReceiveSyncCommit(m)
    \/ \E m \in messages : MCReceiveNewLeaderAck(m)
    \/ \E s \in Server : MCCommitSyncPacket(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ \E s \in Server : MCLeaderActivate(s)
    \/ \E s \in Server : MCLeaderEnterBroadcast(s)
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

(* Omitted real context actions (covered by EnvUpdate, discharged below). *)
OmittedContextActions ==
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E m \in messages : MCDropMessage(m)

(* Rely: the environment may persist a prefix of a server's data tree as a *)
(* snapshot (bounded by the snapshot budget) or lose one in-flight message *)
(* (bounded by the drop budget); it changes nothing else.                   *)
EnvUpdate ==
    \/ \E s \in Server :
         /\ counters.snapshot < MaxSnapshot
         /\ up[s]
         /\ \E n \in 0..Len(applied[s]) :
              /\ IsPrefix(snapshot[s], SubSeq(applied[s], 1, n))
              /\ snapshot' = [snapshot EXCEPT ![s] = SubSeq(applied[s], 1, n)]
         /\ counters' = [counters EXCEPT !.snapshot = @ + 1]
         /\ UNCHANGED <<up, electionVars, proposed, queued, appended, durable,
                         committed, applied, acked, commitCertified, messages,
                         syncVars, usedTxn, zkState>>
         /\ NoRollback
    \/ /\ counters.drop < MaxDrop
       /\ \E m \in messages : messages' = messages \ {m}
       /\ counters' = [counters EXCEPT !.drop = @ + 1]
       /\ UNCHANGED <<up, electionVars, histVars, acked, commitCertified,
                       syncVars, usedTxn, zkState>>
       /\ NoRollback

ConcreteFocusNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

-----------------------------------------------------------------------------------------------------------------------------------------------------
(* Update properties are defined once in UpdateProps.tla (shared with the  *)
(* trace-evidence module): CommittedPersistedOnQuorum, LeaderCompleteness, *)
(* UpdateProperties, UpdateControl.                                       *)

-----------------------------------------------------------------------------
(* Focused initial states.  FocusInit is a state of the full MCSpec reached *)
(* after one leader epoch in which s1 proposed and fsynced t1 that no other *)
(* server received, followed by every server stepping down (BeginElection  *)
(* flushes and fast-forwards).  Reachability from MCInit is witnessed by    *)
(* the canary run Update-reach-focusinit.cfg (CanaryFocusInitShape).        *)
FocusLeader == CHOOSE s \in Server : TRUE
FocusTxn == CHOOSE t \in Txn : TRUE
FocusHist == <<EntryFor(FocusTxn, 1)>>
FocusPeer == CHOOSE s \in Server \ {FocusLeader} : TRUE

FocusShape ==
    /\ \A s \in Server : up[s] /\ role[s] = "looking" /\ phase[s] = "election"
    /\ \A s \in Server : zkState[s] = "NONE" /\ syncMode[s] = "NONE"
    /\ \E a, b \in Server :
         /\ a /= b
         /\ acceptedEpoch[a] = 1 /\ currentEpoch[a] = 1
         /\ durable[a] = <<EntryFor(FocusTxn, 1)>>
         /\ applied[a] = durable[a]
         /\ acceptedEpoch[b] = 1 /\ currentEpoch[b] = 1
         /\ durable[b] = <<>> /\ applied[b] = <<>>
         /\ \A c \in Server \ {a, b} : durable[c] = <<>> /\ applied[c] = <<>>
                                        /\ currentEpoch[c] = 0
    /\ ~\E t \in Txn : commitCertified[t]

CanaryFocusInitShape == ~FocusShape

\* FocusInit for an arbitrary renaming (a = leader with t1, b = peer).
\* `votes` is excluded from the exact match: every LOOKING server can reset
\* its own vote set with RestartElectionRound (a new FLE round).
FocusStateWith(a, b) ==
    LET h == FocusHist IN
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> IF s \in {a, b} THEN 1 ELSE 0]
    /\ currentEpoch = [s \in Server |-> IF s \in {a, b} THEN 1 ELSE 0]
    /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {a} ELSE {}]
    /\ proposed = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ queued = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ appended = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ durable = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> IF t = FocusTxn THEN {a} ELSE {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ usedTxn = {FocusTxn}
    /\ epochSet = [s \in Server |-> FALSE]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ syncStarted = [s \in Server |-> FALSE]
    /\ pending = [s \in Server |-> <<>>]
    /\ nlAckSent = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ zkState = [s \in Server |-> "NONE"]
CanaryFocusInitExact == ~\E a, b \in Server : a /= b /\ FocusStateWith(a, b)

FocusInit ==
    LET a == FocusLeader
        b == FocusPeer
        h == FocusHist IN
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> IF s \in {a, b} THEN 1 ELSE 0]
    /\ currentEpoch = [s \in Server |-> IF s \in {a, b} THEN 1 ELSE 0]
    /\ votes = [s \in Server |-> {s}]
    /\ leadersByEpoch = [e \in Epoch |-> IF e = 1 THEN {a} ELSE {}]
    /\ proposed = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ queued = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ appended = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ durable = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> IF t = FocusTxn THEN {a} ELSE {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ usedTxn = {FocusTxn}
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ epochSet = [s \in Server |-> FALSE]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ syncStarted = [s \in Server |-> FALSE]
    /\ pending = [s \in Server |-> <<>>]
    /\ nlAckSent = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ zkState = [s \in Server |-> "NONE"]
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]

(* FocusInit2: the final state of the TLC counterexample to               *)
(* CommittedPersistedOnQuorum found from FocusInit (output/mc-shakedown-    *)
(* concrete.log, 20 states; source "mc").  Leader a has activated epoch 2   *)
(* committing t1 on a NEWLEADER quorum {a, b} while b's copy of t1 is only  *)
(* queued (not appended, not fsynced) and b's server is INITIAL.            *)
FocusThird == CHOOSE s \in Server \ {FocusLeader, FocusPeer} : TRUE
FocusInit2 ==
    LET a == FocusLeader
        b == FocusPeer
        c == FocusThird
        h == FocusHist IN
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> IF s = a THEN "leading"
                                ELSE IF s = b THEN "following" ELSE "looking"]
    /\ phase = [s \in Server |-> IF s \in {a, b} THEN "sync" ELSE "election"]
    /\ leaderOf = [s \in Server |-> IF s \in {a, b} THEN a ELSE Nil]
    /\ acceptedEpoch = [s \in Server |-> IF s \in {a, b} THEN 2 ELSE 0]
    /\ currentEpoch = [s \in Server |-> IF s \in {a, b} THEN 2 ELSE 0]
    /\ votes = [s \in Server |-> IF s = a THEN {a, b} ELSE {s}]
    /\ leadersByEpoch = [e \in Epoch |-> IF e \in {1, 2} THEN {a} ELSE {}]
    /\ proposed = [s \in Server |-> IF s \in {a, b} THEN h ELSE <<>>]
    /\ queued = [s \in Server |-> IF s \in {a, b} THEN h ELSE <<>>]
    /\ appended = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ durable = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ committed = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ applied = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ snapshot = [s \in Server |-> IF s = a THEN h ELSE <<>>]
    /\ acked = [t \in Txn |-> IF t = FocusTxn THEN {a} ELSE {}]
    /\ commitCertified = [t \in Txn |-> t = FocusTxn]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> IF s = b THEN a ELSE Nil]
    /\ syncJustified = [s \in Server |-> s = b]
    /\ usedTxn = {FocusTxn}
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ epochSet = [s \in Server |-> s \in {a, b}]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> IF s = b THEN h ELSE <<>>]
    /\ syncStarted = [s \in Server |-> s = b]
    /\ pending = [s \in Server |-> IF s = b THEN h ELSE <<>>]
    /\ nlAckSent = [s \in Server |-> s = b]
    /\ nlAcks = [s \in Server |-> IF s = a THEN {a, b} ELSE {}]
    /\ zkState = [s \in Server |-> IF s = a THEN "RUNNING"
                                   ELSE IF s = b THEN "INITIAL" ELSE "NONE"]
    /\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]

(* Hunt-only search restriction (never part of a specification): exclude  *)
(* the INITIAL-state learner failure path so that TLC must find loss       *)
(* through a process crash (Scenario 5 crash variant).  Any path found is  *)
(* a behavior of the unrestricted spec.                                    *)
NoInitialStateFailure ==
    ~\E s \in Server : zkState[s] = "INITIAL" /\ up'[s] /\ zkState'[s] = "NONE"

-----------------------------------------------------------------------------
(* Entry points *)

\* 1. Full update check: update properties over complete MCNext.
UpdateFullSpec == MCSpec
\* 1b. Full MCNext started from the focused (reachable) state.
UpdateFullFromFocusSpec == FocusInit /\ [][MCNext]_vars
\* 2. Concrete focused check.
UpdateConcreteSpec == FocusInit /\ [][ConcreteFocusNext]_vars
\* 2c. Concrete focused check continued from the mc-sourced FocusInit2.
UpdateConcreteSpec2 == FocusInit2 /\ [][ConcreteFocusNext]_vars
\* 1c. Full MCNext from FocusInit2.
UpdateFullFromFocus2Spec == FocusInit2 /\ [][MCNext]_vars
\* 3. Open focused check.
UpdateOpenSpec == FocusInit /\ [][OpenUpdateNext]_vars
\* 4. Discharge: every omitted context step satisfies the rely.
DischargeStep == OmittedContextActions => EnvUpdate
DischargeContext == [][DischargeStep]_vars

=============================================================================
