------------------------------ MODULE OldBase ------------------------------
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

ActiveLeaderUniqueness ==
    Cardinality({s \in Server : running[s] /\ role[s] = "LEADING" /\ phase[s] = "BROADCAST"}) <= 1

AcceptedEpochGECurrentEpoch == \A s \in Server : acceptedEpoch[s] >= currentEpoch[s]

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

CommittedPrefixAgreement ==
    \A a, b \in Server : PrefixOf(committed[a], committed[b]) \/ PrefixOf(committed[b], committed[a])

NormalAckHasDurabilityEvidence == \A t \in Txn : acks[t] \subseteq durabilityEvidence[t]

ApplyHasCommitCertificate ==
    \A s \in Server : \A t \in Elems(applied[s]) : Quorum(commitWitness[t])

SyncEntryJustified ==
    \A s \in Server :
        running[s] /\ phase[s] = "BROADCAST"
        => IF role[s] = "LEADING" THEN newLeaderReady[s]
           ELSE IF role[s] = "FOLLOWING" THEN syncComplete[s]
           ELSE FALSE

SnapshotPublishedValid ==
    \A s \in Server : PrefixOf(snapshotPublished[s], applied[s])

MonotoneStep ==
    \/ \E f \in Server : ~syncComplete[f] /\ syncComplete'[f]
    \/ /\ \A s \in Server : Len(durable'[s]) >= Len(durable[s])
       /\ \A s \in Server : Len(committed'[s]) >= Len(committed[s])
       /\ \A s \in Server : Len(applied'[s]) >= Len(applied[s])

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
