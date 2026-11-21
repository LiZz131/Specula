------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

(***************************************************************************)
(* Code-faithful finite abstraction of the exact-old ZooKeeper Zab path.  *)
(* Histories contain dense transaction identifiers in zxid order.          *)
(***************************************************************************)

CONSTANTS Server, MaxEpoch, MaxTxn, NoServer

Txn == 1..MaxTxn
Roles == {"LOOKING", "LEADING", "FOLLOWING"}
Phases == {"ELECTION", "DISCOVERY", "SYNCHRONIZATION", "BROADCAST"}
Modes == {"NONE", "DIFF", "TRUNC", "SNAP"}
TransitionNames == {
    "Init", "RestartLoadDatabase", "GracefulShutdown", "Crash",
    "BeginElectionRound", "CastVote", "FinishElection",
    "SetPeerState", "SetZabState", "PersistAcceptedEpoch", "PersistCurrentEpoch",
    "RecordEpochAck", "FormEpochQuorum", "ChooseSyncMode",
    "CompleteLearnerSync", "FormNewLeaderQuorum", "LeaderPropose",
    "FollowerPendingProposal", "QueueForSync", "FlushTxnLog",
    "RecordProposalAck", "CommitProposal", "FollowerCommit",
    "ApplyTxn", "BeginSnapshot", "FinishSnapshot"
}

VARIABLES
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    prepared, syncQueued, pending, durable, recoveryVisible,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished

vars == <<
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    prepared, syncQueued, pending, durable, recoveryVisible,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished
>>

Quorum(q) == q \subseteq Server /\ Cardinality(q) * 2 > Cardinality(Server)
Elems(h) == {h[n] : n \in 1..Len(h)}
TxnOrder == [n \in Txn |-> n]
PrefixOf(a, b) == \E n \in 0..Len(b) : a = SubSeq(b, 1, n)
AppendOnce(h, t) == IF t \in Elems(h) THEN h ELSE Append(h, t)
MaxNat(a, b) == IF a >= b THEN a ELSE b
MinNat(a, b) == IF a <= b THEN a ELSE b
ReconciledDurable(f, l) ==
    SubSeq(prepared[l], 1,
           MaxNat(Len(committed[l]),
                  MinNat(Len(durable[f]), Len(prepared[l]))))
OrderedFragment(h) ==
    \A a, b \in 1..Len(h) : a < b => h[a] < h[b]
ElectionUpToDate(c) ==
    \A v \in Server :
        running[v] =>
            \/ currentEpoch[c] > currentEpoch[v]
            \/ currentEpoch[c] = currentEpoch[v]
               /\ Len(durable[c]) >= Len(durable[v])

Init ==
    /\ running = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "LOOKING"]
    /\ phase = [s \in Server |-> "ELECTION"]
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ leaderOf = [s \in Server |-> NoServer]
    /\ acceptedEpoch = [s \in Server |-> 0]
    /\ currentEpoch = [s \in Server |-> 0]
    /\ epochProposal = [s \in Server |-> 0]
    /\ electionRound = 0
    /\ votedFor = [s \in Server |-> NoServer]
    /\ electionVotes = [s \in Server |-> {}]
    /\ epochAcks = [s \in Server |-> {}]
    /\ newLeaderAcks = [s \in Server |-> {}]
    /\ newLeaderReady = [s \in Server |-> FALSE]
    /\ syncComplete = [s \in Server |-> FALSE]
    /\ prepared = [s \in Server |-> <<>>]
    /\ syncQueued = [s \in Server |-> <<>>]
    /\ pending = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ recoveryVisible = [s \in Server |-> <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> <<>>]
    /\ globalCommitted = <<>>
    /\ acks = [t \in Txn |-> {}]
    /\ durabilityEvidence = [t \in Txn |-> {}]
    /\ commitWitness = [t \in Txn |-> {}]
    /\ nextTxn = 1
    /\ snapshotBusy = [s \in Server |-> FALSE]
    /\ snapshotImage = [s \in Server |-> <<>>]
    /\ snapshotPublished = [s \in Server |-> <<>>]

TraceBaseInit ==
    /\ running = [s \in Server |-> FALSE]
    /\ role = [s \in Server |-> "LOOKING"]
    /\ phase = [s \in Server |-> "ELECTION"]
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ leaderOf = [s \in Server |-> NoServer]
    /\ acceptedEpoch = [s \in Server |-> -1]
    /\ currentEpoch = [s \in Server |-> -1]
    /\ epochProposal = [s \in Server |-> -1]
    /\ electionRound = 0
    /\ votedFor = [s \in Server |-> NoServer]
    /\ electionVotes = [s \in Server |-> {}]
    /\ epochAcks = [s \in Server |-> {}]
    /\ newLeaderAcks = [s \in Server |-> {}]
    /\ newLeaderReady = [s \in Server |-> FALSE]
    /\ syncComplete = [s \in Server |-> FALSE]
    /\ prepared = [s \in Server |-> <<>>]
    /\ syncQueued = [s \in Server |-> <<>>]
    /\ pending = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ recoveryVisible = [s \in Server |-> <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> <<>>]
    /\ globalCommitted = <<>>
    /\ acks = [t \in Txn |-> {}]
    /\ durabilityEvidence = [t \in Txn |-> {}]
    /\ commitWitness = [t \in Txn |-> {}]
    /\ nextTxn = 1
    /\ snapshotBusy = [s \in Server |-> FALSE]
    /\ snapshotImage = [s \in Server |-> <<>>]
    /\ snapshotPublished = [s \in Server |-> <<>>]

RestartLoadDatabase(s, ae, ce) ==
    /\ s \in Server /\ ae \in (-1)..MaxEpoch /\ ce \in (-1)..MaxEpoch
    /\ ce <= ae
    /\ running' = [running EXCEPT ![s] = TRUE]
    /\ role' = [role EXCEPT ![s] = "LOOKING"]
    /\ phase' = [phase EXCEPT ![s] = "ELECTION"]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = NoServer]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = ae]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = ce]
    /\ epochProposal' = [epochProposal EXCEPT ![s] = ae]
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![s] = durable[s]]
    /\ prepared' = [prepared EXCEPT ![s] = durable[s]]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = <<>>]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ syncComplete' = [syncComplete EXCEPT ![s] = FALSE]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, durable, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

GracefulShutdown(s) ==
    /\ s \in Server /\ running[s]
    /\ running' = [running EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

Crash(s) ==
    /\ s \in Server /\ running[s]
    /\ running' = [running EXCEPT ![s] = FALSE]
    /\ phase' = [phase EXCEPT ![s] = "ELECTION"]
    /\ role' = [role EXCEPT ![s] = "LOOKING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = NoServer]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = <<>>]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncComplete' = [syncComplete EXCEPT ![s] = FALSE]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![s] = FALSE]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, epochProposal,
                    electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, prepared,
                    durable, recoveryVisible, committed, applied,
                    globalCommitted, acks, durabilityEvidence, commitWitness,
                    nextTxn, snapshotImage, snapshotPublished>>

BeginElectionRound(c) ==
    /\ c \in Server /\ running[c]
    /\ ~\E s \in Server : running[s] /\ role[s] = "LEADING" /\ phase[s] = "BROADCAST"
    /\ electionRound' = electionRound + 1
    /\ votedFor' = [s \in Server |-> NoServer]
    /\ electionVotes' = [s \in Server |-> {}]
    /\ role' = [s \in Server |-> IF running[s] THEN "LOOKING" ELSE role[s]]
    /\ phase' = [s \in Server |-> IF running[s] THEN "ELECTION" ELSE phase[s]]
    /\ syncMode' = [s \in Server |-> IF running[s] THEN "NONE" ELSE syncMode[s]]
    /\ leaderOf' = [s \in Server |-> IF running[s] THEN NoServer ELSE leaderOf[s]]
    /\ epochAcks' = [s \in Server |-> {}]
    /\ newLeaderAcks' = [s \in Server |-> {}]
    /\ newLeaderReady' = [s \in Server |-> IF running[s] THEN FALSE ELSE newLeaderReady[s]]
    /\ syncComplete' = [s \in Server |-> IF running[s] THEN FALSE ELSE syncComplete[s]]
    /\ UNCHANGED <<running, acceptedEpoch, currentEpoch,
                    epochProposal, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

CastVote(v, c) ==
    /\ v \in Server /\ c \in Server /\ running[v] /\ running[c]
    /\ phase[v] = "ELECTION" /\ votedFor[v] = NoServer
    /\ votedFor' = [votedFor EXCEPT ![v] = c]
    /\ electionVotes' = [electionVotes EXCEPT ![c] = @ \cup {v}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf,
                    acceptedEpoch, currentEpoch, epochProposal, electionRound,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

FinishElection(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s]
    /\ Quorum(electionVotes[c]) /\ ElectionUpToDate(c)
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, electionRound, votedFor, electionVotes,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

ObserveElectionResult(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s]
    /\ ElectionUpToDate(c)
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ electionVotes' = [electionVotes EXCEPT ![c] = Server]
    /\ votedFor' = [votedFor EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, electionRound, epochAcks, newLeaderAcks,
                    newLeaderReady, syncComplete, prepared, syncQueued,
                    pending, durable, recoveryVisible, committed, applied,
                    globalCommitted, acks, durabilityEvidence, commitWitness,
                    nextTxn, snapshotBusy, snapshotImage, snapshotPublished>>

ObserveSetZabState(s, p) ==
    /\ s \in Server /\ p \in Phases
    /\ phase' = [phase EXCEPT ![s] = p]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

ObserveSetPeerState(s, r) ==
    /\ s \in Server /\ r \in Roles
    /\ role' = [role EXCEPT ![s] = r]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = IF r = "LOOKING" THEN NoServer ELSE @]
    /\ UNCHANGED <<running, phase, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, electionRound, votedFor, electionVotes,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

PersistAcceptedEpoch(s, e) ==
    /\ s \in Server /\ running[s] /\ e \in 0..MaxEpoch
    /\ phase[s] = "DISCOVERY"
    /\ e >= acceptedEpoch[s]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = e]
    /\ epochProposal' = [epochProposal EXCEPT ![s] = e]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, currentEpoch,
                    electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, newLeaderReady, syncComplete, prepared,
                    syncQueued, pending, durable, recoveryVisible, committed,
                    applied, globalCommitted, acks, durabilityEvidence,
                    commitWitness, nextTxn, snapshotBusy, snapshotImage,
                    snapshotPublished>>

PersistCurrentEpoch(s, e) ==
    /\ s \in Server /\ running[s] /\ e \in 0..MaxEpoch
    /\ e >= currentEpoch[s] /\ e <= acceptedEpoch[s]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = e]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    epochProposal, electionRound, votedFor, electionVotes,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

RecordEpochAck(l, f) ==
    /\ l \in Server /\ f \in Server /\ running[l] /\ running[f]
    /\ role[l] = "LEADING" /\ phase[l] = "DISCOVERY"
    /\ epochProposal[l] > currentEpoch[l]
    /\ acceptedEpoch[l] = epochProposal[l]
    /\ phase[f] = "DISCOVERY"
    /\ acceptedEpoch[f] = epochProposal[l]
    /\ epochAcks' = [epochAcks EXCEPT ![l] = @ \cup {f}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

FormEpochQuorum(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ phase[l] = "DISCOVERY"
    /\ Quorum(epochAcks[l])
    /\ currentEpoch[l] < epochProposal[l]
    /\ epochProposal[l] <= acceptedEpoch[l]
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = epochProposal[l]]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = {l}]
    /\ phase' = [phase EXCEPT ![l] = "SYNCHRONIZATION"]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, acceptedEpoch,
                    epochProposal, electionRound, votedFor, electionVotes,
                    epochAcks, newLeaderReady, syncComplete, prepared,
                    syncQueued, pending, durable, recoveryVisible, committed,
                    applied, globalCommitted, acks, durabilityEvidence,
                    commitWitness, nextTxn, snapshotBusy, snapshotImage,
                    snapshotPublished>>

ChooseSyncMode(f, m) ==
    /\ f \in Server /\ m \in Modes /\ running[f]
    /\ role[f] = "FOLLOWING"
    /\ syncMode' = [syncMode EXCEPT ![f] = m]
    /\ UNCHANGED <<running, role, phase, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

CompleteLearnerSync(f, l, m) ==
    /\ f \in Server /\ l \in Server /\ m \in Modes
    /\ running[f] /\ running[l] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] = l /\ role[l] = "LEADING"
    /\ (syncMode[f] = m \/ syncMode[f] = "NONE")
    /\ prepared' = [prepared EXCEPT ![f] =
          IF m \in {"TRUNC", "SNAP"} THEN prepared[l] ELSE @]
    /\ durable' = [durable EXCEPT ![f] =
          IF m \in {"TRUNC", "SNAP"} THEN ReconciledDurable(f, l) ELSE @]
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![f] =
          IF m \in {"TRUNC", "SNAP"} THEN ReconciledDurable(f, l) ELSE @]
    /\ committed' = [committed EXCEPT ![f] =
          IF m \in {"TRUNC", "SNAP"} THEN committed[l] ELSE @]
    /\ applied' = [applied EXCEPT ![f] =
          IF m \in {"TRUNC", "SNAP"} THEN committed[l] ELSE @]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = TRUE]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = @ \cup {f}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderReady, syncQueued,
                    pending, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

FormNewLeaderQuorum(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ Quorum(newLeaderAcks[l])
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![l] = TRUE]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

ObserveNewLeaderQuorum(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = Server]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![l] = TRUE]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, syncComplete, prepared,
                    syncQueued, pending, durable, recoveryVisible, committed,
                    applied, globalCommitted, acks, durabilityEvidence,
                    commitWitness, nextTxn, snapshotBusy, snapshotImage,
                    snapshotPublished>>

LeaderPropose(l, t) ==
    /\ l \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ phase[l] = "BROADCAST"
    /\ newLeaderReady[l] /\ t = nextTxn
    /\ prepared' = [prepared EXCEPT ![l] = Append(@, t)]
    /\ acks' = [acks EXCEPT ![t] = {}]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = {}]
    /\ commitWitness' = [commitWitness EXCEPT ![t] = {}]
    /\ nextTxn' = nextTxn + 1
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    snapshotBusy, snapshotImage, snapshotPublished>>

FollowerPendingProposal(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING"
    /\ phase[f] \in {"SYNCHRONIZATION", "BROADCAST"}
    /\ leaderOf[f] \in Server /\ t \in Elems(prepared[leaderOf[f]])
    /\ t = Len(prepared[f]) + 1
    /\ pending' = [pending EXCEPT ![f] = AppendOnce(@, t)]
    /\ prepared' = [prepared EXCEPT ![f] = AppendOnce(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

QueueForSync(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ t \in Elems(prepared[s])
    /\ t = IF Len(syncQueued[s]) = 0
            THEN Len(durable[s]) + 1
            ELSE syncQueued[s][Len(syncQueued[s])] + 1
    /\ syncQueued' = [syncQueued EXCEPT ![s] = AppendOnce(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

FlushTxnLog(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ t \in Elems(syncQueued[s])
    /\ t = Len(durable[s]) + 1
    /\ durable' = [durable EXCEPT ![s] = AppendOnce(@, t)]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = @ \cup {s}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, commitWitness, nextTxn, snapshotBusy, snapshotImage,
                    snapshotPublished>>

RecordProposalAck(l, source, t) ==
    /\ l \in Server /\ source \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ t \in Elems(prepared[l])
    /\ t \notin Elems(globalCommitted)
    /\ source \in durabilityEvidence[t]
    /\ acks' = [acks EXCEPT ![t] = @ \cup {source}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

CommitProposal(l, t) ==
    /\ l \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ Quorum(acks[t])
    /\ t = Len(globalCommitted) + 1
    /\ globalCommitted' = Append(globalCommitted, t)
    /\ committed' = [committed EXCEPT ![l] = AppendOnce(@, t)]
    /\ commitWitness' = [commitWitness EXCEPT ![t] = acks[t]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, applied, acks, durabilityEvidence,
                    nextTxn, snapshotBusy, snapshotImage, snapshotPublished>>

FollowerCommit(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING" /\ t \in Elems(pending[f])
    /\ t \in Elems(globalCommitted)
    /\ t = Len(committed[f]) + 1
    /\ committed' = [committed EXCEPT ![f] = AppendOnce(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

ApplyTxn(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ t \in Elems(committed[s]) /\ t \in Elems(globalCommitted)
    /\ t = Len(applied[s]) + 1
    /\ applied' = [applied EXCEPT ![s] = AppendOnce(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished>>

BeginSnapshot(s) ==
    /\ s \in Server /\ running[s] /\ role[s] \in {"LEADING", "FOLLOWING"}
    /\ ~snapshotBusy[s]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = TRUE]
    /\ snapshotImage' = [snapshotImage EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotPublished>>

FinishSnapshot(s) ==
    /\ s \in Server /\ snapshotBusy[s]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = FALSE]
    /\ snapshotPublished' = [snapshotPublished EXCEPT ![s] = snapshotImage[s]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotImage>>

\* REQ-EVIDENCE TypeOK
\* intent:   every base-model variable stays inside the domain declared for it
\* status:   model-internal
\* verified: base
\* review:   ok
TypeOK ==
    /\ running \in [Server -> BOOLEAN]
    /\ role \in [Server -> Roles]
    /\ phase \in [Server -> Phases]
    /\ syncMode \in [Server -> Modes]
    /\ leaderOf \in [Server -> Server \cup {NoServer}]
    /\ acceptedEpoch \in [Server -> (-1)..MaxEpoch]
    /\ currentEpoch \in [Server -> (-1)..MaxEpoch]
    /\ epochProposal \in [Server -> (-1)..MaxEpoch]
    /\ electionRound \in Nat
    /\ votedFor \in [Server -> Server \cup {NoServer}]
    /\ electionVotes \in [Server -> SUBSET Server]
    /\ epochAcks \in [Server -> SUBSET Server]
    /\ newLeaderAcks \in [Server -> SUBSET Server]
    /\ newLeaderReady \in [Server -> BOOLEAN]
    /\ syncComplete \in [Server -> BOOLEAN]
    /\ prepared \in [Server -> Seq(Txn)]
    /\ syncQueued \in [Server -> Seq(Txn)]
    /\ pending \in [Server -> Seq(Txn)]
    /\ durable \in [Server -> Seq(Txn)]
    /\ recoveryVisible \in [Server -> Seq(Txn)]
    /\ committed \in [Server -> Seq(Txn)]
    /\ applied \in [Server -> Seq(Txn)]
    /\ globalCommitted \in Seq(Txn)
    /\ acks \in [Txn -> SUBSET Server]
    /\ durabilityEvidence \in [Txn -> SUBSET Server]
    /\ commitWitness \in [Txn -> SUBSET Server]
    /\ nextTxn \in 1..(MaxTxn + 1)
    /\ snapshotBusy \in [Server -> BOOLEAN]
    /\ snapshotImage \in [Server -> Seq(Txn)]
    /\ snapshotPublished \in [Server -> Seq(Txn)]

\* REQ-EVIDENCE ActiveLeaderUniqueness
\* intent:   at any time at most one running server is in the LEADING role and the broadcast phase
\* status:   unknown
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:712 "self.setZabState(QuorumPeer.ZabState.BROADCAST);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:760 "if (!tickSkip && !syncedAckSet.hasAllQuorums()) {"
\* watch:    Leader.java:lead; Leader.java:waitForNewLeaderAck; Leader.java:shutdown; QuorumPeer.java:setPeerState; QuorumPeer.java:setZabState
\* verified: base
\* note:     zookeeperInternals.md:246 ("there is only one active leader at a time since followers only follow a single leader at a time") and :210-211 ("no other leader will be able to get a quorum of followers") state uniqueness of the leader that a quorum follows, and :188 only says when a leader activates; the same document at :212-213, :257-259 ("old leaders believing they are still active") and :278 ("two servers simultaneously think they are the leader") says a server may still hold the leader state after a new leader emerges, so none of these quotes supports uniqueness of the LEADING/broadcast state and they were removed as evidence; :130 ("only one leader uses a given epoch") is per epoch and was not counted; searched Leader.java history (-S'Not sufficient followers synced': 21ef61aa, 9531ec29, 8b4520f7; -S'syncedAckSet': only faa7cec7), log --grep for "split brain"/"two leaders" (only a4bc9857, a truncate-failure fix, not counted), and the docs for "only one leader", "single leader" and "split brain" (zookeeperReconfig.md:553 and zookeeperAdmin.md:1848 are misconfiguration warnings, not counted)
\* review:   status requirement -> unknown and the three doc lines removed, because they support uniqueness of the quorum-backed leader while the same document says two servers may simultaneously hold the leader state that the formula counts.
ActiveLeaderUniqueness ==
    Cardinality({s \in Server : running[s] /\ role[s] = "LEADING" /\ phase[s] = "BROADCAST"}) <= 1

\* REQ-EVIDENCE AcceptedEpochGECurrentEpoch
\* intent:   a server's current epoch never exceeds its accepted epoch
\* status:   unknown
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1142 "if (acceptedEpoch < currentEpoch) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1405 "self.setAcceptedEpoch(epoch);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743 "self.setCurrentEpoch(newEpoch);"
\* watch:    QuorumPeer.java:loadDataBase; QuorumPeer.java:setAcceptedEpoch; QuorumPeer.java:setCurrentEpoch; Learner.java:registerWithLeader; Learner.java:syncWithLeader; Leader.java:getEpochToPropose; Leader.java:lead
\* verified: base
\* note:     no doc or code comment states the inequality itself; the startup check at QuorumPeer.java:1142 is impl only (added in 776db780 without a comment, message corrected in 1ea6879b, found with -S'acceptedEpoch < currentEpoch' and -S'is less than the current epoch'); removed as evidence: history f8f15de5 (message: "setCurrentEpoch should be done upon receipt of NEWLEADER (before acking it)"; "AcceptedEpoch not updated at leader before it proposes the epoch to followers") only fixes when each epoch is written in the handshake, Zab1_0Test.java:614-615 testNormalFollowerRun asserts the concrete values 1 and 0 after ACKEPOCH, and Zab1_0Test.java:1126-1127 testAbandonBeforeACKEpoch asserts only that the leader's current epoch stays 0 without a quorum of epoch acks; none of them states or directly implies the inequality; the comments at Learner.java:513-516 concern not acking an equal epoch twice and were not counted; -S'setAcceptedEpoch' on Learner.java gives only 776db780 (no rule in its message)
\* review:   status requirement -> unknown and the two history and two test lines removed, because they fix the handshake order or assert single values and do not state that the current epoch never exceeds the accepted epoch.
AcceptedEpochGECurrentEpoch == \A s \in Server : acceptedEpoch[s] >= currentEpoch[s]

\* REQ-EVIDENCE OrderedHistories
\* intent:   the global commit sequence and every server's seen, logged and recovered histories are gap-free prefixes of zxid order, each server's queued and pending proposals are in increasing zxid order, its committed history is a prefix of the global commit sequence, and its applied history is a prefix of its committed history
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:229 "has been written to non-volatile storage, all messages that were proposed before" -> logged and recovered histories are gap-free zxid prefixes
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:245 "see and record proposals in order" -> proposals a server has seen are recorded in zxid order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:225 "followers also receive proposals in order" -> a follower receives the leader's proposals over a FIFO channel, so in zxid order and without gaps
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:891 "make sure that ops are committed in order." -> the global commit sequence follows zxid order, with no operation committed ahead of a preceding one
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:226 "Followers process messages in the order they are received." -> queued and pending proposals stay in zxid order
\* evidence: contract source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:95 "must correspond to the head of pendingTxns if it exists" -> a follower commits its pending proposals from the head of the queue, so its committed history follows the order it received them
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:63 "message `a` will be delivered before `b` by all" -> every server commits (delivers) transactions in one common order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:234 "COMMITs are processed in order. Followers deliver a proposal" -> a follower processes the leader's COMMITs in order and applies a proposal when it is committed, so its committed and applied histories follow the global commit order
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/CommitProcessor.java:70 "Write requests must be processed in zxid order" -> the applied history is in zxid order
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:910 "if (zxid != lastCommitted + 1) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:627 "if (pif.hdr.getZxid() != lastQueued + 1) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:103 "if (firstElementZxid != zxid) {"
\* watch:    Leader.java:propose; Leader.java:tryToCommit; Follower.java:processPacket; Learner.java:syncWithLeader; FollowerZooKeeperServer.java:logRequest; FollowerZooKeeperServer.java:commit; SyncRequestProcessor.java:run; CommitProcessor.java:run
\* verified: base
\* note:     every clause has doc or comment support; the gap checks in Learner.java:627 and Follower.java:171 only log a warning, so they were counted as impl, not as a rule; the no-gap reading of zookeeperInternals.md:225 and :234 (COMMITs sent over the same channels, :231-233) rests on the same document's definition of FIFO channels at :84-87 ("a message m is delivered only after all messages sent before m"), and of Leader.java:891 on the rest of that comment at :892-896 ("not possible to get enough acks for an operation without getting enough acks for preceding ops")
\* review:   intent rewritten to state what the formula checks (gap-free prefixes for seen, logged, recovered and global commit; increasing order for queued and pending) and the suffixes of :225, :63, :234, Leader.java:891 and FollowerZooKeeperServer.java:95 restated to what those quotes say (:63 gives one common order, not the prefix relation).
OrderedHistories ==
    /\ PrefixOf(globalCommitted, TxnOrder)
    /\ \A s \in Server :
        /\ PrefixOf(prepared[s], TxnOrder)
        /\ OrderedFragment(syncQueued[s])
        /\ OrderedFragment(pending[s])
        /\ PrefixOf(durable[s], TxnOrder)
        /\ PrefixOf(recoveryVisible[s], TxnOrder)
        /\ PrefixOf(committed[s], globalCommitted)
        /\ PrefixOf(applied[s], committed[s])

\* REQ-EVIDENCE CommittedPrefixAgreement
\* intent:   for any two servers one committed history is a prefix of the other, so no two servers commit different transactions at the same position
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:63 "message `a` will be delivered before `b` by all" -> all servers commit in one common order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:242 "believed by a new leader always contain any proposal that has actually been committed" -> a committed transaction is not dropped or replaced across leader changes
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java:204 testInconsistentDueToUncommittedLog "This inconsistent view of the quorum exposed from leaders is a violation of ZAB." -> a write that was visible at the old leader is still present at the new leader after the quorum recovers (assertion at :212-214)
\* evidence: history b978dfb9 (message) "inconsistent view of the data from client before / after quorum recovers" -> divergent committed views across a recovery are treated as a bug
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:103 "if (firstElementZxid != zxid) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1300 "QuorumPacket qp = new QuorumPacket(Leader.COMMIT, p.packet.getZxid(), null, null);"
\* watch:    Leader.java:tryToCommit; Leader.java:startForwarding; LearnerHandler.java:syncFollower; Learner.java:syncWithLeader; FollowerZooKeeperServer.java:commit
\* verified: base
\* note:     the total-order guarantee in zookeeperInternals.md:61-64 is stated for delivery; it is read here as applying to commit, since :234-235 says followers deliver a proposal when it is committed
\* review:   suffix of the DIFFSyncConsistencyTest line narrowed from "servers must not disagree on committed data" to what its assertion checks; status and intent kept because :63 and :242 support the intent.
CommittedPrefixAgreement ==
    \A a, b \in Server : PrefixOf(committed[a], committed[b]) \/ PrefixOf(committed[b], committed[a])

\* REQ-EVIDENCE NormalAckHasDurabilityEvidence
\* intent:   the leader counts a server's acknowledgement of a proposal only if that server has flushed the proposal to its transaction log
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:119 "Acknowledgement means the server has recorded the proposal to persistent storage." -> an acknowledgement implies the proposal is durable at the acknowledging server
\* evidence: contract source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/TxnLog.java:99 "they are persisted" -> committing (flushing) the transaction log makes the logged transactions persistent, which is what "flushed" means in the intent
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:83 "invoked after flush returns successfully."
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:245 "this.nextProcessor.processRequest(i);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SendAckRequestProcessor.java:42 "QuorumPacket qp = new QuorumPacket(Leader.ACK, si.getHdr().getZxid(), null, null);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:76 "syncProcessor = new SyncRequestProcessor(this, new SendAckRequestProcessor(getFollower()));"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/ProposalRequestProcessor.java:53 "syncProcessor = new SyncRequestProcessor(zks, ackProcessor);"
\* watch:    SyncRequestProcessor.java:run; SyncRequestProcessor.java:flush; SendAckRequestProcessor.java:processRequest; AckRequestProcessor.java:processRequest; FollowerZooKeeperServer.java:setupRequestProcessors; ProposalRequestProcessor.java:ProposalRequestProcessor; Leader.java:processAck
\* verified: base
\* note:     the class comment SyncRequestProcessor.java:40-50 only narrates the pipeline and was not counted as a rule; history -S'callbacks will be' on SyncRequestProcessor.java leads only to package moves (67c653cf, daa66b7c, be031cb4) and, with --follow, to the initial import 047d9258, with no rule; the field comment SyncRequestProcessor.java:81-83 describes what the toFlush queue holds, without a rule or reason, and was retyped as impl; DIFFSyncConsistencyTest.java:118-127 only waits for the leader's own ack and calls that "synced to disk" in a failure message, so it asserts no durability and was removed as evidence
\* review:   SyncRequestProcessor.java:83 retyped comment -> impl (narrates the queue), the DIFFSyncConsistencyTest:123 line removed (it asserts only that an ack arrives), the TxnLog.java:99 suffix narrowed to what the contract says, and the history-search result in the note corrected; status kept on zookeeperInternals.md:119.
NormalAckHasDurabilityEvidence == \A t \in Txn : acks[t] \subseteq durabilityEvidence[t]

\* REQ-EVIDENCE ApplyHasCommitCertificate
\* intent:   a server applies a transaction only after that transaction was committed on the acknowledgements of a quorum
\* status:   requirement
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:902 "in order to be committed, a proposal must be accepted by a quorum." -> commit requires a quorum of acknowledgements
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:117 "committed when a quorum of them acknowledge the proposal." -> commit requires a quorum of acknowledgements
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:118 "If a proposal contains a message, the message will be delivered when the proposal" -> a transaction is applied (delivered) once its proposal is committed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:235 "message when that proposal is committed." -> followers apply only committed proposals
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:289 "the leader can only commit once it receives an" -> commit requires a quorum of acknowledgements
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:655 testNormalFollowerRun "The change should not have happened yet, since we haven't committed" -> a follower does not apply a proposal before its COMMIT
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:905 "if (!p.hasAllQuorums()) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:110 "commitProcessor.commit(request);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:663 "zk.processTxn(pif.hdr, pif.rec);"
\* watch:    Leader.java:tryToCommit; Leader.java:processAck; FollowerZooKeeperServer.java:commit; CommitProcessor.java:commit; Follower.java:processPacket; Learner.java:syncWithLeader
\* verified: base
\* note:     zookeeperAdmin.md:2618-2619 (transaction written to non-volatile storage before the update takes place) concerns logging, not commit, and was not counted
\* review:   ok
ApplyHasCommitCertificate ==
    \A s \in Server : \A t \in Elems(applied[s]) : Quorum(commitWitness[t])

\* REQ-EVIDENCE SyncEntryJustified
\* intent:   a running server is in the broadcast phase only as a leader whose NEWLEADER proposal a quorum acknowledged or as a follower that completed synchronization with its leader
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:198 "A new leader will not accept new proposals until the NEW_LEADER proposal has been COMMITTED." -> leader enters broadcast only after a quorum acked NEWLEADER
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:653 "We have to get at least a majority of servers in sync with" -> leader enters broadcast only after a quorum acked NEWLEADER
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:145 "A leader becomes active only when a quorum of followers" -> leader enters broadcast only after a quorum synced with it
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:194 "A follower will ACK the NEW_LEADER proposal after it has synced with the leader." -> follower completes synchronization before it takes part in broadcast
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:644 "so we need to mark when the peer can actually start" -> a follower starts using its data only once sync is marked complete
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:663 "waitForNewLeaderAck(self.getId(), zk.getZxid());"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java:109 "syncWithLeader(newEpochZxid);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:857 "setZabState(ZabState.ELECTION);"
\* watch:    Leader.java:lead; Leader.java:waitForNewLeaderAck; Follower.java:followLeader; Learner.java:syncWithLeader; LearnerHandler.java:run; QuorumPeer.java:setPeerState; QuorumPeer.java:setZabState
\* verified: base
\* clause leader-in-broadcast: requirement — doc zookeeperInternals.md:198 and :145 and comment Leader.java:653-655 require a quorum of NEWLEADER acks before the leader activates
\* clause follower-in-broadcast: requirement — doc zookeeperInternals.md:194 and comment LearnerHandler.java:643-645 place follower activation after synchronization with the leader
\* clause no-other-role-in-broadcast: impl-abstraction — only QuorumPeer.java:855-857 (going LOOKING resets the Zab state to ELECTION); the Zab state is documented as monitoring output (QuorumPeer.java:487) and came with an admin command in cc900a3b
\* note:     searched history with -S'setZabState(ZabState.ELECTION)' and -S'enum ZabState' (only cc900a3b, ZOOKEEPER-3459 "Add admin command to display synced state of peer"); no doc, comment or test says a LOOKING peer must not report the broadcast phase
\* review:   ok
SyncEntryJustified ==
    \A s \in Server :
        running[s] /\ phase[s] = "BROADCAST"
        => IF role[s] = "LEADING" THEN newLeaderReady[s]
           ELSE IF role[s] = "FOLLOWING" THEN syncComplete[s]
           ELSE FALSE

\* REQ-EVIDENCE SnapshotPublishedValid
\* intent:   in every state, the last snapshot a server published is a prefix of that server's current applied history, so it covers only transactions the server has applied
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperAdmin.md:2603 "last committed transaction at the start of the snapshot" -> when written, a snapshot is labelled by a transaction the server had already applied
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperAdmin.md:2604 "snapshot includes a subset of the updates to the data tree that" -> when written, a snapshot holds only updates that had reached the server's data tree, i.e. applied transactions
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:468 "long lastZxid = dataTree.lastProcessedZxid;"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:469 "File snapshotFile = new File(snapDir, Util.makeSnapshotName(lastZxid));"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:521 "txnLogFactory.save(zkDb.getDataTree(), zkDb.getSessionWithTimeOuts(), syncSnap);"
\* watch:    ZooKeeperServer.java:takeSnapshot; FileTxnSnapLog.java:save; SyncRequestProcessor.java:run; Learner.java:syncWithLeader
\* verified: base
\* clause covers-only-applied: requirement — zookeeperAdmin.md:2602-2605: a snapshot is named by the last committed transaction at its start and holds only updates made to the data tree, so when written it covers only transactions the server had applied
\* clause exact-prefix-of-current-applied: impl-abstraction — that the published snapshot is exactly an initial segment of the applied history, and remains one in later states, rests only on FileTxnSnapLog.java:468-469 and ZooKeeperServer.java:521; zookeeperAdmin.md:2605-2607 says a snapshot "may not correspond to any data tree that actually existed" and no source addresses later states
\* note:     the only non-impl source is the data-directory description in zookeeperAdmin.md:2598-2611, which also says a snapshot "may not correspond to any data tree that actually existed"; the support is therefore for the snapshot's label and contents being already-applied work, not for an exact image; history -S'makeSnapshotName(lastZxid)' gives only 0254f868 (file headers), no rule
\* review:   status requirement -> mixed with two clauses and intent restated to the formula (prefix of the current applied history), because the cited doc supports only "covers applied work when written" and itself calls snapshots fuzzy, not an exact prefix.
SnapshotPublishedValid ==
    \A s \in Server : PrefixOf(snapshotPublished[s], applied[s])

MonotoneStep ==
    \/ \E f \in Server : ~syncComplete[f] /\ syncComplete'[f]
    \/ /\ \A s \in Server : Len(durable'[s]) >= Len(durable[s])
       /\ \A s \in Server : Len(committed'[s]) >= Len(committed[s])
       /\ \A s \in Server : Len(applied'[s]) >= Len(applied[s])

\* REQ-EVIDENCE MonotoneUnlessRecovery
\* intent:   except in a step that completes a learner synchronization, no server's logged, committed or applied history ever becomes shorter
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:182 "have not been committed, so they can be discarded. When the follower connects" -> the proposals a follower discards are uncommitted ones, discarded when it connects to the leader (sync), so committed proposals are not discarded
\* evidence: contract source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/TxnLog.java:83 "truncate the log to get in sync with the" -> the log-truncation operation is documented as a step of getting in sync with the leader
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:830 "3. Follower has txn that we haven't seen. This may be old leader" -> the leader cuts a follower's log with TRUNC during sync when the follower has transactions the leader has not seen
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java:213 testInconsistentDueToUncommittedLog "Data inconsistency detected!" -> a write visible at the old leader is still present at the new leader after the quorum recovers
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:591 "boolean truncated = zk.getZKDatabase().truncateLog(qp.getZxid());"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:570 "zk.getZKDatabase().deserializeSnapshot(leaderIs);"
\* watch:    Learner.java:syncWithLeader; LearnerHandler.java:syncFollower; ZKDatabase.java:truncateLog; ZKDatabase.java:deserializeSnapshot; FileTxnSnapLog.java:truncateLog; SyncRequestProcessor.java:run
\* verified: base
\* clause durable-shrinks-only-in-sync: requirement — doc zookeeperInternals.md:176-183, comment LearnerHandler.java:830-831 and contract TxnLog.java:82-84 tie log truncation to synchronization with a leader
\* clause committed-and-applied-shrink-only-in-sync: requirement — doc zookeeperInternals.md:180-182 (only uncommitted proposals are discarded) and test DIFFSyncConsistencyTest.java:213
\* clause sync-step-exemption: impl-abstraction — that a sync step may cut a follower's log is documented (zookeeperInternals.md:182-183, TxnLog.java:82-84), but that a SNAP sync replaces the follower's database, and that the exemption covers committed and applied histories, is visible only in Learner.java:565-597 and ZKDatabase.java:599-622
\* note:     history searched with -S'truncateLog' and -S'deserializeSnapshot' on Learner.java (0957b840 refactor, 3dc91bd2), -S'Leader.TRUNC' (27d045af, 9f102d31, 344a3079 and later) and -S'we need to truncate the log to the lastzxid of the leader' (344a3079, 0957b840); no comment says which histories may shrink during a SNAP sync; 27d045af (message "Log truncation truncating log too much - can cause data loss") limits how much a truncation inside a sync step may remove, which the intent exempts, so it supports no part of the intent and was removed as evidence
\* review:   history line 27d045af removed (it constrains truncation inside the exempted sync step), "only" claims dropped from the :182, LearnerHandler.java:830 and TxnLog.java:83 suffixes, the test suffix narrowed to its assertion, and the clause names and exemption text corrected to match the formula and the cited sources.
MonotoneUnlessRecovery == [][MonotoneStep]_vars

InvariantSet ==
    TypeOK /\ ActiveLeaderUniqueness /\ AcceptedEpochGECurrentEpoch
    /\ OrderedHistories /\ CommittedPrefixAgreement
    /\ NormalAckHasDurabilityEvidence /\ ApplyHasCommitCertificate
    /\ SyncEntryJustified /\ SnapshotPublishedValid

(***************************************************************************)
(* Canonical source-derived base schedule.  The MC module expands ordinary *)
(* server choices; this driver gives base.cfg a finite transition relation  *)
(* that exercises every persistence/history boundary without adding        *)
(* observational counters to the semantic base.                            *)
(***************************************************************************)
BaseLeader == CHOOSE s \in Server : TRUE
BaseFollower == CHOOSE s \in Server \ {BaseLeader} : TRUE

BaseNext ==
    \/ \E v \in Server : CastVote(v, BaseLeader)
    \/ FinishElection(BaseLeader, BaseLeader)
    \/ FinishElection(BaseFollower, BaseLeader)
    \/ /\ running[BaseLeader] /\ phase[BaseLeader] = "ELECTION"
       /\ role[BaseLeader] = "LEADING"
       /\ ObserveSetZabState(BaseLeader, "DISCOVERY")
    \/ /\ running[BaseFollower] /\ phase[BaseFollower] = "ELECTION"
       /\ role[BaseFollower] = "FOLLOWING"
       /\ ObserveSetZabState(BaseFollower, "DISCOVERY")
    \/ /\ role[BaseLeader] = "LEADING"
       /\ phase[BaseLeader] = "DISCOVERY"
       /\ currentEpoch[BaseLeader] < MaxEpoch
       /\ PersistAcceptedEpoch(BaseLeader, currentEpoch[BaseLeader] + 1)
    \/ /\ role[BaseFollower] = "FOLLOWING"
       /\ phase[BaseFollower] = "DISCOVERY"
       /\ PersistAcceptedEpoch(BaseFollower, epochProposal[BaseLeader])
    \/ RecordEpochAck(BaseLeader, BaseLeader)
    \/ RecordEpochAck(BaseLeader, BaseFollower)
    \/ FormEpochQuorum(BaseLeader)
    \/ /\ acceptedEpoch[BaseFollower] > currentEpoch[BaseFollower]
       /\ PersistCurrentEpoch(BaseFollower, acceptedEpoch[BaseFollower])
    \/ /\ role[BaseFollower] = "FOLLOWING"
       /\ phase[BaseFollower] = "DISCOVERY"
       /\ phase[BaseLeader] = "SYNCHRONIZATION"
       /\ currentEpoch[BaseFollower] = currentEpoch[BaseLeader]
       /\ ObserveSetZabState(BaseFollower, "SYNCHRONIZATION")
    \/ \E m \in {"DIFF", "TRUNC", "SNAP"} :
          /\ syncMode[BaseFollower] = "NONE"
          /\ ~syncComplete[BaseFollower]
          /\ ChooseSyncMode(BaseFollower, m)
    \/ /\ ~syncComplete[BaseFollower]
       /\ syncMode[BaseFollower] \in {"DIFF", "TRUNC", "SNAP"}
       /\ CompleteLearnerSync(BaseFollower, BaseLeader, syncMode[BaseFollower])
    \/ /\ ~newLeaderReady[BaseLeader]
       /\ FormNewLeaderQuorum(BaseLeader)
    \/ /\ role[BaseLeader] = "LEADING"
       /\ phase[BaseLeader] = "SYNCHRONIZATION"
       /\ newLeaderReady[BaseLeader]
       /\ ObserveSetZabState(BaseLeader, "BROADCAST")
    \/ /\ role[BaseFollower] = "FOLLOWING"
       /\ phase[BaseFollower] = "SYNCHRONIZATION"
       /\ syncComplete[BaseFollower]
       /\ newLeaderReady[BaseLeader]
       /\ ObserveSetZabState(BaseFollower, "BROADCAST")
    \/ /\ nextTxn \in Txn
       /\ LeaderPropose(BaseLeader, nextTxn)
    \/ \E t \in Txn : FollowerPendingProposal(BaseFollower, t)
    \/ \E t \in Txn : QueueForSync(BaseLeader, t)
    \/ \E t \in Txn : QueueForSync(BaseFollower, t)
    \/ \E t \in Txn : FlushTxnLog(BaseLeader, t)
    \/ \E t \in Txn : FlushTxnLog(BaseFollower, t)
    \/ \E t \in Txn : RecordProposalAck(BaseLeader, BaseLeader, t)
    \/ \E t \in Txn : RecordProposalAck(BaseLeader, BaseFollower, t)
    \/ \E t \in Txn : CommitProposal(BaseLeader, t)
    \/ \E t \in Txn : FollowerCommit(BaseFollower, t)
    \/ \E t \in Txn : ApplyTxn(BaseLeader, t)
    \/ \E t \in Txn : ApplyTxn(BaseFollower, t)
    \/ BeginSnapshot(BaseLeader)
    \/ FinishSnapshot(BaseLeader)
    \/ BeginSnapshot(BaseFollower)
    \/ FinishSnapshot(BaseFollower)
    \/ /\ phase[BaseLeader] = "BROADCAST"
       /\ nextTxn = MaxTxn + 1
       /\ Crash(BaseLeader)
    \/ /\ phase[BaseFollower] = "BROADCAST"
       /\ nextTxn = MaxTxn + 1
       /\ Crash(BaseFollower)
    \/ /\ ~running[BaseLeader]
       /\ RestartLoadDatabase(BaseLeader,
                              acceptedEpoch[BaseLeader],
                              currentEpoch[BaseLeader])
    \/ /\ ~running[BaseFollower]
       /\ RestartLoadDatabase(BaseFollower,
                              acceptedEpoch[BaseFollower],
                              currentEpoch[BaseFollower])
    \/ /\ nextTxn = MaxTxn + 1
       /\ GracefulShutdown(BaseLeader)
    \/ /\ nextTxn = MaxTxn + 1
       /\ GracefulShutdown(BaseFollower)

BaseSymmetry == Permutations(Server)

=============================================================================
