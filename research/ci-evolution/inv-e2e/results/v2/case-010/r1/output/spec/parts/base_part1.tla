------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

(***************************************************************************)
(* Code-faithful finite abstraction of the ZooKeeper Zab path, revised for *)
(* the updated revision (artifact commit "update").  Histories contain     *)
(* dense transaction identifiers in zxid order.                            *)
(*                                                                         *)
(* Incremental revision (case-010):                                        *)
(*  - the in-memory ZKDatabase that a peer reuses across leader changes is *)
(*    explicit (recoveryVisible + dbInitialized);                          *)
(*  - learner synchronization is split at its real source boundaries      *)
(*    (mode packet, direct in-memory COMMIT application, NEWLEADER         *)
(*    snapshot, NEWLEADER ACK, UPTODATE);                                  *)
(*  - Learner.shutdown is an explicit action whose zk.shutdown(boolean)    *)
(*    call clears the database only for an unfinished SNAP sync (new) and  *)
(*    no longer reaches the LearnerZooKeeperServer.shutdown() override     *)
(*    that drained the learner sync processor (new);                       *)
(*  - CodeVersion selects the exact-old ("old") or updated ("new") shutdown *)
(*    semantics so that the old implementation remains a control.         *)
(***************************************************************************)

CONSTANTS Server, MaxEpoch, MaxTxn, NoServer, CodeVersion

ASSUME CodeVersion \in {"old", "new"}

Txn == 1..MaxTxn
Roles == {"LOOKING", "LEADING", "FOLLOWING"}
Phases == {"ELECTION", "DISCOVERY", "SYNCHRONIZATION", "BROADCAST"}
Modes == {"NONE", "DIFF", "TRUNC", "SNAP"}
\* Learner.syncWithLeader progress inside one following session.
\*   IDLE      : no sync-mode packet processed in this session
\*   MODE      : DIFF/SNAP/TRUNC packet processed, NEWLEADER not yet processed
\*   SNAPPED   : SNAP/TRUNC only: NEWLEADER takeSnapshot completed
\*   NEWLEADER : setSyncMode(NONE)+NEWLEADER ACK done (writeToTxnLog = true)
Stages == {"IDLE", "MODE", "SNAPPED", "NEWLEADER"}
TransitionNames == {
    "Init", "RestartLoadDatabase", "GracefulShutdown", "Crash",
    "BeginElectionRound", "CastVote", "FinishElection", "JoinEstablishedLeader",
    "SetPeerState", "SetZabState", "PersistAcceptedEpoch", "PersistCurrentEpoch",
    "RecordEpochAck", "FormEpochQuorum", "ChooseSyncMode",
    "ReceiveSyncMode", "SyncApplyCommitted", "PersistSyncSnapshot",
    "LearnerAckNewLeader", "CompleteLearnerSync", "FormNewLeaderQuorum",
    "LeaderPropose", "FollowerPendingProposal", "QueueForSync", "FlushTxnLog",
    "LeakedFlush", "RecordProposalAck", "CommitProposal", "FollowerCommit",
    "ApplyTxn", "BeginSnapshot", "FinishSnapshot", "LearnerShutdown",
    "ReloadDatabase"
}

VARIABLES
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    prepared, syncQueued, pending, durable, recoveryVisible,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished,
    \* --- incremental (case-010) state ---
    dbInitialized,  \* ZKDatabase.initialized (ZKDatabase.java:96,161-163,171-188,284-302)
    learnerStage,   \* Learner.syncWithLeader progress (Learner.java:546-792)
    sessionMode,    \* mode packet of the current following session (Learner.java:559-608)
    logCursor,      \* prefix of prepared already owned by the current sync processor
    leakedQueued    \* queue of a learner SyncRequestProcessor that zk.shutdown did not stop

vars == <<
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    prepared, syncQueued, pending, durable, recoveryVisible,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished,
    dbInitialized, learnerStage, sessionMode, logCursor, leakedQueued
>>

Quorum(q) == q \subseteq Server /\ Cardinality(q) * 2 > Cardinality(Server)
Elems(h) == {h[n] : n \in 1..Len(h)}
TxnOrder == [n \in Txn |-> n]
PrefixOf(a, b) == \E n \in 0..Len(b) : a = SubSeq(b, 1, n)
AppendOnce(h, t) == IF t \in Elems(h) THEN h ELSE Append(h, t)
RECURSIVE AppendAllOnce(_, _)
AppendAllOnce(h, q) ==
    IF Len(q) = 0 THEN h ELSE AppendAllOnce(AppendOnce(h, Head(q)), Tail(q))
MaxNat(a, b) == IF a >= b THEN a ELSE b
MinNat(a, b) == IF a <= b THEN a ELSE b
LastOr0(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)]
LongerOf(a, b) == IF Len(a) >= Len(b) THEN a ELSE b
AboveSeq(h, z) == SelectSeq(h, LAMBDA x : x > z)
AtMostSeq(h, z) == SelectSeq(h, LAMBDA x : x <= z)
OrderedFragment(h) ==
    \A a, b \in 1..Len(h) : a < b => h[a] < h[b]
\* longest prefix of h that is also a prefix of the global commit sequence
CommittedPart(h) ==
    LET ok(k) == k <= Len(globalCommitted) /\ SubSeq(h, 1, k) = SubSeq(globalCommitted, 1, k)
        n == CHOOSE k \in 0..Len(h) : ok(k) /\ \A j \in 0..Len(h) : ok(j) => j <= k
    IN SubSeq(h, 1, n)

\* Restore semantics of a learner snapshot taken at NEWLEADER: the newest
\* snapshot (img) plus every logged record with a larger zxid
\* (FileTxnSnapLog.java:243-368 restore; FileTxnLog iterator from zxid).
SnapRestore(img, d) == img \o AboveSeq(d, LastOr0(img))

\* History a peer reports as its last logged zxid.
\* QuorumPeer.java:1257-1262 getLastLoggedZxid: reload from disk only when the
\* in-memory database is not initialized; otherwise report the in-memory tree.
DbView(s) == IF dbInitialized[s] THEN recoveryVisible[s] ELSE durable[s]
ElectionZxid(s) == LastOr0(DbView(s))

\* Leader data tree / committed-log maximum used by LearnerHandler.syncFollower
\* (LearnerHandler.java:796-806,840-863): replayed history plus applied txns.
LeaderTree(l) == LongerOf(applied[l], recoveryVisible[l])
LeaderTreeZxid(l) == LastOr0(LeaderTree(l))

\* Vote comparison among peers currently running FLE (FastLeaderElection.java
\* :722-747 totalOrderPredicate on peerEpoch then zxid).
ElectionUpToDate(c) ==
    \A v \in Server :
        (running[v] /\ (role[v] = "LOOKING" \/ v = c)) =>
            \/ currentEpoch[c] > currentEpoch[v]
            \/ currentEpoch[c] = currentEpoch[v]
               /\ ElectionZxid(c) >= ElectionZxid(v)

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
    \* QuorumPeer.start -> loadDataBase initializes the database (QuorumPeer.java:1083-1104)
    /\ dbInitialized = [s \in Server |-> TRUE]
    /\ learnerStage = [s \in Server |-> "IDLE"]
    /\ sessionMode = [s \in Server |-> "NONE"]
    /\ logCursor = [s \in Server |-> 0]
    /\ leakedQueued = [s \in Server |-> <<>>]

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
    /\ dbInitialized = [s \in Server |-> FALSE]
    /\ learnerStage = [s \in Server |-> "IDLE"]
    /\ sessionMode = [s \in Server |-> "NONE"]
    /\ logCursor = [s \in Server |-> 0]
    /\ leakedQueued = [s \in Server |-> <<>>]

\* Process start/restart: QuorumPeer.start -> loadDataBase (QuorumPeer.java:1083-1149).
\* A new QuorumPeer object starts with SyncMode.NONE (QuorumPeer.java:847) and no
\* request processors; leaked threads of the previous process are gone.
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
    /\ dbInitialized' = [dbInitialized EXCEPT ![s] = TRUE]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "IDLE"]
    /\ sessionMode' = [sessionMode EXCEPT ![s] = "NONE"]
    /\ logCursor' = [logCursor EXCEPT ![s] = Len(durable[s])]
    /\ leakedQueued' = [leakedQueued EXCEPT ![s] = <<>>]
    /\ UNCHANGED <<electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, durable, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

\* UPDATE-MAP
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1257-1262 getLastLoggedZxid
\* update: Update!AffectedActions (MCReload) -- consumer of the cleared database
\* In-process reload after zkDb.clear(): getLastLoggedZxid -> loadDataBase.
ReloadDatabase(s) ==
    /\ s \in Server /\ running[s] /\ ~dbInitialized[s]
    /\ dbInitialized' = [dbInitialized EXCEPT ![s] = TRUE]
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![s] = durable[s]]
    /\ prepared' = [prepared EXCEPT ![s] = durable[s]]
    /\ logCursor' = [logCursor EXCEPT ![s] = Len(durable[s])]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, pending, durable, committed,
                    applied, globalCommitted, acks, durabilityEvidence,
                    commitWitness, nextTxn, snapshotBusy, snapshotImage,
                    snapshotPublished, learnerStage, sessionMode, leakedQueued>>

\* QuorumPeer.shutdown: running=false is published first (QuorumPeer.java:1538-1540);
\* the learner shutdown that follows is the separate LearnerShutdown observation.
GracefulShutdown(s) ==
    /\ s \in Server /\ running[s]
    /\ running' = [running EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor,
                    leakedQueued>>

\* Abrupt process crash: all volatile state, including any leaked sync thread,
\* is lost; only durable files survive.
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
    /\ dbInitialized' = [dbInitialized EXCEPT ![s] = FALSE]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "IDLE"]
    /\ sessionMode' = [sessionMode EXCEPT ![s] = "NONE"]
    /\ leakedQueued' = [leakedQueued EXCEPT ![s] = <<>>]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, epochProposal,
                    electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, prepared,
                    durable, recoveryVisible, committed, applied,
                    globalCommitted, acks, durabilityEvidence, commitWitness,
                    nextTxn, snapshotImage, snapshotPublished, logCursor>>

\* A new election round after the active leader is gone.  Running followers
\* leave through LearnerShutdown first (QuorumPeer.java:1468-1480), so the round
\* starts only when no running peer is still FOLLOWING.  The stale QuorumPeer
\* syncMode is not reset by an election (no setSyncMode call on this path).
BeginElectionRound(c) ==
    /\ c \in Server /\ running[c]
    /\ ~\E s \in Server : running[s] /\ role[s] = "LEADING" /\ phase[s] = "BROADCAST"
    /\ ~\E s \in Server : running[s] /\ role[s] = "FOLLOWING"
    /\ electionRound' = electionRound + 1
    /\ votedFor' = [s \in Server |-> NoServer]
    /\ electionVotes' = [s \in Server |-> {}]
    /\ role' = [s \in Server |-> IF running[s] THEN "LOOKING" ELSE role[s]]
    /\ phase' = [s \in Server |-> IF running[s] THEN "ELECTION" ELSE phase[s]]
    /\ leaderOf' = [s \in Server |-> IF running[s] THEN NoServer ELSE leaderOf[s]]
    /\ epochAcks' = [s \in Server |-> {}]
    /\ newLeaderAcks' = [s \in Server |-> {}]
    /\ newLeaderReady' = [s \in Server |-> IF running[s] THEN FALSE ELSE newLeaderReady[s]]
    /\ syncComplete' = [s \in Server |-> IF running[s] THEN FALSE ELSE syncComplete[s]]
    /\ UNCHANGED <<running, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor,
                    leakedQueued>>

\* lookForLeader first calls getLastLoggedZxid (FastLeaderElection.java:957-975),
\* which reloads an uninitialized database; voting therefore needs dbInitialized.
CastVote(v, c) ==
    /\ v \in Server /\ c \in Server /\ running[v] /\ running[c]
    /\ dbInitialized[v]
    /\ phase[v] = "ELECTION" /\ votedFor[v] = NoServer
    /\ votedFor' = [votedFor EXCEPT ![v] = c]
    /\ electionVotes' = [electionVotes EXCEPT ![c] = @ \cup {v}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf,
                    acceptedEpoch, currentEpoch, epochProposal, electionRound,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

FinishElection(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s] /\ dbInitialized[s]
    /\ role[s] = "LOOKING"
    /\ Quorum(electionVotes[c]) /\ ElectionUpToDate(c)
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, electionRound, votedFor, electionVotes,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

\* A LOOKING peer accepts an already established leader from LEADING/FOLLOWING
\* notifications plus leader confirmation, without the zxid comparison
\* (FastLeaderElection.java:1054-1088 ooe/checkLeader path).
JoinEstablishedLeader(s, c) ==
    /\ s \in Server /\ c \in Server /\ s /= c
    /\ running[s] /\ running[c] /\ dbInitialized[s]
    /\ role[s] = "LOOKING" /\ phase[s] = "ELECTION"
    /\ role[c] = "LEADING" /\ Quorum(electionVotes[c])
    /\ role' = [role EXCEPT ![s] = "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, electionRound, votedFor, electionVotes,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

\* Trace observation of a completed lookForLeader.  Joining an established
\* leader skips the zxid comparison, as in JoinEstablishedLeader.
ObserveElectionResult(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s]
    /\ IF s /= c /\ role[c] = "LEADING" THEN TRUE ELSE ElectionUpToDate(c)
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ electionVotes' = [electionVotes EXCEPT ![c] = Server]
    /\ votedFor' = [votedFor EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, electionRound, epochAcks, newLeaderAcks,
                    newLeaderReady, syncComplete, prepared, syncQueued,
                    pending, durable, recoveryVisible, committed, applied,
                    globalCommitted, acks, durabilityEvidence, commitWitness,
                    nextTxn, snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor,
                    leakedQueued>>

ObserveSetZabState(s, p) ==
    /\ s \in Server /\ p \in Phases
    /\ phase' = [phase EXCEPT ![s] = p]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor,
                    leakedQueued>>

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
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

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
                    snapshotPublished, dbInitialized, learnerStage,
                    sessionMode, logCursor, leakedQueued>>

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
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

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
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

\* Leader.lead: the leader's own request processors (and sync processor) are
\* created by startZkServer later; its database view is the loaded tree.
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
                    snapshotPublished, dbInitialized, learnerStage,
                    sessionMode, logCursor, leakedQueued>>

\* Trace observation of QuorumPeer.setSyncMode(DIFF|SNAP|TRUNC) at
\* Learner.java:563,566,589, before the mode-specific database work.
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
                    snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor,
                    leakedQueued>>

\* Leader-side mode choice (LearnerHandler.java:775-935), projected onto
\* prefix histories: DIFF when the learner's reported zxid is covered by the
\* leader tree; TRUNC when it is newer than the leader's max committed log
\* (LearnerHandler.java:853-861); SNAP is always possible (forceSnapSync,
\* committed-log/txn-log coverage limits, LearnerHandler.java:836-839,865-905).
ModeAllowed(f, l, m) ==
    \/ m = "SNAP"
    \/ m = "DIFF" /\ ElectionZxid(f) <= LeaderTreeZxid(l)
    \/ m = "TRUNC" /\ ElectionZxid(f) > LeaderTreeZxid(l)

\* UPDATE-MAP
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:546-614 syncWithLeader mode packet
\* update: Update!InteractionActions (MCReceiveSync) -- producer of the in-memory/disk split
\* SNAP: deserializeSnapshot replaces only the in-memory database (Learner.java:566-583);
\*       the leader serialized its data tree (LearnerHandler.java:549-575).
\* TRUNC: ZKDatabase.truncateLog clears, truncates the log, reloads (ZKDatabase.java:599-622).
\* DIFF: no database change before NEWLEADER (writeToTxnLog = true, Learner.java:614).
ReceiveSyncMode(f, l, m) ==
    /\ f \in Server /\ l \in Server /\ m \in {"DIFF", "SNAP", "TRUNC"}
    /\ running[f] /\ running[l] /\ dbInitialized[f]
    /\ role[f] = "FOLLOWING" /\ leaderOf[f] = l /\ role[l] = "LEADING"
    /\ phase[l] \in {"SYNCHRONIZATION", "BROADCAST"}
    /\ learnerStage[f] = "IDLE"
    /\ ModeAllowed(f, l, m)
    /\ syncMode' = [syncMode EXCEPT ![f] = m]
    /\ sessionMode' = [sessionMode EXCEPT ![f] = m]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "MODE"]
    /\ durable' = [durable EXCEPT ![f] =
          IF m = "TRUNC" THEN AtMostSeq(durable[f], LeaderTreeZxid(l)) ELSE @]
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![f] =
          CASE m = "SNAP" -> applied[l]
            [] m = "TRUNC" -> AtMostSeq(durable[f], LeaderTreeZxid(l))
            [] OTHER -> @]
    /\ prepared' = [prepared EXCEPT ![f] =
          CASE m = "SNAP" -> applied[l]
            [] m = "TRUNC" -> AtMostSeq(durable[f], LeaderTreeZxid(l))
            [] OTHER -> @]
    /\ logCursor' = [logCursor EXCEPT ![f] =
          CASE m = "SNAP" -> Len(applied[l])
            [] m = "TRUNC" -> Len(AtMostSeq(durable[f], LeaderTreeZxid(l)))
            [] OTHER -> @]
    /\ UNCHANGED <<running, role, phase, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, pending, committed, applied,
                    globalCommitted, acks, durabilityEvidence, commitWitness,
                    nextTxn, snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, leakedQueued>>

\* UPDATE-MAP
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:643-668 COMMIT with !writeToTxnLog
\* update: Update!InteractionActions (MCSyncApply) -- in-memory-only state the abort must discard
\* SNAP/TRUNC before NEWLEADER: a COMMIT for the head proposal is applied directly
\* to the in-memory tree and is not written to the transaction log.  COMMITs come
\* from Leader.startForwarding toBeApplied (Leader.java:1289-1305) or live commits
\* sent to forwarding followers (Leader.java:918-960).
SyncApplyCommitted(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING" /\ leaderOf[f] \in Server
    /\ learnerStage[f] = "MODE" /\ sessionMode[f] \in {"SNAP", "TRUNC"}
    /\ t \in Elems(committed[leaderOf[f]])
    /\ t = LastOr0(recoveryVisible[f]) + 1
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![f] = Append(@, t)]
    /\ prepared' = [prepared EXCEPT ![f] = AppendOnce(@, t)]
    /\ logCursor' = [logCursor EXCEPT ![f] = Len(AppendOnce(prepared[f], t))]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, pending, durable, committed,
                    applied, globalCommitted, acks, durabilityEvidence,
                    commitWitness, nextTxn, snapshotBusy, snapshotImage,
                    snapshotPublished, dbInitialized, learnerStage,
                    sessionMode, leakedQueued>>

\* Trace observation: ZooKeeperServer.takeSnapshot entered for the NEWLEADER
\* learner snapshot (Learner.java:738-741).
BeginSyncSnapshot(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ learnerStage[f] = "MODE" /\ sessionMode[f] \in {"SNAP", "TRUNC"}
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![f] = TRUE]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

\* UPDATE-MAP
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:738-741 takeSnapshot at NEWLEADER
\* update: Update!InteractionActions (MCPersistSyncSnapshot) -- closes the abort window
\* snapshotNeeded (SNAP/TRUNC): the in-memory tree becomes durable.
PersistSyncSnapshot(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ learnerStage[f] = "MODE" /\ sessionMode[f] \in {"SNAP", "TRUNC"}
    /\ durable' = [durable EXCEPT ![f] = SnapRestore(recoveryVisible[f], durable[f])]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![f] = FALSE]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "SNAPPED"]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotImage, snapshotPublished, dbInitialized,
                    sessionMode, logCursor, leakedQueued>>

\* UPDATE-MAP
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:744-759 setSyncMode(NONE), startupWithoutServing, NEWLEADER ACK
\* update: Update!InteractionActions (MCAckNewLeader) -- after this point fullyShutDown is false
\* The serving pipeline of the follower is (re)based on the in-memory tree; its
\* local committed/applied histories are the committed part of that tree.
LearnerAckNewLeader(f, l) ==
    /\ f \in Server /\ l \in Server /\ running[f]
    /\ role[f] = "FOLLOWING" /\ leaderOf[f] = l
    /\ \/ learnerStage[f] = "MODE" /\ sessionMode[f] = "DIFF"
       \/ learnerStage[f] = "SNAPPED"
    /\ syncMode' = [syncMode EXCEPT ![f] = "NONE"]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "NEWLEADER"]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = @ \cup {f}]
    /\ committed' = [committed EXCEPT ![f] = CommittedPart(recoveryVisible[f])]
    /\ applied' = [applied EXCEPT ![f] = CommittedPart(recoveryVisible[f])]
    /\ UNCHANGED <<running, role, phase, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderReady, syncComplete,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    globalCommitted, acks, durabilityEvidence, commitWitness,
                    nextTxn, snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, sessionMode, logCursor, leakedQueued>>

\* UPTODATE processed and syncWithLeader returned (Learner.java:711-725,762-792;
\* Follower.java:108-110).  zk.startServing makes the zk state RUNNING.
CompleteLearnerSync(f, l, m) ==
    /\ f \in Server /\ l \in Server /\ m \in Modes
    /\ running[f] /\ running[l] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] = l /\ role[l] = "LEADING" /\ newLeaderReady[l]
    /\ learnerStage[f] = "NEWLEADER" /\ ~syncComplete[f]
    /\ m = sessionMode[f]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = TRUE]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

\* UPDATE-MAP
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:850-866 shutdown -> zk.shutdown(syncMode == SNAP)
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:803-859 shutdown(boolean)
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerZooKeeperServer.java:155-173 shutdown() override (old path only)
\* update: Update!AffectedActions (MCLearnerExit)
\* fullyShutDown (new): QuorumPeer syncMode is still SNAP, i.e. NEWLEADER did not
\* reach setSyncMode(NONE).  canShutdown is true only after UPTODATE
\* (startServing); otherwise the server returns early (and, new, clears the
\* database when fullyShutDown).  For a running server the learner sync
\* processor is drained only by the LearnerZooKeeperServer.shutdown() override,
\* which the new one-argument call bypasses; the processor thread then keeps
\* its queue (leakedQueued).  A sync processor started at NEWLEADER but not yet
\* serving is not stopped by either revision.
LearnerFully(f) == CodeVersion = "new" /\ syncMode[f] = "SNAP"
LearnerZkRunning(f) == syncComplete[f]
LearnerDrains(f) == CodeVersion = "old" /\ LearnerZkRunning(f)
\* fastForwardDataBase replays log records newer than the tree (ZKDatabase.java:300-322)
FastForward(f) ==
    LET tree == LongerOf(recoveryVisible[f], applied[f])
    IN tree \o AboveSeq(durable[f], LastOr0(tree))

LearnerShutdownEffects(f) ==
    LET mem == IF LearnerZkRunning(f) THEN FastForward(f) ELSE recoveryVisible[f]
        dur == IF LearnerDrains(f) THEN AppendAllOnce(durable[f], syncQueued[f]) ELSE durable[f]
        init == IF LearnerFully(f) THEN FALSE ELSE dbInitialized[f]
        view == IF init THEN mem ELSE dur
    IN
    /\ f \in Server
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![f] = mem]
    /\ durable' = [durable EXCEPT ![f] = dur]
    /\ durabilityEvidence' = [t \in Txn |->
          IF LearnerDrains(f) /\ t \in Elems(syncQueued[f])
          THEN durabilityEvidence[t] \cup {f} ELSE durabilityEvidence[t]]
    /\ leakedQueued' = [leakedQueued EXCEPT ![f] =
          IF LearnerDrains(f) THEN @ ELSE @ \o syncQueued[f]]
    /\ syncQueued' = [syncQueued EXCEPT ![f] = <<>>]
    /\ dbInitialized' = [dbInitialized EXCEPT ![f] = init]
    /\ prepared' = [prepared EXCEPT ![f] = view]
    /\ logCursor' = [logCursor EXCEPT ![f] = Len(view)]
    /\ pending' = [pending EXCEPT ![f] = <<>>]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "IDLE"]
    /\ sessionMode' = [sessionMode EXCEPT ![f] = "NONE"]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = FALSE]
    /\ UNCHANGED <<syncMode, acceptedEpoch, currentEpoch, epochProposal,
                    electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, newLeaderReady, committed, applied,
                    globalCommitted, acks, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished>>

\* Trace observation: the LearnerShutdown probe follows zk.shutdown; the role and
\* phase reset are the separately logged updateServerState events.
LearnerShutdown(f) ==
    /\ f \in Server /\ role[f] = "FOLLOWING"
    /\ LearnerShutdownEffects(f)
    /\ UNCHANGED <<running, role, phase, leaderOf>>

\* Model-checking form: the following session ends with an exception
\* (connection loss, sync timeout, IOException in readPacket) and
\* QuorumPeer.run's finally runs follower.shutdown then updateServerState
\* (QuorumPeer.java:1468-1480, 855-859).
LearnerExit(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ LearnerShutdownEffects(f)
    /\ role' = [role EXCEPT ![f] = "LOOKING"]
    /\ phase' = [phase EXCEPT ![f] = "ELECTION"]
    /\ leaderOf' = [leaderOf EXCEPT ![f] = NoServer]
    /\ UNCHANGED running

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
                    snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor,
                    leakedQueued>>

\* FollowerZooKeeperServer.logRequest (FollowerZooKeeperServer.java:82-90),
\* reached only once NEWLEADER switched writeToTxnLog on (Learner.java:752-756,
\* 778-785) or from Follower.processPacket in broadcast.  FIFO leader channel.
FollowerPendingProposal(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING"
    /\ phase[f] \in {"SYNCHRONIZATION", "BROADCAST"}
    /\ learnerStage[f] = "NEWLEADER"
    /\ leaderOf[f] \in Server /\ t \in Elems(prepared[leaderOf[f]])
    /\ t = LastOr0(prepared[f]) + 1
    /\ pending' = [pending EXCEPT ![f] = AppendOnce(@, t)]
    /\ prepared' = [prepared EXCEPT ![f] = AppendOnce(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

\* SyncRequestProcessor.processRequest (SyncRequestProcessor.java:273-283): the
\* current processor receives prepared entries in order; entries delivered by
\* snapshot/direct apply are not handed to it (logCursor).
QueueForSync(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ \/ role[s] = "LEADING"
       \/ role[s] = "FOLLOWING" /\ learnerStage[s] = "NEWLEADER"
    /\ logCursor[s] < Len(prepared[s])
    /\ t = prepared[s][logCursor[s] + 1]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = Append(@, t)]
    /\ logCursor' = [logCursor EXCEPT ![s] = @ + 1]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, leakedQueued>>

\* SyncRequestProcessor append + flush of the queue head (SyncRequestProcessor.java
\* :180-250); FileTxnLog.append does not reject a non-contiguous zxid
\* (FileTxnLog.java:274-282).  Replay of an already present record is a no-op,
\* so the durable history is the in-order set of distinct records.
FlushTxnLog(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ Len(syncQueued[s]) > 0 /\ t = Head(syncQueued[s])
    /\ durable' = [durable EXCEPT ![s] = AppendOnce(@, t)]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = Tail(@)]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = @ \cup {s}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, pending,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, commitWitness, nextTxn, snapshotBusy, snapshotImage,
                    snapshotPublished, dbInitialized, learnerStage,
                    sessionMode, logCursor, leakedQueued>>

\* UPDATE-MAP
\* code: zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:155-250 run loop of a processor zk.shutdown(boolean) did not stop
\* update: Update!InteractionActions (MCLeakedFlush)
\* The old session's processor still appends its queue to the shared ZKDatabase
\* log; its ACK goes to the closed learner socket and is never counted.
LeakedFlush(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ Len(leakedQueued[s]) > 0 /\ t = Head(leakedQueued[s])
    /\ durable' = [durable EXCEPT ![s] = AppendOnce(@, t)]
    /\ leakedQueued' = [leakedQueued EXCEPT ![s] = Tail(@)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending,
                    recoveryVisible, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor>>

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
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

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
                    nextTxn, snapshotBusy, snapshotImage, snapshotPublished,
                    dbInitialized, learnerStage, sessionMode, logCursor,
                    leakedQueued>>

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
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

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
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued>>

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
                    snapshotPublished, dbInitialized, learnerStage,
                    sessionMode, logCursor, leakedQueued>>

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
                    snapshotImage, dbInitialized, learnerStage, sessionMode,
                    logCursor, leakedQueued>>

