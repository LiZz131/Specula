------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking lens over the complete updated reference.       *)
(* It owns no behaviour: every step is an MC wrapper of a base action.     *)
(*                                                                         *)
(* Source delta (neutral commits baseline -> update):                      *)
(*   Learner.java:861-865   zk.shutdown() became                           *)
(*                          zk.shutdown(syncMode == SNAP)                  *)
(*   ZooKeeperServer.java:804-807  shutdown(true) on a non-running server  *)
(*                          now calls zkDb.clear()                         *)
(* Reference owner: base!LearnerShutdown (constant                         *)
(* UpdateFullShutdownOnSnap = TRUE selects the updated branch).            *)
(***************************************************************************)
EXTENDS MC

-----------------------------------------------------------------------------
(* Affected Actions                                                         *)
-----------------------------------------------------------------------------

\* reference: base!LearnerShutdown
\* code: Learner.java:850-866; ZooKeeperServer.java:803-855
AffectedActions == \E f \in Server : MCLearnerShutdown(f)

-----------------------------------------------------------------------------
(* Interaction Actions                                                      *)
-----------------------------------------------------------------------------

\* Producers of the state the changed exit inspects or discards:
\*  sync-mode choice and first packet  (base!ChooseSyncMode, LearnerApplySnapshot,
\*  LearnerTruncateLog; Learner.java:557-605, LearnerHandler.java:775-932),
\*  in-memory COMMIT application before NEWLEADER (base!LearnerSyncCommit;
\*  Learner.java:643-669), and the NEWLEADER durability point and mode reset
\*  (base!LearnerSyncSnapshot, LearnerPersistCurrentEpoch,
\*  LearnerNewLeaderModeNone; Learner.java:726-761).
SyncProducers ==
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : MCChooseSync(f, m)
    \/ \E f \in Server : MCApplySnapshot(f)
    \/ \E f \in Server : MCTruncateLog(f)
    \/ \E f \in Server : \E t \in Txn : MCSyncPacket(f, t)
    \/ \E f \in Server : MCSyncCommit(f)
    \/ \E f \in Server : MCSyncSnapshot(f)
    \/ \E f \in Server : MCPersistFollowerCurrent(f)
    \/ \E f \in Server : MCNewLeaderModeNone(f)
    \/ \E f \in Server : MCAckNewLeader(f)
    \/ \E f \in Server : MCUpToDate(f)
    \/ \E f \in Server : MCCompleteSync(f)
    \/ \E f \in Server : MCFollowerBroadcast(f)
    \/ \E f \in Server : MCEnterFollowerSync(f)

\* First consumers after the exit: role change, reload of a cleared
\* database (QuorumPeer.java:1257-1262), election votes and termination
\* (FastLeaderElection.java:722-747,867-875,1012-1088), re-registration.
ExitConsumers ==
    \/ \E f \in Server : MCFollowerExitToLooking(f)
    \/ \E l \in Server : MCLeaderShutdown(l)
    \/ \E s \in Server : MCEnterElectionPhase(s)
    \/ \E s \in Server : MCReload(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s, c \in Server : MCFinishElection(s, c)
    \/ \E s \in Server : MCEnterDiscovery(s)
    \/ \E f \in Server : MCPersistFollowerAccepted(f)
    \/ MCBeginElection

\* Leader establishment and the broadcast stream that is forwarded during
\* sync and later logged by the re-synced learner.
LeaderContext ==
    \/ \E l \in Server : MCLeaderProposeEpoch(l)
    \/ \E l, f \in Server : MCRecordEpochAck(l, f)
    \/ \E l \in Server : MCLeaderEpochQuorum(l)
    \/ \E l \in Server : MCLeaderStartSync(l)
    \/ \E l \in Server : MCFormNewLeaderQuorum(l)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ MCBroadcastNext

\* Crash and restart cross the changed volatile/durable boundary.
RecoveryContext ==
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)

InteractionActions ==
    \/ SyncProducers
    \/ ExitConsumers
    \/ LeaderContext
    \/ RecoveryContext

\* Omitted reference actions: periodic fuzzy snapshots (MCSnapshotNext).
\* They write only snapshotBusy/snapshotImage/snapshotPublished, which no
\* update-visible variable, guard, or property reads (checked below).
OmittedActions == MCSnapshotNext

-----------------------------------------------------------------------------
(* Focused and open specifications                                         *)
-----------------------------------------------------------------------------

FocusNext == AffectedActions \/ InteractionActions

UpdateVisible == <<serverVars, epochVars, electionVars, zabVars, logVars,
                   dbVars, syncVars, commitVars>>

\* Rely for omitted context: no update-visible variable changes; the omitted
\* actions' own (snapshot) variables may change arbitrarily within type.
EnvUpdate ==
    /\ UNCHANGED UpdateVisible
    \* per peer: optionally begin (image := applied) and/or publish (published,
    \* snapZ advance) -- the effects of BeginSnapshot / FinishSnapshot
    /\ \E b, p \in [Server -> BOOLEAN] :
          /\ snapshotBusy' \in [Server -> BOOLEAN]
          /\ snapshotImage' = [s \in Server |-> IF b[s] THEN applied[s] ELSE snapshotImage[s]]
          /\ snapshotPublished' = [s \in Server |-> IF p[s] THEN snapshotImage[s] ELSE snapshotPublished[s]]
          /\ snapZ' = [s \in Server |-> IF p[s] THEN MaxNat(snapZ[s], LastOf(snapshotImage[s])) ELSE snapZ[s]]
    \* MC bookkeeping: only the snapshot budget/coverage may move
    /\ counters' \in {counters, [counters EXCEPT !.snapshots = @ + 1]}
    /\ counters'.snapshots <= MaxSnapshots
    /\ seen' \in {seen, seen \cup {"FinishSnapshot"}}

OpenUpdateNext == FocusNext \/ EnvUpdate

\* Discharge obligation: every omitted real step satisfies the rely.
DischargeContext == [][OmittedActions => EnvUpdate]_mcvars

-----------------------------------------------------------------------------
(* Update properties                                                        *)
-----------------------------------------------------------------------------

\* Scenario U1/U2 (modeling-brief section 8). Interaction property between the
\* changed exit and its old consumers: the zxid a peer reports to the
\* election (getInitLastLoggedZxid) and to the leader in FOLLOWERINFO/ACKEPOCH
\* (Learner.java:487,524) must describe history the peer holds on disk,
\* because the leader's DIFF decision skips everything up to it
\* (LearnerHandler.java:845-869) and a DIFF NEWLEADER takes no snapshot
\* (Learner.java:555-564,739-741).
\* reference: base!LastLoggedHist, base!LearnerShutdown, base!ReloadDatabase
ReportingPhase(s) ==
    \/ role[s] = "LOOKING"
    \/ role[s] = "LEADING" /\ phase[s] = "DISCOVERY"
    \/ /\ role[s] = "FOLLOWING" /\ syncStage[s] = "IDLE" /\ ~syncComplete[s]
       /\ phase[s] \in {"ELECTION", "DISCOVERY", "SYNCHRONIZATION"}

ReportedHistoryDurable ==
    \A s \in Server :
        running[s] /\ memInit[s] /\ ReportingPhase(s)
        => Elems(memDb[s]) \subseteq Elems(durable[s])

\* Scenario U1: the updated branch's own promise, observed by the next
\* reader. After a SNAP-window exit the next reported history is reloaded
\* from disk, i.e. a peer whose stale syncMode is SNAP and that is LOOKING
\* never reports the discarded leader image.
\* reference: base!LearnerShutdown (full branch), base!ReloadDatabase
SnapExitReportsDisk ==
    \A s \in Server :
        running[s] /\ role[s] = "LOOKING" /\ syncMode[s] = "SNAP" /\ memInit[s]
        => Elems(memDb[s]) \subseteq Elems(durable[s])

UpdateInvariants ==
    ReportedHistoryDurable /\ SnapExitReportsDisk

\* Reachability canaries (expected violations = witnesses).
CanaryNoSnapAbort == NeverSnapAbort
CanaryNoReloadAfterClear == NeverReloadAfterClear
CanaryNoTruncAbortMemoryOnly == NeverTruncAbortMemoryOnly
CanaryNoInMemorySyncCommitSnap == NeverInMemorySyncCommitSnap

-----------------------------------------------------------------------------
(* Scenario-restricted schedules. Each is FocusNext conjoined with steering *)
(* guards that only DISABLE choices (roles, which peer receives a record,   *)
(* which mode a peer may get). They never add or change a transition, so   *)
(* every behaviour they admit is a behaviour of MCNext. Role names fix      *)
(* three distinct peers; symmetry is not used with them.                    *)
-----------------------------------------------------------------------------

PA == CHOOSE s \in Server : TRUE
PB == CHOOSE s \in Server \ {PA} : TRUE
PC == CHOOSE s \in Server \ {PA, PB} : TRUE

\* Steering predicate over a step of FocusNext (primed variables visible).
\* U1: PA leads epoch 1 with PB; PC is the lagging learner. PC may only
\* finish its election after a transaction is committed, and only by
\* joining the established leader.
SnapSteer ==
    /\ \A s, c \in Server : role'[s] # role[s] /\ role'[s] = "LEADING" => s = PA
    /\ (role[PC] = "LOOKING" /\ role'[PC] = "FOLLOWING") => globalCommitted # <<>>
    /\ \A v \in Server : votedFor'[v] # votedFor[v] /\ votedFor'[v] # NoServer => votedFor'[v] = PA

SnapScenarioNext == FocusNext /\ SnapSteer

\* U1 restricted to the changed branch: as SnapSteer, but TRUNC is never
\* chosen, so every learner exit inside a sync is a SNAP or DIFF exit.
SnapOnlySteer ==
    /\ SnapSteer
    /\ \A f \in Server : syncMode'[f] = "TRUNC" => syncMode[f] = "TRUNC"

\* U2: epoch 1 led by PA with PB and PC; PA proposes a second record that only
\* PA logs, then PA crashes; PB leads epoch 2 with PC and proposes a third
\* record; PA restarts, joins PB and may be sent TRUNC; PA may exit.
TruncSteer ==
    /\ \A s \in Server : role[s] # "LEADING" /\ role'[s] = "LEADING" =>
          IF electionRound = 0 THEN s = PA ELSE s = PB
    /\ \A v \in Server : votedFor'[v] # votedFor[v] /\ votedFor'[v] # NoServer =>
          votedFor'[v] = IF electionRound = 0 THEN PA ELSE PB
    \* record 2 stays on PA only
    /\ \A f \in Server \ {PA} : 2 \notin Elems(prepared'[f]) /\ 2 \notin Elems(syncBuf'[f])
    \* only PA crashes, and only once it has logged record 2
    /\ \A s \in Server : running[s] /\ ~running'[s] => s = PA /\ 2 \in Elems(durable[PA])
    /\ \A f \in Server : syncMode'[f] = "SNAP" => syncMode[f] = "SNAP"

TruncScenarioNext == FocusNext /\ TruncSteer

\* U3: like U2 but record 2 reaches PC as a forwarded sync PROPOSAL that PC
\* logs at NEWLEADER of a DIFF sync, and PC exits before UPTODATE.
DiffWindowSteer ==
    /\ \A s \in Server : role[s] # "LEADING" /\ role'[s] = "LEADING" =>
          IF electionRound = 0 THEN s = PA ELSE s = PB
    /\ \A v \in Server : votedFor'[v] # votedFor[v] /\ votedFor'[v] # NoServer =>
          votedFor'[v] = IF electionRound = 0 THEN PA ELSE PB
    /\ 2 \notin Elems(prepared'[PB]) /\ 2 \notin Elems(syncBuf'[PB])
    /\ \A s \in Server : running[s] /\ ~running'[s] => s = PA
    /\ \A f \in Server : syncMode'[f] = "SNAP" => syncMode[f] = "SNAP"

DiffWindowScenarioNext == FocusNext /\ DiffWindowSteer

\* Tighter orderings for U2/U3 (still pure restrictions). Faults are
\* confined to the scenario's learner; the leader of epoch 2 applies its
\* first record only after the learner received its sync mode; the crashed
\* first leader restarts only after epoch 2 committed a record.
NewlyApplied(s, t) == t \in Elems(memDb'[s]) /\ t \notin Elems(memDb[s])
FaultOnly(f) ==
    \A g \in Server : (syncStage'[g] = "EXITED" /\ syncStage[g] # "EXITED"
                       /\ leaderOf[g] \in Server /\ running[leaderOf[g]]
                       /\ role[leaderOf[g]] = "LEADING") => g = f

\* U2 without any crash (LearnerHandler.java:854-863 makes TRUNC the choice
\* whenever a learner reports a record the leader has committed but not yet
\* applied): PA leads with PB; PC joins after two records were proposed;
\* SNAP is never chosen; PA delays applying record 2 until PC received a
\* sync mode TRUNC; only PC suffers injected exits.
TruncLogSteer ==
    /\ \A s \in Server : role[s] # "LEADING" /\ role'[s] = "LEADING" => s = PA
    /\ \A v \in Server : votedFor'[v] # votedFor[v] /\ votedFor'[v] # NoServer => votedFor'[v] = PA
    /\ (role[PC] = "LOOKING" /\ role'[PC] = "FOLLOWING") => 2 \in Elems(prepared[PA])
    /\ \A f \in Server : syncMode'[f] = "SNAP" => syncMode[f] = "SNAP"
    /\ NewlyApplied(PA, 2) => syncMode[PC] = "TRUNC"
    /\ FaultOnly(PC)

\* MC-1 deterministic ordering: when the leader decides TRUNC for PC, the
\* record PC holds above the leader's applied frontier is already committed
\* (so startForwarding queues its PROPOSAL+COMMIT before NEWLEADER,
\* Leader.java:1293-1302, LearnerHandler.java:551-600) and not yet applied.
TruncDecisionAfterCommit ==
    (syncMode'[PC] = "TRUNC" /\ syncMode[PC] # "TRUNC")
       => \E t \in Elems(memDb[PC]) :
             t \in Elems(globalCommitted) /\ t \notin Elems(memDb[leaderOf[PC]])
SnapSteerDeterministicCommit == SnapSteer /\ TruncDecisionAfterCommit

TruncSteer2 ==
    /\ TruncSteer
    /\ FaultOnly(PA)
    /\ NewlyApplied(PB, 3) => syncMode[PA] = "TRUNC"
    /\ (~running[PA] /\ running'[PA]) => 3 \in Elems(globalCommitted)

DiffWindowSteer2 ==
    /\ DiffWindowSteer
    /\ FaultOnly(PC)
    \* PC joins epoch 1 only after record 1 committed and while record 2 is outstanding
    /\ (role[PC] = "LOOKING" /\ role'[PC] = "FOLLOWING" /\ electionRound = 0)
         => (globalCommitted # <<>> /\ 2 \in Elems(prepared[PA]))
    /\ (~running'[PA] /\ running[PA]) => syncStage[PC] = "EXITED" \/ role[PC] = "LOOKING"

=============================================================================
