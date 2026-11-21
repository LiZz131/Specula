------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

(***************************************************************************)
(* Code-faithful finite abstraction of the ZooKeeper Zab path, revised for *)
(* the `update` revision (Learner.shutdown -> zk.shutdown(isSnap),          *)
(* ZooKeeperServer.shutdown(boolean) clears an unstarted database).         *)
(* Histories contain transaction identifiers in zxid order; identifiers are *)
(* unique system-wide, so a lost (never committed) proposal leaves a gap in *)
(* later histories.                                                        *)
(*                                                                         *)
(* Variable meanings (per server s):                                       *)
(*   prepared[s]     in-memory history of the zkDb: the DataTree plus      *)
(*                   in-memory accepted proposals.  It is the baseline that *)
(*                   QuorumPeer.getLastLoggedZxid() advertises in          *)
(*                   FOLLOWERINFO (QuorumPeer.java:1257-1262).              *)
(*   durable[s]      recoverable on-disk history: latest snapshot followed *)
(*                   by WAL records, in replay order                       *)
(*                   (FileTxnSnapLog.java:243-368).  May contain gaps or    *)
(*                   out-of-order records if the implementation writes them.*)
(*   syncQueued[s]   current SyncRequestProcessor queue (queued, unflushed).*)
(*   leakedQueued[s] queues (one FIFO per thread) of learner                *)
(*                   SyncRequestProcessors that were not shut down when    *)
(*                   their learner exited; each keeps appending to the     *)
(*                   shared txn log (SyncRequestProcessor.java:156-222)    *)
(*                   without a live leader connection.                     *)
(*   pending[s]      FollowerZooKeeperServer.pendingTxns.                  *)
(*   committed[s], applied[s]  commit-processor / FinalRequestProcessor    *)
(*                   histories (client-visible state), as in the prior run. *)
(*   learnerStage[s] program counter of Learner.syncWithLeader.            *)
(*   dbCleared[s]    zkDb.clear() ran and the database is uninitialized     *)
(*                   until the next getLastLoggedZxid() reload.            *)
(***************************************************************************)

CONSTANTS Server, MaxEpoch, MaxTxn, NoServer,
          \* "UPDATED" = update revision (Learner.java:860-865,
          \* ZooKeeperServer.java:803-810).  "PRIOR" = exact-old revision,
          \* used only by attribution controls (spec/evidence, control cfgs).
          LearnerShutdownSemantics

ASSUME LearnerShutdownSemantics \in {"UPDATED", "PRIOR"}

Txn == 1..MaxTxn
Roles == {"LOOKING", "LEADING", "FOLLOWING"}
Phases == {"ELECTION", "DISCOVERY", "SYNCHRONIZATION", "BROADCAST"}
Modes == {"NONE", "DIFF", "TRUNC", "SNAP"}
\* Learner.syncWithLeader program counter (Learner.java:546-812):
\*   NONE      not inside a sync (or before the first sync packet)
\*   MODE      SNAP/TRUNC packet read and syncMode set, image not yet loaded
\*   DATA      DIFF selected, or SNAP image loaded / TRUNC applied
\*   SNAPPED   NEWLEADER snapshot of a SNAP/TRUNC image written (739-741)
\*   NEWLEADER NEWLEADER processed: syncMode NONE, processors started (743-760)
\*   UPTODATE  UPTODATE processed and server serving (711-725, 765-767)
LearnerStages == {"NONE", "MODE", "DATA", "SNAPPED", "NEWLEADER", "UPTODATE"}
TransitionNames == {
    "Init", "RestartLoadDatabase", "ReloadDatabase", "GracefulShutdown", "Crash",
    "BeginElectionRound", "CastVote", "FinishElection",
    "SetPeerState", "SetZabState", "PersistAcceptedEpoch", "PersistCurrentEpoch",
    "RecordEpochAck", "FormEpochQuorum", "ChooseSyncMode",
    "LoadSyncSnapshot", "TruncateLog", "ApplySyncCommit", "LearnerNewLeader",
    "CompleteLearnerSync", "FormNewLeaderQuorum", "LeaderPropose",
    "FollowerPendingProposal", "QueueForSync", "FlushTxnLog", "FlushLeakedTxnLog",
    "RecordProposalAck", "CommitProposal", "FollowerCommit",
    "ApplyTxn", "BeginSnapshot", "FinishSnapshot", "FinishSyncSnapshot",
    "LearnerShutdown", "LearnerExit"
}

VARIABLES
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    learnerStage, dbCleared,
    prepared, syncQueued, leakedQueued, pending, durable, recoveryVisible,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished

vars == <<
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    learnerStage, dbCleared,
    prepared, syncQueued, leakedQueued, pending, durable, recoveryVisible,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished
>>

\* Variable groups used in UNCHANGED clauses.
electVars == <<electionRound, votedFor, electionVotes>>
epochVars == <<acceptedEpoch, currentEpoch, epochProposal>>
snapVars == <<snapshotBusy, snapshotImage, snapshotPublished>>
certVars == <<acks, durabilityEvidence, commitWitness, nextTxn>>

Quorum(q) == q \subseteq Server /\ Cardinality(q) * 2 > Cardinality(Server)
Elems(h) == {h[n] : n \in 1..Len(h)}
TxnOrder == [n \in Txn |-> n]
PrefixOf(a, b) == Len(a) <= Len(b) /\ a = SubSeq(b, 1, Len(a))
AppendOnce(h, t) == IF t \in Elems(h) THEN h ELSE Append(h, t)
MaxNat(a, b) == IF a >= b THEN a ELSE b
MinNat(a, b) == IF a <= b THEN a ELSE b
LastOr0(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)]
After(h, x) == SelectSeq(h, LAMBDA t : t > x)
UpTo(h, x) == SelectSeq(h, LAMBDA t : t <= x)
\* Append the records of q not already present in d, in q order.
AppendAll(d, q) == d \o SelectSeq(q, LAMBDA t : t \notin Elems(d))
\* Longest common prefix of two histories.
LCP(a, b) ==
    LET n == CHOOSE k \in 0..MinNat(Len(a), Len(b)) :
                 /\ SubSeq(a, 1, k) = SubSeq(b, 1, k)
                 /\ \A m \in (k + 1)..MinNat(Len(a), Len(b)) :
                        SubSeq(a, 1, m) /= SubSeq(b, 1, m)
    IN SubSeq(a, 1, n)
OrderedFragment(h) ==
    \A a, b \in 1..Len(h) : a < b => h[a] < h[b]
\* Replay order of a log: a record never follows a later-zxid record
\* (adjacent re-appends of the same zxid replay to the same state).
ReplayOrdered(h) ==
    \A a, b \in 1..Len(h) : a < b => h[a] <= h[b]
\* In-memory history after replaying a WAL: each txn applied (re-applying a
\* duplicate record is a no-op on the history), DataTree.lastProcessedZxid
\* is the maximum (DataTree.processTxn).  Sorted distinct records.
ReplayHistory(h) ==
    LET S == Elems(h)
    IN [i \in 1..Cardinality(S) |-> CHOOSE x \in S : Cardinality({y \in S : y < x}) = i - 1]
\* Records still queued in leaked learner log processors of s.
LeakedElems(s) == UNION {Elems(q) : q \in Elems(leakedQueued[s])}
RemoveAt(sq, i) == SubSeq(sq, 1, i - 1) \o SubSeq(sq, i + 1, Len(sq))
\* Next leader record streamed after the follower's last zxid: the leader
\* queues records with zxid greater than the peer's position
\* (LearnerHandler.java:946-1036; Leader.java:1289-1322).
NextFrom(f, l) ==
    LET pos == LastOr0(prepared[f])
        rest == After(prepared[l], pos)
    IN IF (pos = 0 \/ pos \in Elems(prepared[l])) /\ rest /= <<>> THEN Head(rest) ELSE 0
\* Leader's committed log as seen by syncFollower: its applied records.
InCommittedLog(z, l) == z = 0 \/ z \in Elems(applied[l])
\* TRUNC target: maxCommittedLog when the peer is ahead, otherwise the last
\* committed record before the peer's zxid (LearnerHandler.java:852-857,
\* 1000-1006).
TruncTarget(f, l) ==
    LET below == {t \in Elems(applied[l]) : t < LastOr0(prepared[f])}
    IN IF below = {} THEN 0 ELSE CHOOSE t \in below : \A u \in below : u <= t
ElectionUpToDate(c) ==
    \A v \in Server :
        running[v] =>
            \/ currentEpoch[c] > currentEpoch[v]
            \/ currentEpoch[c] = currentEpoch[v]
               /\ Len(durable[c]) >= Len(durable[v])

\* LearnerHandler.syncFollower decision (LearnerHandler.java:775-932,
\* 946-1036) projected on the follower's advertised in-memory history.
\*  - SNAP: txn-log gap (893-905), cross-epoch TRUNC refusal (997-999), the
\*    unhandled fallback (926-930), or forceSnapSync (841-843); never when the
\*    peer is ahead of the leader's committed log, which takes TRUNC first
\*    (852-857).  (forceSnapSync with a peer ahead is a test-only knob and is
\*    excluded.)
\*  - DIFF: the follower's last zxid is in the leader's committed log
\*    (records the leader has applied: ZKDatabase.addCommittedProposal at
\*    apply, ZooKeeperServer.java:1800) (844-851, 860-865, 970-990).  Only
\*    the zxid is compared, not the follower's history.
\*  - TRUNC: the follower's last zxid is not in that log (ahead of
\*    maxCommittedLog or diverged; 852-857, 1000-1006).
SyncModeAllowed(f, l, m) ==
    \/ m = "SNAP" /\ LastOr0(prepared[f]) <= LastOr0(applied[l])
    \/ m = "DIFF" /\ InCommittedLog(LastOr0(prepared[f]), l)
    \/ m = "TRUNC" /\ ~InCommittedLog(LastOr0(prepared[f]), l)

\* Learner state predicates used by the changed shutdown path.
\* ZooKeeperServer.canShutdown() is true only after startServing()
\* (ZooKeeperServer.java:784-786; Learner.java:767).
ZkServing(f) == learnerStage[f] = "UPTODATE"
\* Request processors exist after startupWithoutServing() (Learner.java:751;
\* FollowerZooKeeperServer.java:70-78).
ProcessorsStarted(f) == learnerStage[f] \in {"NEWLEADER", "UPTODATE"}

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
    /\ learnerStage = [s \in Server |-> "NONE"]
    /\ dbCleared = [s \in Server |-> FALSE]
    /\ prepared = [s \in Server |-> <<>>]
    /\ syncQueued = [s \in Server |-> <<>>]
    /\ leakedQueued = [s \in Server |-> <<>>]
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
    /\ learnerStage = [s \in Server |-> "NONE"]
    /\ dbCleared = [s \in Server |-> FALSE]
    /\ prepared = [s \in Server |-> <<>>]
    /\ syncQueued = [s \in Server |-> <<>>]
    /\ leakedQueued = [s \in Server |-> <<>>]
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

(***************************************************************************)
(* Process start / restart: QuorumPeer.start -> loadDataBase                *)
(* (QuorumPeer.java:1101-1150; ZKDatabase.java:284-298).  A new QuorumPeer *)
(* starts with syncMode NONE (QuorumPeer.java:876-886).                    *)
(***************************************************************************)
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
    /\ prepared' = [prepared EXCEPT ![s] = ReplayHistory(durable[s])]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = <<>>]
    /\ leakedQueued' = [leakedQueued EXCEPT ![s] = <<>>]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ syncComplete' = [syncComplete EXCEPT ![s] = FALSE]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![s] = FALSE]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "NONE"]
    /\ dbCleared' = [dbCleared EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<electVars, epochAcks,
                    newLeaderAcks, durable, committed, applied, globalCommitted,
                    certVars, snapVars>>

(***************************************************************************)
(* UPDATE: reload of a cleared database.  QuorumPeer.getLastLoggedZxid()   *)
(* calls loadDataBase() when !zkDb.isInitialized() (QuorumPeer.java:1257-  *)
(* 1262), e.g. at the next FastLeaderElection.lookForLeader after a        *)
(* SNAP-mode learner exit cleared the database.  Epoch files are re-read   *)
(* but unchanged; role, phase and syncMode are not reset.                  *)
(* UPDATE-MAP                                                               *)
(*   code: ZooKeeperServer.java:803-810, QuorumPeer.java:1257-1262          *)
(*   update: Update!AffectedActions (MCReloadDatabase)                      *)
(***************************************************************************)
ReloadDatabase(s) ==
    /\ s \in Server /\ running[s] /\ dbCleared[s]
    /\ prepared' = [prepared EXCEPT ![s] = ReplayHistory(durable[s])]
    /\ recoveryVisible' = [recoveryVisible EXCEPT ![s] = durable[s]]
    /\ dbCleared' = [dbCleared EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, syncQueued, leakedQueued,
                    pending, durable, committed, applied, globalCommitted,
                    certVars, snapVars>>

\* QuorumPeer.shutdown (QuorumPeer.java:1538-1570).  Queued, un-ACKed writes
\* are not modeled as drained (they may be lost; restart reloads durable).
GracefulShutdown(s) ==
    /\ s \in Server /\ running[s]
    /\ running' = [running EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<role, phase, syncMode, leaderOf, epochVars, electVars,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued, leakedQueued,
                    pending, durable, recoveryVisible, committed, applied,
                    globalCommitted, certVars, snapVars>>

\* Abrupt process crash: volatile state (including leaked threads) is lost.
Crash(s) ==
    /\ s \in Server /\ running[s]
    /\ running' = [running EXCEPT ![s] = FALSE]
    /\ phase' = [phase EXCEPT ![s] = "ELECTION"]
    /\ role' = [role EXCEPT ![s] = "LOOKING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = NoServer]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = <<>>]
    /\ leakedQueued' = [leakedQueued EXCEPT ![s] = <<>>]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncComplete' = [syncComplete EXCEPT ![s] = FALSE]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![s] = FALSE]
    /\ learnerStage' = [learnerStage EXCEPT ![s] = "NONE"]
    /\ dbCleared' = [dbCleared EXCEPT ![s] = FALSE]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<epochVars, electVars, epochAcks, newLeaderAcks, prepared,
                    durable, recoveryVisible, committed, applied,
                    globalCommitted, certVars, snapshotImage, snapshotPublished>>

\* New election round after every live peer is LOOKING.  syncMode is NOT
\* reset: it is written only at Learner.java:563,566,589,750 (repair of the
\* prior model, which reset it here).
BeginElectionRound(c) ==
    /\ c \in Server /\ running[c]
    /\ \A s \in Server : running[s] => role[s] = "LOOKING"
    /\ electionRound' = electionRound + 1
    /\ votedFor' = [s \in Server |-> NoServer]
    /\ electionVotes' = [s \in Server |-> {}]
    /\ epochAcks' = [s \in Server |-> {}]
    /\ newLeaderAcks' = [s \in Server |-> {}]
    /\ newLeaderReady' = [s \in Server |-> IF running[s] THEN FALSE ELSE newLeaderReady[s]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapVars>>

\* FastLeaderElection.lookForLeader starts from getLastLoggedZxid(), which
\* reloads a cleared database first (QuorumPeer.java:1257-1262).
CastVote(v, c) ==
    /\ v \in Server /\ c \in Server /\ running[v] /\ running[c]
    /\ ~dbCleared[v]
    /\ phase[v] = "ELECTION" /\ votedFor[v] = NoServer
    /\ votedFor' = [votedFor EXCEPT ![v] = c]
    /\ electionVotes' = [electionVotes EXCEPT ![c] = @ \cup {v}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electionRound, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapVars>>

\* Election completion; a LOOKING peer may also join an established leader
\* whose round still holds a quorum (FastLeaderElection.java:1054-1088).
FinishElection(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s]
    /\ role[s] = "LOOKING" /\ ~dbCleared[s]
    /\ Quorum(electionVotes[c]) /\ ElectionUpToDate(c)
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electVars,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, certVars, snapVars>>

ObserveElectionResult(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s]
    /\ ~dbCleared[s]
    /\ ElectionUpToDate(c)
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ electionVotes' = [electionVotes EXCEPT ![c] = Server]
    /\ votedFor' = [votedFor EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electionRound,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, certVars, snapVars>>

ObserveSetZabState(s, p) ==
    /\ s \in Server /\ p \in Phases
    /\ phase' = [phase EXCEPT ![s] = p]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electVars,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, certVars, snapVars>>

ObserveSetPeerState(s, r) ==
    /\ s \in Server /\ r \in Roles
    /\ role' = [role EXCEPT ![s] = r]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = IF r = "LOOKING" THEN NoServer ELSE @]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electVars,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, certVars, snapVars>>

\* QuorumPeer.setPeerState(LOOKING) clears the leader and sets ELECTION inside
\* the same synchronized method (QuorumPeer.java:853-861); the trace observes
\* it as two consecutive events, replayed as one step.
ObserveSetPeerStateLooking(s) ==
    /\ s \in Server
    /\ role' = [role EXCEPT ![s] = "LOOKING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = NoServer]
    /\ phase' = [phase EXCEPT ![s] = "ELECTION"]
    /\ UNCHANGED <<running, syncMode, epochVars, electVars,
                    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, certVars, snapVars>>

PersistAcceptedEpoch(s, e) ==
    /\ s \in Server /\ running[s] /\ e \in 0..MaxEpoch
    /\ phase[s] = "DISCOVERY"
    /\ e >= acceptedEpoch[s]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = e]
    /\ epochProposal' = [epochProposal EXCEPT ![s] = e]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, currentEpoch,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapVars>>

PersistCurrentEpoch(s, e) ==
    /\ s \in Server /\ running[s] /\ e \in 0..MaxEpoch
    /\ e >= currentEpoch[s] /\ e <= acceptedEpoch[s]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = e]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, acceptedEpoch,
                    epochProposal, electVars, epochAcks, newLeaderAcks,
                    newLeaderReady, syncComplete, learnerStage, dbCleared,
                    prepared, syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapVars>>

RecordEpochAck(l, f) ==
    /\ l \in Server /\ f \in Server /\ running[l] /\ running[f]
    /\ role[l] = "LEADING" /\ phase[l] = "DISCOVERY"
    /\ epochProposal[l] > currentEpoch[l]
    /\ acceptedEpoch[l] = epochProposal[l]
    /\ phase[f] = "DISCOVERY"
    /\ acceptedEpoch[f] = epochProposal[l]
    /\ epochAcks' = [epochAcks EXCEPT ![l] = @ \cup {f}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, newLeaderAcks, newLeaderReady, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, certVars, snapVars>>

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
                    epochProposal, electVars, epochAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapVars>>

(***************************************************************************)
(* Sync start: the first sync packet sets syncMode (Learner.java:557-602). *)
(* The leader's choice is SyncModeAllowed.  DIFF needs no image work.      *)
(***************************************************************************)
ChooseSyncMode(f, m) ==
    /\ f \in Server /\ m \in {"DIFF", "TRUNC", "SNAP"} /\ running[f]
    /\ role[f] = "FOLLOWING" /\ leaderOf[f] \in Server
    /\ running[leaderOf[f]] /\ role[leaderOf[f]] = "LEADING"
    /\ learnerStage[f] = "NONE" /\ ~dbCleared[f]
    /\ SyncModeAllowed(f, leaderOf[f], m)
    /\ syncMode' = [syncMode EXCEPT ![f] = m]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = IF m = "DIFF" THEN "DATA" ELSE "MODE"]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = FALSE]
    \* DIFF keeps the in-memory DataTree; the leader confirmed it lies in its
    \* committed log, so it is the client-visible base after UPTODATE.
    /\ committed' = [committed EXCEPT ![f] = IF m = "DIFF" THEN prepared[f] ELSE @]
    /\ applied' = [applied EXCEPT ![f] = IF m = "DIFF" THEN prepared[f] ELSE @]
    /\ UNCHANGED <<running, role, phase, leaderOf, epochVars, electVars,
                    epochAcks, newLeaderAcks, newLeaderReady,
                    dbCleared, prepared, syncQueued, leakedQueued, pending,
                    durable, recoveryVisible, globalCommitted, certVars, snapVars>>

(***************************************************************************)
(* SNAP: zkDb.deserializeSnapshot replaces the in-memory database with the *)
(* leader's DataTree and sets lastProcessedZxid; nothing is written to disk *)
(* (Learner.java:565-586; ZKDatabase.java:618-622).  The leader's DataTree  *)
(* is its applied history (LearnerHandler.java:549-648).                   *)
(* UPDATE-MAP                                                               *)
(*   code: Learner.java:565-586 (producer of the state Learner.shutdown     *)
(*         now clears)                                                      *)
(*   update: Update!InteractionActions (MCLoadSyncSnapshot)                 *)
(***************************************************************************)
LoadSyncSnapshot(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] \in Server
    /\ learnerStage[f] = "MODE" /\ syncMode[f] = "SNAP"
    /\ LET l == leaderOf[f]
           image == applied[l]
       IN /\ PrefixOf(image, prepared[l])
          /\ prepared' = [prepared EXCEPT ![f] = image]
          /\ committed' = [committed EXCEPT ![f] = image]
          /\ applied' = [applied EXCEPT ![f] = image]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "DATA"]
    /\ dbCleared' = [dbCleared EXCEPT ![f] = FALSE]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, globalCommitted, certVars, snapVars>>

(***************************************************************************)
(* TRUNC: zkDb.truncateLog clears memory, cuts the WAL after zxid, and      *)
(* reloads from disk (Learner.java:587-598; ZKDatabase.java:599-610).  The  *)
(* target is the last record shared with the leader's committed log.       *)
(***************************************************************************)
TruncateLog(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] \in Server
    /\ learnerStage[f] = "MODE" /\ syncMode[f] = "TRUNC"
    \* FileTxnSnapLog.truncateLog cuts only the WAL; the reload restores the
    \* newest snapshot, which may be newer than the target
    \* (FileTxnSnapLog.java:502-523).  lastProcessedZxid is then forced to the
    \* target (Learner.java:597), so the leader streams records after it.
    /\ LET l == leaderOf[f]
           target == TruncTarget(f, l)
           cut == UpTo(durable[f], target)
           snap == snapshotPublished[f]
           reloaded == IF LastOr0(snap) > target THEN snap \o After(cut, LastOr0(snap)) ELSE cut
       IN /\ durable' = [durable EXCEPT ![f] = reloaded]
          /\ prepared' = [prepared EXCEPT ![f] = ReplayHistory(cut)]
          /\ recoveryVisible' = [recoveryVisible EXCEPT ![f] = reloaded]
          /\ committed' = [committed EXCEPT ![f] = ReplayHistory(reloaded)]
          /\ applied' = [applied EXCEPT ![f] = ReplayHistory(reloaded)]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "DATA"]
    /\ dbCleared' = [dbCleared EXCEPT ![f] = FALSE]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, syncQueued, leakedQueued, pending,
                    globalCommitted, certVars, snapVars>>

(***************************************************************************)
(* Before NEWLEADER, SNAP and TRUNC keep writeToTxnLog=false, so a COMMIT  *)
(* applies the queued PROPOSAL directly to the in-memory DataTree and is    *)
(* not logged (Learner.java:553-555, 611-614, 643-669).  The leader sends   *)
(* PROPOSAL+COMMIT for committed records beyond the sync point             *)
(* (LearnerHandler.java:1020-1030; Leader.java:1292-1302).                 *)
(***************************************************************************)
ApplySyncCommit(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] \in Server
    /\ learnerStage[f] = "DATA" /\ syncMode[f] \in {"SNAP", "TRUNC"}
    /\ ~snapshotBusy[f]
    /\ t = NextFrom(f, leaderOf[f])
    /\ t \in Elems(committed[leaderOf[f]])
    /\ prepared' = [prepared EXCEPT ![f] = Append(@, t)]
    /\ committed' = [committed EXCEPT ![f] = AppendOnce(@, t)]
    /\ applied' = [applied EXCEPT ![f] = AppendOnce(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    globalCommitted, certVars, snapVars>>

(***************************************************************************)
(* NEWLEADER snapshot of a SNAP/TRUNC image: takeSnapshot(syncSnapshot)     *)
(* (Learner.java:739-741; ZooKeeperServer.java:519-535).  Restore picks the *)
(* newest snapshot and replays only later WAL records                       *)
(* (FileTxnSnapLog.java:243-368).  BeginSnapshot captures the image.        *)
(***************************************************************************)
FinishSyncSnapshot(f) ==
    /\ f \in Server /\ snapshotBusy[f]
    /\ learnerStage[f] = "DATA" /\ syncMode[f] \in {"SNAP", "TRUNC"}
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![f] = FALSE]
    /\ snapshotPublished' = [snapshotPublished EXCEPT ![f] = snapshotImage[f]]
    /\ durable' = [durable EXCEPT ![f] =
          snapshotImage[f] \o After(@, LastOr0(snapshotImage[f]))]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "SNAPPED"]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, recoveryVisible, committed,
                    applied, globalCommitted, certVars, snapshotImage>>

(***************************************************************************)
(* NEWLEADER after the snapshot and setCurrentEpoch: setSyncMode(NONE),     *)
(* startupWithoutServing, log buffered proposals, ACK NEWLEADER             *)
(* (Learner.java:743-760).  The ACK is counted by the leader.               *)
(***************************************************************************)
LearnerNewLeader(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] \in Server
    /\ \/ learnerStage[f] = "DATA" /\ syncMode[f] = "DIFF"
       \/ learnerStage[f] = "SNAPPED"
    /\ currentEpoch[f] = acceptedEpoch[f]
    /\ syncMode' = [syncMode EXCEPT ![f] = "NONE"]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "NEWLEADER"]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![leaderOf[f]] = @ \cup {f}]
    /\ UNCHANGED <<running, role, phase, leaderOf, epochVars, electVars,
                    epochAcks, newLeaderReady, syncComplete, dbCleared,
                    prepared, syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapVars>>

\* UPTODATE: syncWithLeader returns after the leader's NEWLEADER quorum
\* (LearnerHandler.java:620-648; Learner.java:711-725, 765-785;
\* Follower.java:109-111).  The image work happened in the steps above.
CompleteLearnerSync(f, l) ==
    /\ f \in Server /\ l \in Server
    /\ running[f] /\ running[l] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] = l /\ role[l] = "LEADING"
    /\ learnerStage[f] = "NEWLEADER" /\ newLeaderReady[l]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = TRUE]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "UPTODATE"]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    dbCleared, prepared, syncQueued, leakedQueued, pending,
                    durable, recoveryVisible, committed, applied,
                    globalCommitted, certVars, snapVars>>

\* NEWLEADER quorum commits the new leader's whole history (Leader.lead ->
\* waitForNewLeaderAck, Leader.java:657-688; followers ACK NEWLEADER after
\* syncing that history).  Repair of the prior model, which could only commit
\* old-epoch records through per-proposal ACKs.
NewLeaderCommit(l) ==
    LET newc == SelectSeq(prepared[l], LAMBDA t : t \notin Elems(globalCommitted))
    IN /\ globalCommitted' = globalCommitted \o newc
       /\ committed' = [committed EXCEPT ![l] = prepared[l]]
       /\ commitWitness' = [t \in Txn |-> IF t \in Elems(newc) THEN newLeaderAcks'[l] ELSE commitWitness[t]]

FormNewLeaderQuorum(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ Quorum(newLeaderAcks[l])
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![l] = TRUE]
    /\ newLeaderAcks' = newLeaderAcks
    /\ NewLeaderCommit(l)
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, syncComplete,
                    learnerStage, dbCleared, prepared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    applied, acks, durabilityEvidence, nextTxn, snapVars>>

ObserveNewLeaderQuorum(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = Server]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![l] = TRUE]
    /\ NewLeaderCommit(l)
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, syncComplete, learnerStage,
                    dbCleared, prepared, syncQueued, leakedQueued, pending,
                    durable, recoveryVisible, applied, acks,
                    durabilityEvidence, nextTxn, snapVars>>

LeaderPropose(l, t) ==
    /\ l \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ phase[l] = "BROADCAST"
    /\ newLeaderReady[l] /\ t = nextTxn
    /\ prepared' = [prepared EXCEPT ![l] = Append(@, t)]
    /\ acks' = [acks EXCEPT ![t] = {}]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = {}]
    /\ commitWitness' = [commitWitness EXCEPT ![t] = {}]
    /\ nextTxn' = nextTxn + 1
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, syncQueued,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, snapVars>>

\* ProposalRequestProcessor.processRequest: propose then queue to the local
\* SyncRequestProcessor on the same thread (ProposalRequestProcessor.java:
\* 68-90).  Atomic MC form of LeaderPropose + QueueForSync.
LeaderProposeAndLog(l, t) ==
    /\ l \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ phase[l] = "BROADCAST"
    /\ newLeaderReady[l] /\ t = nextTxn
    /\ prepared' = [prepared EXCEPT ![l] = Append(@, t)]
    /\ syncQueued' = [syncQueued EXCEPT ![l] = Append(@, t)]
    /\ acks' = [acks EXCEPT ![t] = {}]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = {}]
    /\ commitWitness' = [commitWitness EXCEPT ![t] = {}]
    /\ nextTxn' = nextTxn + 1
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, leakedQueued,
                    pending, durable, recoveryVisible, committed, applied,
                    globalCommitted, snapVars>>

\* FollowerZooKeeperServer.logRequest: pendingTxns.add (FollowerZooKeeperServer
\* .java:82-89), reached from NEWLEADER/UPTODATE buffers or broadcast
\* PROPOSALs (Learner.java:752-758, 778-785; Follower.java:160-203).
FollowerPendingProposal(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING"
    /\ phase[f] \in {"SYNCHRONIZATION", "BROADCAST"}
    /\ learnerStage[f] \in {"NEWLEADER", "UPTODATE"}
    /\ leaderOf[f] \in Server /\ t = NextFrom(f, leaderOf[f])
    /\ pending' = [pending EXCEPT ![f] = Append(@, t)]
    /\ prepared' = [prepared EXCEPT ![f] = Append(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, syncQueued,
                    leakedQueued, durable, recoveryVisible, committed,
                    applied, globalCommitted, certVars, snapVars>>

\* Atomic MC form: logRequest adds to pendingTxns and calls
\* syncProcessor.processRequest on the learner thread (FollowerZooKeeperServer
\* .java:82-89).
FollowerLogRequest(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING"
    /\ phase[f] \in {"SYNCHRONIZATION", "BROADCAST"}
    /\ learnerStage[f] \in {"NEWLEADER", "UPTODATE"}
    /\ leaderOf[f] \in Server /\ t = NextFrom(f, leaderOf[f])
    /\ pending' = [pending EXCEPT ![f] = Append(@, t)]
    /\ prepared' = [prepared EXCEPT ![f] = Append(@, t)]
    /\ syncQueued' = [syncQueued EXCEPT ![f] = Append(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, leakedQueued,
                    durable, recoveryVisible, committed, applied,
                    globalCommitted, certVars, snapVars>>

\* SyncRequestProcessor.processRequest (SyncRequestProcessor.java:272-279).
QueueForSync(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ t \in Elems(prepared[s]) /\ t \notin Elems(syncQueued[s])
    /\ syncQueued' = [syncQueued EXCEPT ![s] = Append(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    leakedQueued, pending, durable, recoveryVisible,
                    committed, applied, globalCommitted, certVars, snapVars>>

(***************************************************************************)
(* SyncRequestProcessor append + commit (fsync) of the queue head, then the *)
(* ACK processor (SyncRequestProcessor.java:156-249).  The WAL accepts any  *)
(* zxid; FileTxnLog only warns on a non-increasing zxid, and replay applies *)
(* every later record (FileTxnSnapLog.java:317-368), so no contiguity guard.*)
(***************************************************************************)
FlushTxnLog(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ syncQueued[s] /= <<>> /\ t = Head(syncQueued[s])
    \* The WAL appends even a duplicate zxid; replay re-applies it.
    /\ durable' = [durable EXCEPT ![s] = Append(@, t)]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = Tail(@)]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = @ \cup {s}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    leakedQueued, pending, recoveryVisible, committed,
                    applied, globalCommitted, acks, commitWitness, nextTxn,
                    snapVars>>

(***************************************************************************)
(* UPDATE: a learner SyncRequestProcessor that was not shut down keeps     *)
(* draining its queue into the shared txn log.  Its SendAckRequestProcessor *)
(* writes to the closed learner socket, so no ACK evidence is produced      *)
(* (SendAckRequestProcessor.java; Learner.java:859).                        *)
(* UPDATE-MAP                                                               *)
(*   code: Learner.java:864 (bypasses LearnerZooKeeperServer.java:154-173)  *)
(*   update: Update!InteractionActions (MCFlushLeaked)                      *)
(***************************************************************************)
FlushLeakedTxnLog(s, i, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ i \in 1..Len(leakedQueued[s])
    /\ t = Head(leakedQueued[s][i])
    /\ durable' = [durable EXCEPT ![s] = Append(@, t)]
    /\ leakedQueued' = [leakedQueued EXCEPT ![s] =
          IF Tail(@[i]) = <<>> THEN RemoveAt(@, i) ELSE [@ EXCEPT ![i] = Tail(@)]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, pending, recoveryVisible, committed, applied,
                    globalCommitted, certVars, snapVars>>

RecordProposalAck(l, source, t) ==
    /\ l \in Server /\ source \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ t \in Elems(prepared[l])
    /\ t \notin Elems(globalCommitted)
    /\ source \in durabilityEvidence[t]
    /\ acks' = [acks EXCEPT ![t] = @ \cup {source}]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    durabilityEvidence, commitWitness, nextTxn, snapVars>>

\* Leader.tryToCommit commits in zxid order among the leader's outstanding
\* proposals (Leader.java:890-962): every earlier record of the leader
\* history must already be committed.  (Repair of the prior dense-id guard.)
CommitProposal(l, t) ==
    /\ l \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ phase[l] = "BROADCAST" /\ newLeaderReady[l]
    /\ Quorum(acks[t])
    /\ t \notin Elems(globalCommitted)
    /\ t \in Elems(prepared[l])
    /\ \A k \in 1..Len(prepared[l]) :
          prepared[l][k] < t => prepared[l][k] \in Elems(globalCommitted)
    /\ globalCommitted' = Append(globalCommitted, t)
    /\ committed' = [committed EXCEPT ![l] = AppendOnce(@, t)]
    /\ commitWitness' = [commitWitness EXCEPT ![t] = acks[t]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, applied, acks, durabilityEvidence,
                    nextTxn, snapVars>>

\* FollowerZooKeeperServer.commit: the COMMIT must match the pendingTxns head
\* (FollowerZooKeeperServer.java:97-110).
FollowerCommit(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f]
    /\ role[f] = "FOLLOWING" /\ pending[f] /= <<>>
    /\ t = Head(pending[f])
    /\ t \in Elems(globalCommitted)
    /\ committed' = [committed EXCEPT ![f] = AppendOnce(@, t)]
    /\ pending' = [pending EXCEPT ![f] = Tail(@)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, durable, recoveryVisible,
                    applied, globalCommitted, certVars, snapVars>>

\* FinalRequestProcessor.applyRequest in commit order.
ApplyTxn(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ PrefixOf(applied[s], committed[s]) /\ Len(applied[s]) < Len(committed[s])
    /\ t = committed[s][Len(applied[s]) + 1]
    /\ t \in Elems(globalCommitted)
    /\ applied' = [applied EXCEPT ![s] = Append(@, t)]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, globalCommitted, certVars,
                    snapVars>>

BeginSnapshot(s) ==
    /\ s \in Server /\ running[s] /\ role[s] \in {"LEADING", "FOLLOWING"}
    /\ ~snapshotBusy[s]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = TRUE]
    /\ snapshotImage' = [snapshotImage EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapshotPublished>>

\* Periodic / election snapshot publication.  As in the prior suite, its
\* effect on the recoverable history is not modeled (abstraction recorded
\* in analysis-report.md); the NEWLEADER sync snapshot is FinishSyncSnapshot.
FinishSnapshot(s) ==
    /\ s \in Server /\ snapshotBusy[s]
    /\ ~(learnerStage[s] = "DATA" /\ syncMode[s] \in {"SNAP", "TRUNC"})
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = FALSE]
    /\ snapshotPublished' = [snapshotPublished EXCEPT ![s] = snapshotImage[s]]
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, learnerStage, dbCleared, prepared,
                    syncQueued, leakedQueued, pending, durable,
                    recoveryVisible, committed, applied, globalCommitted,
                    certVars, snapshotImage>>

(***************************************************************************)
(* UPDATE: Learner.shutdown (Learner.java:850-866) when the follower leaves *)
(* FOLLOWING (QuorumPeer.java:1468-1480) or the peer shuts down.            *)
(*                                                                         *)
(* UPDATED: zk.shutdown(syncMode == SNAP) dispatches to                     *)
(*   ZooKeeperServer.shutdown(boolean) (ZooKeeperServer.java:803-858):      *)
(*   - not serving and SNAP: zkDb.clear()            (804-809)              *)
(*   - serving: fast-forward from the WAL            (841-852)              *)
(*   - LearnerZooKeeperServer.shutdown() is NOT invoked, so the follower    *)
(*     SyncRequestProcessor is never shut down; its queue is leaked.        *)
(* PRIOR: zk.shutdown() -> LearnerZooKeeperServer.shutdown()               *)
(*   (LearnerZooKeeperServer.java:154-173): early return when not serving; *)
(*   otherwise ZooKeeperServer.shutdown(false) (fast-forward) followed by   *)
(*   syncProcessor.shutdown(), which drains and flushes the queue before    *)
(*   returning (SyncRequestProcessor.java:251-270).                         *)
(* Fast-forward replays logged records into the DataTree, so the in-memory  *)
(* baseline keeps records that are applied or already durable, and loses   *)
(* queued-but-unflushed records (ZKDatabase.java:300-304).                 *)
(* UPDATE-MAP                                                               *)
(*   code: Learner.java:860-865; ZooKeeperServer.java:803-810              *)
(*   update: Update!AffectedActions (MCLearnerExit), Update properties      *)
(***************************************************************************)
LearnerShutdownCore(f) ==
    LET full == LearnerShutdownSemantics = "UPDATED" /\ syncMode[f] = "SNAP"
        serving == ZkServing(f)
        drain == LearnerShutdownSemantics = "PRIOR" /\ serving
        leak == ProcessorsStarted(f) /\ ~drain
        fastForwarded ==
            SelectSeq(prepared[f], LAMBDA t : t \in Elems(applied[f]) \cup Elems(durable[f]))
    IN
    /\ dbCleared' = [dbCleared EXCEPT ![f] = full \/ @]
    /\ prepared' = [prepared EXCEPT ![f] =
          IF full THEN <<>> ELSE IF serving THEN fastForwarded ELSE @]
    /\ durable' = [durable EXCEPT ![f] = IF drain THEN @ \o syncQueued[f] ELSE @]
    /\ leakedQueued' = [leakedQueued EXCEPT ![f] =
          IF leak /\ syncQueued[f] /= <<>> THEN Append(@, syncQueued[f]) ELSE @]
    /\ syncQueued' = [syncQueued EXCEPT ![f] = <<>>]
    /\ pending' = [pending EXCEPT ![f] = <<>>]
    /\ learnerStage' = [learnerStage EXCEPT ![f] = "NONE"]
    \* zkDb.clear() discards the DataTree (ZKDatabase.java:171-188); only the
    \* records the reload restores from disk remain part of the commit/apply
    \* histories (validated: traces/upd-snap-exit-diff-v3.ndjson event 201).
    /\ committed' = [committed EXCEPT ![f] =
          IF full THEN SelectSeq(@, LAMBDA t : t \in Elems(durable[f])) ELSE @]
    /\ applied' = [applied EXCEPT ![f] =
          IF full THEN SelectSeq(@, LAMBDA t : t \in Elems(durable[f])) ELSE @]

\* Trace form: the probe fires inside Learner.shutdown, before
\* QuorumPeer.updateServerState() sets LOOKING (QuorumPeer.java:1476-1478),
\* and also on QuorumPeer.shutdown (QuorumPeer.java:1544-1546).
\* The duplicate call from QuorumPeer.shutdown can race the peer thread's own
\* follower.shutdown() + updateServerState() and arrive after LOOKING
\* (QuorumPeer.java:1475-1479, 1544-1546); its effects are idempotent.
LearnerShutdown(f) ==
    /\ f \in Server /\ role[f] \in {"FOLLOWING", "LOOKING"}
    /\ ~(snapshotBusy[f] /\ learnerStage[f] = "DATA")
    /\ LearnerShutdownCore(f)
    /\ UNCHANGED <<running, role, phase, syncMode, leaderOf, epochVars,
                    electVars, epochAcks, newLeaderAcks, newLeaderReady,
                    syncComplete, recoveryVisible, globalCommitted, certVars,
                    snapVars>>

\* MC form: the learner thread runs follower.shutdown() and then
\* updateServerState() -> setPeerState(LOOKING) without other learner work in
\* between (QuorumPeer.java:1475-1479).
LearnerExit(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ ~(snapshotBusy[f] /\ learnerStage[f] = "DATA")
    /\ LearnerShutdownCore(f)
    /\ role' = [role EXCEPT ![f] = "LOOKING"]
    /\ phase' = [phase EXCEPT ![f] = "ELECTION"]
    /\ leaderOf' = [leaderOf EXCEPT ![f] = NoServer]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = FALSE]
    /\ UNCHANGED <<running, syncMode, epochVars, electVars, epochAcks,
                    newLeaderAcks, newLeaderReady, recoveryVisible,
                    globalCommitted, certVars, snapVars>>

(***************************************************************************)
(* Properties                                                               *)
(***************************************************************************)
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
    /\ learnerStage \in [Server -> LearnerStages]
    /\ dbCleared \in [Server -> BOOLEAN]
    /\ prepared \in [Server -> Seq(Txn)]
    /\ syncQueued \in [Server -> Seq(Txn)]
    /\ leakedQueued \in [Server -> Seq(Seq(Txn))]
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

\* Prior formulation: every history is a dense prefix of the global zxid
\* order.  It assumes no proposal is ever lost.  Kept for evidence; replaced
\* in cfgs by OrderedHistoriesV1 (spec/invariant-evidence.json, E-OH*).
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

\* Revised ordering property: histories are in strictly increasing zxid
\* order (a lost proposal may leave an identifier gap), commit/apply follow
\* the global commit order.  Gaps of committed records are judged by
\* Update!RecoverableHistoryComplete.
OrderedHistoriesV1 ==
    /\ OrderedFragment(globalCommitted)
    /\ \A s \in Server :
        /\ OrderedFragment(prepared[s])
        /\ OrderedFragment(syncQueued[s])
        /\ \A q \in Elems(leakedQueued[s]) : OrderedFragment(q)
        /\ OrderedFragment(pending[s])
        /\ ReplayOrdered(durable[s])
        /\ ReplayOrdered(recoveryVisible[s])
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

\* Revised: a published snapshot holds only committed history in commit
\* order.  A later SNAP image may lag a follower's own earlier sync snapshot
\* (the leader serializes its applied DataTree, Learner.java:565-586,
\* LearnerHandler.java:549-648, while FileSnap keeps older snapshots), so the
\* prior "prefix of the in-memory applied history" form is not
\* implementation-backed (spec/invariant-evidence.json, E-SPV).
SnapshotPublishedValidV1 ==
    \A s \in Server : PrefixOf(snapshotPublished[s], globalCommitted)

\* Prior action property: only a learner-sync completion may retract
\* durable/commit/apply histories.
MonotoneStep ==
    \/ \E f \in Server : ~syncComplete[f] /\ syncComplete'[f]
    \/ /\ \A s \in Server : Len(durable'[s]) >= Len(durable[s])
       /\ \A s \in Server : Len(committed'[s]) >= Len(committed[s])
       /\ \A s \in Server : Len(applied'[s]) >= Len(applied[s])

MonotoneUnlessRecovery == [][MonotoneStep]_vars

\* Revised: the explicit, source-authorized reconciliation steps are now
\* separate actions (snapshot load / log truncation MODE->DATA, NEWLEADER
\* snapshot DATA->SNAPPED).  Every other step is monotone per server.
RecoveryStep(s) ==
    \/ learnerStage[s] \in {"NONE", "MODE"} /\ learnerStage'[s] = "DATA"
    \/ learnerStage[s] = "DATA" /\ learnerStage'[s] = "SNAPPED"
MonotoneStepV1 ==
    \A s \in Server :
        \/ RecoveryStep(s)
        \/ /\ Len(durable'[s]) >= Len(durable[s])
           /\ Len(committed'[s]) >= Len(committed[s])
           /\ Len(applied'[s]) >= Len(applied[s])
MonotoneUnlessRecoveryV1 == [][MonotoneStepV1]_vars

InvariantSet ==
    TypeOK /\ ActiveLeaderUniqueness /\ AcceptedEpochGECurrentEpoch
    /\ OrderedHistoriesV1 /\ CommittedPrefixAgreement
    /\ NormalAckHasDurabilityEvidence /\ ApplyHasCommitCertificate
    /\ SyncEntryJustified /\ SnapshotPublishedValidV1

(***************************************************************************)
(* Canonical source-derived base schedule (base.cfg).  One leader and one  *)
(* follower walk election, DIFF sync, the pipeline, and crash/restart.     *)
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
    \/ /\ role[BaseFollower] = "FOLLOWING"
       /\ phase[BaseFollower] = "DISCOVERY"
       /\ phase[BaseLeader] \in {"SYNCHRONIZATION", "BROADCAST"}
       /\ acceptedEpoch[BaseFollower] = acceptedEpoch[BaseLeader]
       /\ ObserveSetZabState(BaseFollower, "SYNCHRONIZATION")
    \/ /\ phase[BaseFollower] = "SYNCHRONIZATION"
       /\ \E m \in {"DIFF", "TRUNC", "SNAP"} : ChooseSyncMode(BaseFollower, m)
    \/ LoadSyncSnapshot(BaseFollower)
    \/ TruncateLog(BaseFollower)
    \/ \E t \in Txn : ApplySyncCommit(BaseFollower, t)
    \/ /\ learnerStage[BaseFollower] = "DATA"
       /\ syncMode[BaseFollower] \in {"SNAP", "TRUNC"}
       /\ BeginSnapshot(BaseFollower)
    \/ FinishSyncSnapshot(BaseFollower)
    \/ /\ learnerStage[BaseFollower] \in {"DATA", "SNAPPED"}
       /\ acceptedEpoch[BaseFollower] > currentEpoch[BaseFollower]
       /\ PersistCurrentEpoch(BaseFollower, acceptedEpoch[BaseFollower])
    \/ LearnerNewLeader(BaseFollower)
    \/ /\ ~newLeaderReady[BaseLeader]
       /\ FormNewLeaderQuorum(BaseLeader)
    \/ CompleteLearnerSync(BaseFollower, BaseLeader)
    \/ /\ role[BaseLeader] = "LEADING"
       /\ phase[BaseLeader] = "SYNCHRONIZATION"
       /\ newLeaderReady[BaseLeader]
       /\ ObserveSetZabState(BaseLeader, "BROADCAST")
    \/ /\ role[BaseFollower] = "FOLLOWING"
       /\ phase[BaseFollower] = "SYNCHRONIZATION"
       /\ syncComplete[BaseFollower]
       /\ ObserveSetZabState(BaseFollower, "BROADCAST")
    \/ /\ nextTxn \in Txn
       /\ LeaderProposeAndLog(BaseLeader, nextTxn)
    \/ \E t \in Txn : FollowerLogRequest(BaseFollower, t)
    \/ \E t \in Txn : FlushTxnLog(BaseLeader, t)
    \/ \E t \in Txn : FlushTxnLog(BaseFollower, t)
    \/ \E i \in 1..2 : \E t \in Txn : FlushLeakedTxnLog(BaseFollower, i, t)
    \/ \E t \in Txn : RecordProposalAck(BaseLeader, BaseLeader, t)
    \/ \E t \in Txn : RecordProposalAck(BaseLeader, BaseFollower, t)
    \/ \E t \in Txn : CommitProposal(BaseLeader, t)
    \/ \E t \in Txn : FollowerCommit(BaseFollower, t)
    \/ \E t \in Txn : ApplyTxn(BaseLeader, t)
    \/ \E t \in Txn : ApplyTxn(BaseFollower, t)
    \/ /\ phase[BaseFollower] = "BROADCAST"
       /\ nextTxn = MaxTxn + 1
       /\ Crash(BaseFollower)
    \/ /\ ~running[BaseFollower]
       /\ RestartLoadDatabase(BaseFollower,
                              acceptedEpoch[BaseFollower],
                              currentEpoch[BaseFollower])
    \/ /\ learnerStage[BaseFollower] \in {"DATA", "UPTODATE"}
       /\ LearnerExit(BaseFollower)
    \/ ReloadDatabase(BaseFollower)

BaseSymmetry == Permutations(Server)

=============================================================================
