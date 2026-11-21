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
NoPlan == [mode |-> "NONE", z |-> 0, cut |-> 0]
TransitionNames == {
    "Init", "RestartLoadDatabase", "GracefulShutdown", "Crash",
    "BeginElectionRound", "CastVote", "FinishElection", "JoinEstablishedLeader",
    "SetPeerState", "SetZabState", "PersistAcceptedEpoch", "PersistCurrentEpoch",
    "RecordEpochAck", "FormEpochQuorum", "ChooseSyncMode",
    "LeaderDecideSync", "ReceiveSyncMode", "SyncApplyCommitted", "PersistSyncSnapshot",
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
    leakedQueued,   \* queue of a learner SyncRequestProcessor that zk.shutdown did not stop
    syncCommitCut,  \* last leader commit that can precede NEWLEADER in this session
    syncPlan        \* leader-side sync decision for this learner (LearnerHandler.syncFollower)

vars == <<
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    prepared, syncQueued, pending, durable, recoveryVisible,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished,
    dbInitialized, learnerStage, sessionMode, logCursor, leakedQueued,
    syncCommitCut, syncPlan
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
    /\ syncCommitCut = [s \in Server |-> 0]
    /\ syncPlan = [s \in Server |-> NoPlan]

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
    /\ syncCommitCut = [s \in Server |-> 0]
    /\ syncPlan = [s \in Server |-> NoPlan]

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
    /\ syncPlan' = [syncPlan EXCEPT ![s] = NoPlan]
    /\ UNCHANGED <<electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, durable, committed, applied, globalCommitted,
                    acks, durabilityEvidence, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished, syncCommitCut>>

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
                    snapshotPublished, learnerStage, sessionMode, leakedQueued, syncCommitCut, syncPlan>>

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
                    leakedQueued, syncCommitCut, syncPlan>>

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
    /\ syncPlan' = [syncPlan EXCEPT ![s] = NoPlan]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, epochProposal,
                    electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, prepared,
                    durable, recoveryVisible, committed, applied,
                    globalCommitted, acks, durabilityEvidence, commitWitness,
                    nextTxn, snapshotImage, snapshotPublished, logCursor, syncCommitCut>>

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
                    leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    leakedQueued, syncCommitCut, syncPlan>>

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
                    leakedQueued, syncCommitCut, syncPlan>>

\* QuorumPeer.setPeerState (QuorumPeer.java:853-861, synchronized): LOOKING also
\* clears the leader address and sets ZabState.ELECTION in the same method;
\* updateServerState -> LOOKING ends the following session.
ObserveSetPeerState(s, r) ==
    /\ s \in Server /\ r \in Roles
    /\ role' = [role EXCEPT ![s] = r]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = IF r = "LOOKING" THEN NoServer ELSE @]
    /\ phase' = [phase EXCEPT ![s] = IF r = "LOOKING" THEN "ELECTION" ELSE @]
    /\ syncComplete' = [syncComplete EXCEPT ![s] = IF r = "LOOKING" THEN FALSE ELSE @]
    /\ UNCHANGED <<running, syncMode, acceptedEpoch, currentEpoch,
                    epochProposal, electionRound, votedFor, electionVotes,
                    epochAcks, newLeaderAcks, newLeaderReady,
                    prepared, syncQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    leakedQueued, syncCommitCut, syncPlan>>

\* Leader-side mode choice (LearnerHandler.java:775-935), projected onto
\* prefix histories: DIFF when the learner's reported zxid is covered by the
\* leader tree; TRUNC when it is newer than the leader's max committed log
\* (LearnerHandler.java:853-861); SNAP is always possible (forceSnapSync,
\* committed-log/txn-log coverage limits, LearnerHandler.java:836-839,865-905).
ModeAllowed(f, l, m) ==
    \/ m = "SNAP"
    \/ m = "DIFF" /\ ElectionZxid(f) <= LeaderTreeZxid(l)
    \/ m = "TRUNC" /\ ElectionZxid(f) > LeaderTreeZxid(l)

\* Leader side: LearnerHandler.syncFollower chooses the mode and registers the
\* learner for forwarding (Leader.startForwarding) under the committed-log read
\* lock (LearnerHandler.java:775-935).  The truncation point is the leader's max
\* committed log at that moment; the commits queued before NEWLEADER are the
\* leader's commits up to startForwarding (toBeApplied, Leader.java:1289-1305),
\* or, for SNAP, any commit forwarded during snapshot serialization.
LeaderDecideSync(l, f, m) ==
    /\ l \in Server /\ f \in Server /\ m \in {"DIFF", "SNAP", "TRUNC"}
    /\ running[f] /\ running[l] /\ dbInitialized[f]
    /\ role[f] = "FOLLOWING" /\ leaderOf[f] = l /\ role[l] = "LEADING"
    /\ phase[f] \in {"DISCOVERY", "SYNCHRONIZATION"}
    /\ learnerStage[f] = "IDLE" /\ syncPlan[f].mode = "NONE"
    /\ ModeAllowed(f, l, m)
    /\ syncPlan' = [syncPlan EXCEPT ![f] =
          [mode |-> m, z |-> LeaderTreeZxid(l),
           cut |-> IF m = "SNAP" THEN MaxTxn ELSE Len(committed[l])]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, prepared, syncQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted, acks,
                    durabilityEvidence, commitWitness, nextTxn, snapshotBusy,
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued,
                    syncCommitCut>>

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
    \* LearnerHandler.run syncs after its own waitForEpochAck returns
    \* (LearnerHandler.java:520-560); the leader thread's setZabState may lag.
    /\ learnerStage[f] = "IDLE"
    /\ syncPlan[f].mode = m
    /\ syncMode' = [syncMode EXCEPT ![f] = m]
    /\ syncPlan' = [syncPlan EXCEPT ![f] = NoPlan]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = FALSE]
    /\ sessionMode' = [sessionMode EXCEPT ![f] = m]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "MODE"]
    /\ durable' = [durable EXCEPT ![f] =
          IF m = "TRUNC" THEN AtMostSeq(durable[f], syncPlan[f].z) ELSE @]
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![f] =
          CASE m = "SNAP" -> applied[l]
            [] m = "TRUNC" -> AtMostSeq(durable[f], syncPlan[f].z)
            [] OTHER -> @]
    /\ prepared' = [prepared EXCEPT ![f] =
          CASE m = "SNAP" -> applied[l]
            [] m = "TRUNC" -> AtMostSeq(durable[f], syncPlan[f].z)
            [] OTHER -> @]
    \* Which leader commits can reach the learner before NEWLEADER
    \* (LearnerHandler.java:549-600): startForwarding queues toBeApplied
    \* PROPOSAL+COMMIT pairs (Leader.java:1289-1305) before NEWLEADER is queued;
    \* for SNAP, live commits forwarded during snapshot serialization also
    \* precede NEWLEADER.  (A live commit in the microsecond window between
    \* startForwarding and the TRUNC/DIFF NEWLEADER enqueue is not modeled.)
    /\ syncCommitCut' = [syncCommitCut EXCEPT ![f] = syncPlan[f].cut]
    /\ logCursor' = [logCursor EXCEPT ![f] =
          CASE m = "SNAP" -> Len(applied[l])
            [] m = "TRUNC" -> Len(AtMostSeq(durable[f], syncPlan[f].z))
            [] OTHER -> @]
    /\ UNCHANGED <<running, role, phase, leaderOf, acceptedEpoch,
                    currentEpoch, epochProposal, electionRound, votedFor,
                    electionVotes, epochAcks, newLeaderAcks, newLeaderReady,
                    syncQueued, pending, committed, applied,
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
    /\ t \in Elems(committed[leaderOf[f]]) /\ t <= syncCommitCut[f]
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
                    sessionMode, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    dbInitialized, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
LearnerZkRunning(f) == syncComplete[f] /\ learnerStage[f] = "NEWLEADER"
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
    /\ syncPlan' = [syncPlan EXCEPT ![f] = NoPlan]
    /\ UNCHANGED <<syncMode, acceptedEpoch, currentEpoch, epochProposal,
                    electionRound, votedFor, electionVotes, epochAcks,
                    newLeaderAcks, newLeaderReady, committed, applied,
                    globalCommitted, acks, commitWitness, nextTxn,
                    snapshotBusy, snapshotImage, snapshotPublished, syncCommitCut>>

\* Trace observation: the LearnerShutdown probe follows zk.shutdown; the role and
\* phase reset are the separately logged updateServerState events.
LearnerShutdown(f) ==
    /\ f \in Server /\ role[f] = "FOLLOWING"
    /\ LearnerShutdownEffects(f)
    /\ UNCHANGED <<running, role, phase, leaderOf, syncComplete>>

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
    /\ syncComplete' = [syncComplete EXCEPT ![f] = FALSE]
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
                    leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, leakedQueued, syncCommitCut, syncPlan>>

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
                    sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    dbInitialized, learnerStage, sessionMode, logCursor, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    leakedQueued, syncCommitCut, syncPlan>>

\* FollowerZooKeeperServer.commit (FollowerZooKeeperServer.java:97-112): the
\* COMMIT is processed after logRequest handed the proposal to the sync
\* processor in the same thread (FollowerZooKeeperServer.java:82-90).
FollowerCommit(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING" /\ t \in Elems(pending[f])
    /\ t \in Elems(SubSeq(prepared[f], 1, logCursor[f]))
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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    snapshotImage, snapshotPublished, dbInitialized,
                    learnerStage, sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

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
                    snapshotPublished, dbInitialized, learnerStage,
                    sessionMode, logCursor, leakedQueued, syncCommitCut, syncPlan>>

\* REQ-EVIDENCE TypeOK
\* intent:   every base-model variable stays inside the domain declared for it
\* status:   model-internal
\* verified: update (case-010; five incremental variables added)
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
    /\ dbInitialized \in [Server -> BOOLEAN]
    /\ learnerStage \in [Server -> Stages]
    /\ sessionMode \in [Server -> Modes]
    /\ logCursor \in [Server -> 0..MaxTxn]
    /\ leakedQueued \in [Server -> Seq(Txn)]
    /\ syncCommitCut \in [Server -> 0..MaxTxn]
    /\ syncPlan \in [Server -> [mode : Modes, z : 0..MaxTxn, cut : 0..MaxTxn]]

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
\* watch:    Leader.java:propose; Leader.java:tryToCommit; Follower.java:processPacket; Learner.java:syncWithLeader; Learner.java:shutdown (touched by update); FollowerZooKeeperServer.java:logRequest; FollowerZooKeeperServer.java:commit; SyncRequestProcessor.java:run; CommitProcessor.java:run
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


\* A learner synchronization replacement step: the mode packet (TRUNC cuts the
\* log), the NEWLEADER snapshot, the NEWLEADER ACK that rebases the follower's
\* local commit pipeline on the synchronized tree, or UPTODATE completion.
SyncReplacementStep ==
    \E f \in Server :
        \/ /\ learnerStage'[f] /= learnerStage[f]
           /\ learnerStage'[f] \in {"MODE", "SNAPPED", "NEWLEADER"}
        \/ ~syncComplete[f] /\ syncComplete'[f]

MonotoneStep ==
    \/ SyncReplacementStep
    \/ /\ \A s \in Server : Len(durable'[s]) >= Len(durable[s])
       /\ \A s \in Server : Len(committed'[s]) >= Len(committed[s])
       /\ \A s \in Server : Len(applied'[s]) >= Len(applied[s])

\* REQ-EVIDENCE MonotoneUnlessRecovery
\* intent:   except in a learner synchronization step (mode packet, NEWLEADER snapshot, NEWLEADER ACK, or UPTODATE completion), no server's logged, committed or applied history ever becomes shorter
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:182 "have not been committed, so they can be discarded. When the follower connects" -> the proposals a follower discards are uncommitted ones, discarded when it connects to the leader (sync), so committed proposals are not discarded
\* evidence: contract source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/TxnLog.java:83 "truncate the log to get in sync with the" -> the log-truncation operation is documented as a step of getting in sync with the leader
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:830 "3. Follower has txn that we haven't seen. This may be old leader" -> the leader cuts a follower's log with TRUNC during sync when the follower has transactions the leader has not seen
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java:213 testInconsistentDueToUncommittedLog "Data inconsistency detected!" -> a write visible at the old leader is still present at the new leader after the quorum recovers
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:591 "boolean truncated = zk.getZKDatabase().truncateLog(qp.getZxid());"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:570 "zk.getZKDatabase().deserializeSnapshot(leaderIs);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:740 "zk.takeSnapshot(syncSnapshot);"
\* watch:    Learner.java:syncWithLeader; Learner.java:shutdown; LearnerHandler.java:syncFollower; ZKDatabase.java:truncateLog; ZKDatabase.java:deserializeSnapshot; ZKDatabase.java:clear; FileTxnSnapLog.java:truncateLog; SyncRequestProcessor.java:run
\* verified: update (case-010)
\* clause durable-shrinks-only-in-sync: requirement — doc zookeeperInternals.md:176-183, comment LearnerHandler.java:830-831 and contract TxnLog.java:82-84 tie log truncation to synchronization with a leader
\* clause committed-and-applied-shrink-only-in-sync: requirement — doc zookeeperInternals.md:180-182 (only uncommitted proposals are discarded) and test DIFFSyncConsistencyTest.java:213
\* clause sync-step-exemption: impl-abstraction — revised: the source performs the replacement at the mode packet (Learner.java:559-608), the NEWLEADER snapshot (Learner.java:738-741) and the NEWLEADER ACK/serving restart (Learner.java:744-759), not only when syncWithLeader returns; the exemption now names those steps (separating state E3 in spec/invariant-evidence.json)
\* note:     the update moves no replacement point; the exemption is re-expressed because the reference splits the previously atomic CompleteLearnerSync
\* review:   exemption migrated from "syncComplete flips" to the split learner-sync steps; durable/committed/applied monotonicity outside those steps is unchanged.
MonotoneUnlessRecovery == [][MonotoneStep]_vars

InvariantSet ==
    TypeOK /\ ActiveLeaderUniqueness /\ AcceptedEpochGECurrentEpoch
    /\ OrderedHistories /\ CommittedPrefixAgreement
    /\ NormalAckHasDurabilityEvidence /\ ApplyHasCommitCertificate
    /\ SyncEntryJustified /\ SnapshotPublishedValid

(***************************************************************************)
(* Canonical source-derived base schedule.  The MC module expands ordinary *)
(* server choices; this driver gives base.cfg a finite transition relation  *)
(* that exercises every persistence/history boundary, including the split   *)
(* learner synchronization and one learner shutdown after all proposals.    *)
(***************************************************************************)
BaseLeader == CHOOSE s \in Server : TRUE
BaseFollower == CHOOSE s \in Server \ {BaseLeader} : TRUE

BaseNext ==
    \/ \E v \in Server : CastVote(v, BaseLeader)
    \/ FinishElection(BaseLeader, BaseLeader)
    \/ FinishElection(BaseFollower, BaseLeader)
    \/ JoinEstablishedLeader(BaseFollower, BaseLeader)
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
       /\ phase[BaseLeader] \in {"SYNCHRONIZATION", "BROADCAST"}
       /\ currentEpoch[BaseFollower] = currentEpoch[BaseLeader]
       /\ ObserveSetZabState(BaseFollower, "SYNCHRONIZATION")
    \/ \E m \in {"DIFF", "TRUNC", "SNAP"} : LeaderDecideSync(BaseLeader, BaseFollower, m)
    \/ \E m \in {"DIFF", "TRUNC", "SNAP"} :
          /\ phase[BaseFollower] = "SYNCHRONIZATION"
          /\ ReceiveSyncMode(BaseFollower, BaseLeader, m)
    \/ \E t \in Txn : SyncApplyCommitted(BaseFollower, t)
    \/ PersistSyncSnapshot(BaseFollower)
    \/ LearnerAckNewLeader(BaseFollower, BaseLeader)
    \/ CompleteLearnerSync(BaseFollower, BaseLeader, sessionMode[BaseFollower])
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
    \/ \E t \in Txn : LeakedFlush(BaseFollower, t)
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
    \/ /\ nextTxn = MaxTxn + 1
       /\ LearnerExit(BaseFollower)
    \/ ReloadDatabase(BaseFollower)
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
