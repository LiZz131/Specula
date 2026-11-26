------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking lens over the updated reference (MC/base).      *)
(* Source delta: Learner.syncWithLeader NEWLEADER now starts the follower  *)
(* pipeline (ZooKeeperServer.startupWithoutServing), enqueues the buffered *)
(* packetsNotCommitted with fzk.logRequest, clears the buffer and only     *)
(* then writes the NEWLEADER ACK; UPTODATE now calls startServing.         *)
(* No Action body is copied here; every behavior is owned by base.tla.     *)
(***************************************************************************)
EXTENDS MC, UpdateProps

----------------------------------------------------------------------------
(* Affected Actions (directly changed reference Actions)                   *)
\* reference: base!LearnerNewLeader      code: Q/Learner.java:726-759
\* reference: base!LearnerAckNewLeader   code: Q/Learner.java:760
\* reference: base!LearnerUpToDate       code: Q/Learner.java:711-725,764-786;
\*                                         ZooKeeperServer.java:669-704
AffectedActions ==
    \/ \E s \in Server : MCLearnerNewLeader(s)
    \/ \E s \in Server : MCLearnerAckNewLeader(s)
    \/ \E s \in Server : MCLearnerUpToDate(s)

(* Interaction Actions: producers of the affected pre-state (sync stream), *)
(* consumers of its results (SyncRequestProcessor append/fsync/ACK, the    *)
(* leader's first-ACK read and NEWLEADER quorum, deferred commits), the    *)
(* unchanged COMMIT handler whose input buffer the update clears, and the  *)
(* crash/restart boundary that decides what survives.                      *)
\* reference: base!LeaderSyncFollower      code: Q/LearnerHandler.java:547-583,774-933
\* reference: base!LeaderSendNewLeader     code: Q/LearnerHandler.java:590-604
\* reference: base!LeaderReadNewLeaderAck  code: Q/LearnerHandler.java:609-623; Q/Leader.java:1547-1588
\* reference: base!LeaderBroadcast         code: Q/Leader.java:663-712
\* reference: base!LearnerSyncCommit       code: Q/Learner.java:643-669 (unchanged, NPE on empty buffer)
\* reference: base!FsyncOne                code: SyncRequestProcessor.java:227-252; Q/SendAckRequestProcessor.java:40-59
InteractionActions ==
    \/ \E l, s \in Server, m \in {"DIFF", "TRUNC", "SNAP"} : MCLeaderSyncFollower(l, s, m)
    \/ \E l, s \in Server : MCLeaderSendNewLeader(l, s)
    \/ \E l, s \in Server : MCLeaderReadNewLeaderAck(l, s)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E l, s \in Server : MCLeaderSendUpToDate(l, s)
    \/ \E l, s \in Server : MCLeaderProcessAck(l, s)
    \/ \E s \in Server : MCLearnerReadMode(s)
    \/ \E s \in Server : MCLearnerSyncProposal(s)
    \/ \E s \in Server : MCLearnerSyncCommit(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E s \in Server : MCReceiveProposal(s)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E l \in Server : MCCommit(l)
    \/ \E s \in Server : MCReceiveCommit(s)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)

\* Omitted context (election/discovery): MCBeginElection, MCCastVote,
\* MCElectLeader, MCElectFollow, MCLeaderProposeEpoch, MCAcceptEpoch,
\* MCFinishDiscovery, MCEnterSyncPhase.

-----------------------------------------------------------------------
(* Update-specific properties: see UpdateProps.tla *)


----------------------------------------------------------------------------
(* Concrete focused spec: one establishing/established epoch window.       *)
(* Seeded states: an epoch-1 history in which only some servers persisted  *)
(* the proposals (nothing committed), then leader s1 has established epoch *)
(* 2 (FinishDiscovery) and the others are registered followers waiting for *)
(* the sync directive.  Reachable in the full model by: epoch-1 election,  *)
(* Propose, partial Append/Fsync, abandonment, and an epoch-2 election that*)
(* s1 wins because its zxid is maximal (HistoryAtLeast).                   *)
CONSTANTS SeedLeader, SeedT1, SeedT2

SeedHists == {<<>>, <<EntryFor(SeedT1, 1)>>,
              <<EntryFor(SeedT1, 1), EntryFor(SeedT2, 1)>>}

FocusedInit ==
    \E hl \in SeedHists, hf \in [Server \ {SeedLeader} -> SeedHists] :
       LET H == [x \in Server |-> IF x = SeedLeader THEN hl ELSE hf[x]] IN
       \* the leader's zxid dominates a vote quorum; other learners may hold a
       \* divergent or longer history (TRUNC/SNAP paths)
       /\ Cardinality({x \in Server : IsPrefix(H[x], hl)}) >= Quorum
       /\ up = [x \in Server |-> TRUE]
       /\ role = [x \in Server |-> IF x = SeedLeader THEN "leading" ELSE "following"]
       /\ phase = [x \in Server |-> "sync"]
       /\ leaderOf = [x \in Server |-> SeedLeader]
       /\ acceptedEpoch = [x \in Server |-> 2]
       /\ currentEpoch = [x \in Server |-> IF x = SeedLeader THEN 2 ELSE 1]
       /\ votes = [x \in Server |-> IF x = SeedLeader THEN Server ELSE {}]
       /\ leaderEpoch = [x \in Server |-> IF x = SeedLeader THEN 2 ELSE 0]
       /\ epochAcks = [x \in Server |-> IF x = SeedLeader
                                         THEN {y \in Server \ {SeedLeader} : IsPrefix(H[y], hl)}
                                         ELSE {}]
       /\ leadersByEpoch = [e \in Epoch |-> IF e = 2 THEN {SeedLeader} ELSE {}]
       /\ queued = H /\ appended = H /\ durable = H
       /\ committed = [x \in Server |-> <<>>]
       /\ applied = [x \in Server |-> <<>>]
       /\ pendingTxns = [x \in Server |-> <<>>]
       /\ syncBase = [x \in Server |-> <<>>]
       /\ pendingNC = [x \in Server |-> <<>>]
       /\ pendingC = [x \in Server |-> <<>>]
       /\ lstage = [x \in Server |-> IF x = SeedLeader THEN "none" ELSE "mode"]
       /\ writeToTxnLog = [x \in Server |-> FALSE]
       /\ zkState = [x \in Server |-> "stopped"]
       /\ syncMode = [x \in Server |-> "NONE"]
       /\ syncJustified = [x \in Server |-> FALSE]
       /\ lhState = [x \in Server |-> "none"]
       /\ newLeaderAcks = [x \in Server |-> {}]
       /\ lq = [x \in Server |-> <<>>]
       /\ fq = [x \in Server |-> <<>>]
       /\ acked = [t \in Txn |-> {}]
       /\ commitCertified = [t \in Txn |-> FALSE]
       /\ usedTxn = TxnIds(hl)
       /\ rollbackAuthorized = [x \in Server |-> FALSE]
       /\ globalCommitted = {}
       /\ nlAckMisread = [x \in Server |-> FALSE]
       /\ syncNPE = [x \in Server |-> FALSE]
       /\ unmatchedCommit = [x \in Server |-> FALSE]
       /\ counters = [crash |-> 0, abandon |-> 0]
       /\ seen = {"leader", "established"}

FocusedNext == AffectedActions \/ InteractionActions

\* Complete MCNext from the same seeded states (full reference behavior; the
\* seeds are reachable: traces/diff-sync-uncommitted.ndjson replays through
\* such a state, see TraceOracle.tla).
SeededFullSpec == FocusedInit /\ [][MCNext]_mcAllVars
FocusedSpec == FocusedInit /\ [][FocusedNext]_mcAllVars

----------------------------------------------------------------------------
(* Open focused spec: the omitted follower-side election context of a      *)
(* fixed, already established epoch is summarized by EnvUpdate.            *)
(* EnvUpdate may: make any up non-looking server give up its role (the     *)
(* visible effects of BeginElection: drain, connection teardown, volatile  *)
(* learner state reset, bounded by MaxAbandon); let a looking server join  *)
(* an established leader without votes (relaxed ElectFollow out-of-        *)
(* election path); register it for that leader's epoch without counting    *)
(* its ACKEPOCH (AcceptEpoch once discovery is over); and enter SYNC.      *)
(* It never creates leaders or epochs, never truncates or extends durable  *)
(* history except by the drain, and leaves commits/acks/oracles untouched.*)
EnvLeave(s) == role[s] /= "looking" /\ MCBeginElection(s)
EnvJoin(s, c) ==
    /\ up[s] /\ s /= c /\ role[s] = "looking"
    /\ up[c] /\ role[c] = "leading" /\ phase[c] \in {"sync", "broadcast"}
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leaderEpoch,
                    epochAcks, leadersByEpoch, logVars, learnerVars,
                    handlerVars, commitVars, ghostVars, mcVars>>
    /\ ResetRollback
EnvRegister(s) ==
    /\ leaderOf[s] \in Server
    /\ phase[leaderOf[s]] \in {"sync", "broadcast"}
    /\ MCAcceptEpoch(s)
EnvEnterSync(s) == MCEnterSyncPhase(s)

EnvUpdate ==
    \/ \E s \in Server : EnvLeave(s)
    \/ \E s, c \in Server : EnvJoin(s, c)
    \/ \E s \in Server : EnvRegister(s)
    \/ \E s \in Server : EnvEnterSync(s)

OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate
OpenSpec == FocusedInit /\ [][OpenUpdateNext]_mcAllVars

----------------------------------------------------------------------------
(* Discharge: in the FULL model, every omitted real context step whose      *)
(* target leader is already established (the open spec's claim scope) is   *)
(* an EnvUpdate step or leaves every variable read by the focused Actions  *)
(* and properties unchanged.  Epoch creation (ElectLeader,                 *)
(* LeaderProposeEpoch, FinishDiscovery, vote-path ElectFollow and counted  *)
(* AcceptEpoch while the leader is in DISCOVERY) is outside the open claim *)
(* and covered only by the full MCNext update check.                       *)
visibleVars == <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                 leaderEpoch, logVars, learnerVars, handlerVars, commitVars,
                 ghostVars>>

Established(c) == c \in Server /\ role[c] = "leading" /\ phase[c] \in {"sync", "broadcast"}

OmittedInScope ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s, c \in Server : Established(c) /\ MCElectFollow(s, c)
    \/ \E s \in Server : Established(leaderOf[s]) /\ MCAcceptEpoch(s)
    \/ \E s \in Server : MCEnterSyncPhase(s)

DischargeStep == OmittedInScope => (EnvUpdate \/ UNCHANGED visibleVars)
DischargeContext == [][DischargeStep]_mcAllVars

----------------------------------------------------------------------------
(* Non-vacuity canaries for the update Scenarios (violation = witness).    *)
NotUpdateDurabilityGap ==   \* a NEWLEADER quorum forms while a learner's enqueued entry is not durable
    ~(\E l \in Server : role[l] = "leading" /\ phase[l] = "broadcast"
          /\ \E s \in newLeaderAcks[l] : ~IsPrefix(durable[l], durable[s]))
NotNlLoggedWitness == NotNlLoggedReached
NotAckBeforeNlAckWitness == NotAckBeforeNlAckReached
NotCommitAfterNlWitness == NotCommitAfterNlReached

=============================================================================
