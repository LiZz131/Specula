------------------------------- MODULE MC -------------------------------
EXTENDS base

CONSTANT TrackCoverage

(***************************************************************************)
(* Finite exploration driver. Bounds limit executions; they are not proof. *)
(***************************************************************************)

VARIABLES counters, seen

mcvars == <<vars, counters, seen>>

CounterType == [rounds : Nat, crashes : Nat, snapshots : Nat]

MCInit ==
    /\ Init
    /\ counters = [rounds |-> 1, crashes |-> 0, snapshots |-> 0]
    /\ seen = {"Init"}

CoverageEvents == {
    "FinishElection", "FormEpochQuorum", "CompleteLearnerSync",
    "CommitProposal", "ApplyTxn", "FinishSnapshot", "RestartLoadDatabase"
}

Mark(name) ==
    seen' = IF TrackCoverage /\ name \in CoverageEvents
            THEN seen \cup {name}
            ELSE seen

MCBeginElection(c) ==
    /\ counters.rounds < 2
    /\ counters.crashes > 0
    /\ BeginElectionRound(c)
    /\ counters' = [counters EXCEPT !.rounds = @ + 1]
    /\ Mark("BeginElectionRound")

MCCastVote(v, c) ==
    /\ CastVote(v, c)
    /\ UNCHANGED counters
    /\ Mark("CastVote")

MCFinishElection(s, c) ==
    /\ FinishElection(s, c)
    /\ UNCHANGED counters
    /\ Mark("FinishElection")

MCEnterDiscovery(s) ==
    /\ running[s] /\ phase[s] = "ELECTION"
    /\ role[s] \in {"LEADING", "FOLLOWING"}
    /\ ObserveSetZabState(s, "DISCOVERY")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCPersistLeaderAccepted(l) ==
    /\ role[l] = "LEADING" /\ phase[l] = "DISCOVERY"
    /\ currentEpoch[l] < MaxEpoch
    /\ PersistAcceptedEpoch(l, currentEpoch[l] + 1)
    /\ UNCHANGED counters
    /\ Mark("PersistAcceptedEpoch")

MCPersistFollowerAccepted(f) ==
    /\ role[f] = "FOLLOWING" /\ phase[f] = "DISCOVERY"
    /\ leaderOf[f] \in Server
    /\ epochProposal[leaderOf[f]] >= 0
    /\ PersistAcceptedEpoch(f, epochProposal[leaderOf[f]])
    /\ UNCHANGED counters
    /\ Mark("PersistAcceptedEpoch")

MCRecordEpochAck(l, f) ==
    /\ RecordEpochAck(l, f)
    /\ UNCHANGED counters
    /\ Mark("RecordEpochAck")

MCFormEpochQuorum(l) ==
    /\ FormEpochQuorum(l)
    /\ UNCHANGED counters
    /\ Mark("FormEpochQuorum")

MCPersistFollowerCurrent(f) ==
    /\ role[f] = "FOLLOWING" /\ acceptedEpoch[f] > currentEpoch[f]
    /\ PersistCurrentEpoch(f, acceptedEpoch[f])
    /\ UNCHANGED counters
    /\ Mark("PersistCurrentEpoch")

MCEnterFollowerSync(f) ==
    /\ role[f] = "FOLLOWING" /\ phase[f] = "DISCOVERY"
    /\ leaderOf[f] \in Server
    /\ phase[leaderOf[f]] = "SYNCHRONIZATION"
    /\ currentEpoch[f] = currentEpoch[leaderOf[f]]
    /\ ObserveSetZabState(f, "SYNCHRONIZATION")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCChooseSync(f, m) ==
    /\ m \in {"DIFF", "TRUNC", "SNAP"}
    /\ phase[f] = "SYNCHRONIZATION"
    /\ syncMode[f] = "NONE"
    /\ ~syncComplete[f]
    /\ ChooseSyncMode(f, m)
    /\ UNCHANGED counters
    /\ Mark("ChooseSyncMode")

MCCompleteSync(f) ==
    /\ syncMode[f] \in {"DIFF", "TRUNC", "SNAP"}
    /\ ~syncComplete[f]
    /\ CompleteLearnerSync(f, leaderOf[f], syncMode[f])
    /\ UNCHANGED counters
    /\ Mark("CompleteLearnerSync")

MCFormNewLeaderQuorum(l) ==
    /\ ~newLeaderReady[l]
    /\ FormNewLeaderQuorum(l)
    /\ UNCHANGED counters
    /\ Mark("FormNewLeaderQuorum")

MCLeaderBroadcast(l) ==
    /\ role[l] = "LEADING" /\ phase[l] = "SYNCHRONIZATION"
    /\ newLeaderReady[l]
    /\ ObserveSetZabState(l, "BROADCAST")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCFollowerBroadcast(f) ==
    /\ role[f] = "FOLLOWING" /\ phase[f] = "SYNCHRONIZATION"
    /\ syncComplete[f] /\ newLeaderReady[leaderOf[f]]
    /\ ObserveSetZabState(f, "BROADCAST")
    /\ UNCHANGED counters
    /\ Mark("SetZabState")

MCLeaderPropose(l) ==
    /\ nextTxn \in Txn
    /\ LeaderPropose(l, nextTxn)
    /\ UNCHANGED counters
    /\ Mark("LeaderPropose")

MCFollowerPending(f, t) ==
    /\ FollowerPendingProposal(f, t)
    /\ UNCHANGED counters
    /\ Mark("FollowerPendingProposal")

MCQueue(s, t) ==
    /\ QueueForSync(s, t)
    /\ UNCHANGED counters
    /\ Mark("QueueForSync")

MCFlush(s, t) ==
    /\ FlushTxnLog(s, t)
    /\ UNCHANGED counters
    /\ Mark("FlushTxnLog")

MCAck(l, source, t) ==
    /\ RecordProposalAck(l, source, t)
    /\ UNCHANGED counters
    /\ Mark("RecordProposalAck")

MCCommit(l, t) ==
    /\ CommitProposal(l, t)
    /\ UNCHANGED counters
    /\ Mark("CommitProposal")

MCFollowerCommit(f, t) ==
    /\ FollowerCommit(f, t)
    /\ UNCHANGED counters
    /\ Mark("FollowerCommit")

MCApply(s, t) ==
    /\ ApplyTxn(s, t)
    /\ UNCHANGED counters
    /\ Mark("ApplyTxn")

MCBeginSnapshot(s) ==
    /\ counters.snapshots < 1
    /\ phase[s] = "BROADCAST"
    /\ BeginSnapshot(s)
    /\ counters' = [counters EXCEPT !.snapshots = @ + 1]
    /\ Mark("BeginSnapshot")

MCFinishSnapshot(s) ==
    /\ FinishSnapshot(s)
    /\ UNCHANGED counters
    /\ Mark("FinishSnapshot")

MCCrash(s) ==
    /\ counters.crashes < 1
    /\ (phase[s] = "BROADCAST" \/ snapshotBusy[s])
    /\ Crash(s)
    /\ counters' = [counters EXCEPT !.crashes = @ + 1]
    /\ Mark("Crash")

MCRestart(s) ==
    /\ ~running[s]
    /\ RestartLoadDatabase(s, acceptedEpoch[s], currentEpoch[s])
    /\ UNCHANGED counters
    /\ Mark("RestartLoadDatabase")

MCNext ==
    \/ \E c \in Server : MCBeginElection(c)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s, c \in Server : MCFinishElection(s, c)
    \/ \E s \in Server : MCEnterDiscovery(s)
    \/ \E l \in Server : MCPersistLeaderAccepted(l)
    \/ \E f \in Server : MCPersistFollowerAccepted(f)
    \/ \E l, f \in Server : MCRecordEpochAck(l, f)
    \/ \E l \in Server : MCFormEpochQuorum(l)
    \/ \E f \in Server : MCPersistFollowerCurrent(f)
    \/ \E f \in Server : MCEnterFollowerSync(f)
    \/ \E f \in Server : \E m \in Modes : MCChooseSync(f, m)
    \/ \E f \in Server : MCCompleteSync(f)
    \/ \E l \in Server : MCFormNewLeaderQuorum(l)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E f \in Server : MCFollowerBroadcast(f)
    \/ \E l \in Server : MCLeaderPropose(l)
    \/ \E f \in Server : \E t \in Txn : MCFollowerPending(f, t)
    \/ \E s \in Server : \E t \in Txn : MCQueue(s, t)
    \/ \E s \in Server : \E t \in Txn : MCFlush(s, t)
    \/ \E l, source \in Server : \E t \in Txn : MCAck(l, source, t)
    \/ \E l \in Server : \E t \in Txn : MCCommit(l, t)
    \/ \E f \in Server : \E t \in Txn : MCFollowerCommit(f, t)
    \/ \E s \in Server : \E t \in Txn : MCApply(s, t)
    \/ \E s \in Server : MCBeginSnapshot(s)
    \/ \E s \in Server : MCFinishSnapshot(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)

(***************************************************************************)
(* Diagnostic/core projection: all ordinary protocol actions, excluding    *)
(* the counter-changing election-restart, crash, and snapshot injections.  *)
(***************************************************************************)
MCCoreNext == MCNext /\ UNCHANGED counters

MCRecoveryNext ==
    MCNext /\ counters'.snapshots = counters.snapshots

MCSnapshotNext ==
    MCNext
    /\ counters'.rounds = counters.rounds
    /\ counters'.crashes = counters.crashes

\* REQ-EVIDENCE MCTypeOK
\* intent:   TypeOK holds and the MC driver's counters and coverage set stay well-typed
\* status:   model-internal
\* verified: base
\* review:   ok
MCTypeOK == TypeOK /\ counters \in [rounds : Nat, crashes : Nat, snapshots : Nat] /\ seen \subseteq TransitionNames

ReachedElection == "FinishElection" \in seen
ReachedEpochQuorum == "FormEpochQuorum" \in seen
ReachedSync == "CompleteLearnerSync" \in seen
ReachedCommit == \E t \in Txn : Quorum(commitWitness[t])
ReachedApply == \E s \in Server : Len(applied[s]) > 0
ReachedSnapshot == "FinishSnapshot" \in seen
ReachedRecovery == "RestartLoadDatabase" \in seen

\* REQ-EVIDENCE ElectionUnreachable
\* intent:   reachability canary, expected to be violated: no FinishElection step is ever recorded in the coverage set
\* status:   model-internal
\* verified: base
\* review:   ok
ElectionUnreachable == ~ReachedElection
\* REQ-EVIDENCE SyncUnreachable
\* intent:   reachability canary, expected to be violated: no CompleteLearnerSync step is ever recorded in the coverage set
\* status:   model-internal
\* verified: base
\* review:   ok
SyncUnreachable == ~ReachedSync
\* REQ-EVIDENCE CommitUnreachable
\* intent:   reachability canary, expected to be violated: no transaction ever obtains a quorum commit witness
\* status:   model-internal
\* verified: base
\* review:   ok
CommitUnreachable == ~ReachedCommit
\* REQ-EVIDENCE ApplyUnreachable
\* intent:   reachability canary, expected to be violated: no server ever applies a transaction
\* status:   model-internal
\* verified: base
\* review:   ok
ApplyUnreachable == ~ReachedApply
\* REQ-EVIDENCE SnapshotUnreachable
\* intent:   reachability canary, expected to be violated: no FinishSnapshot step is ever recorded in the coverage set
\* status:   model-internal
\* verified: base
\* review:   ok
SnapshotUnreachable == ~ReachedSnapshot
\* REQ-EVIDENCE RecoveryUnreachable
\* intent:   reachability canary, expected to be violated: no RestartLoadDatabase step is ever recorded in the coverage set
\* status:   model-internal
\* verified: base
\* review:   ok
RecoveryUnreachable == ~ReachedRecovery

(***************************************************************************)
(* Canonical existential schedule used only by the commit reachability hunt. *)
(* It removes unrelated crash/snapshot branches; the checked transition      *)
(* definitions are exactly the same ones used by MCNext.                     *)
(***************************************************************************)

WitnessLeader == CHOOSE s \in Server : TRUE
WitnessFollower == CHOOSE s \in Server \ {WitnessLeader} : TRUE

CommitHuntNext ==
    \/ \E v \in Server : MCCastVote(v, WitnessLeader)
    \/ MCFinishElection(WitnessLeader, WitnessLeader)
    \/ MCFinishElection(WitnessFollower, WitnessLeader)
    \/ MCEnterDiscovery(WitnessLeader)
    \/ MCEnterDiscovery(WitnessFollower)
    \/ MCPersistLeaderAccepted(WitnessLeader)
    \/ MCPersistFollowerAccepted(WitnessFollower)
    \/ MCRecordEpochAck(WitnessLeader, WitnessLeader)
    \/ MCRecordEpochAck(WitnessLeader, WitnessFollower)
    \/ MCFormEpochQuorum(WitnessLeader)
    \/ MCPersistFollowerCurrent(WitnessFollower)
    \/ MCEnterFollowerSync(WitnessFollower)
    \/ MCChooseSync(WitnessFollower, "DIFF")
    \/ MCCompleteSync(WitnessFollower)
    \/ MCFormNewLeaderQuorum(WitnessLeader)
    \/ MCLeaderBroadcast(WitnessLeader)
    \/ MCFollowerBroadcast(WitnessFollower)
    \/ MCLeaderPropose(WitnessLeader)
    \/ \E t \in Txn : MCFollowerPending(WitnessFollower, t)
    \/ \E t \in Txn : MCQueue(WitnessLeader, t)
    \/ \E t \in Txn : MCQueue(WitnessFollower, t)
    \/ \E t \in Txn : MCFlush(WitnessLeader, t)
    \/ \E t \in Txn : MCFlush(WitnessFollower, t)
    \/ \E t \in Txn : MCAck(WitnessLeader, WitnessLeader, t)
    \/ \E t \in Txn : MCAck(WitnessLeader, WitnessFollower, t)
    \/ \E t \in Txn : MCCommit(WitnessLeader, t)

ApplyHuntNext ==
    \/ CommitHuntNext
    \/ \E t \in Txn : MCApply(WitnessLeader, t)

SnapshotHuntNext ==
    \/ ApplyHuntNext
    \/ MCBeginSnapshot(WitnessLeader)
    \/ MCFinishSnapshot(WitnessLeader)
    \/ MCBeginSnapshot(WitnessFollower)
    \/ MCFinishSnapshot(WitnessFollower)

RecoveryHuntNext ==
    \/ CommitHuntNext
    \/ \E t \in Txn : MCApply(WitnessLeader, t)
    \/ \E t \in Txn : MCApply(WitnessFollower, t)
    \/ MCCrash(WitnessLeader)
    \/ MCCrash(WitnessFollower)
    \/ MCRestart(WitnessLeader)
    \/ MCRestart(WitnessFollower)
    \/ MCBeginElection(WitnessLeader)

Symmetry == Permutations(Server)

=============================================================================
