------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

(***************************************************************************)
(* Code-faithful finite abstraction of the UPDATED ZooKeeper Zab path       *)
(* (neutral synthetic commit "update").                                     *)
(*                                                                         *)
(* Transaction identifiers are global and allocated in proposal order, so  *)
(* id order is zxid order.  Histories are strictly increasing sequences of *)
(* ids; a history may skip an id (divergent uncommitted proposals of an    *)
(* earlier epoch), which is what TRUNC repairs.                            *)
(*                                                                         *)
(* Revision vs. the V0 prior suite (see ../modeling-brief.md section 8):    *)
(*  - memDb/memInit model ZKDatabase's data tree and `initialized` flag,    *)
(*    separately from the durable snapshot+txn-log history.  The value a   *)
(*    server reports to election and to the leader (getLastLoggedZxid)    *)
(*    is read from memDb when initialized, else reloaded from durable.     *)
(*  - Learner.syncWithLeader is split at its real packet/persistence       *)
(*    boundaries; Learner.shutdown is an explicit action that carries the  *)
(*    updated fullyShutDown = (syncMode == SNAP) semantics.                *)
(*  - Late joiners can sync with an established leader.                    *)
(***************************************************************************)

CONSTANTS Server, MaxEpoch, MaxTxn, NoServer,
          \* TRUE = updated source (Learner.java:862-864, ZooKeeperServer.java:804-807).
          \* FALSE = exact-old control (Learner called zk.shutdown() == shutdown(false)).
          \* Only the differential non-vacuity control cfg sets FALSE.
          UpdateFullShutdownOnSnap

Txn == 1..MaxTxn
TxnOrNone == 0..MaxTxn
Roles == {"LOOKING", "LEADING", "FOLLOWING"}
Phases == {"ELECTION", "DISCOVERY", "SYNCHRONIZATION", "BROADCAST"}
Modes == {"NONE", "DIFF", "TRUNC", "SNAP"}
\* Learner progress inside Learner.syncWithLeader (Learner.java:546-812):
\*  IDLE     not inside syncWithLeader (or sync finished)
\*  MODE     first packet read and setSyncMode(SNAP|TRUNC) done, data not yet replaced
\*  DATA     first packet fully handled; reading PROPOSAL/COMMIT before NEWLEADER
\*  SNAPPED  NEWLEADER: takeSnapshot(syncSnapshot) returned (SNAP/TRUNC only)
\*  EPOCH    NEWLEADER: setCurrentEpoch(newEpoch) returned
\*  NEWLEADER NEWLEADER: setSyncMode(NONE) done; logging packetsNotCommitted
\*  ACKED    NEWLEADER ACK written; reading packets until UPTODATE
\*  UPTODATE UPTODATE handled, startServing done; post-loop logRequest/commit
\*  EXITED   Learner.shutdown returned, role not yet LOOKING
Stages == {"IDLE", "MODE", "DATA", "SNAPPED", "EPOCH", "NEWLEADER", "ACKED",
           "UPTODATE", "EXITED"}

VARIABLES
    running, role, phase, syncMode, leaderOf,
    acceptedEpoch, currentEpoch, epochProposal,
    electionRound, votedFor, electionVotes,
    epochAcks, newLeaderAcks, newLeaderReady, syncComplete,
    prepared, logPos, syncQueued, pending, durable,
    memDb, memInit,
    syncStage, syncBuf, syncCommits, syncPos, syncCut,
    committed, applied, globalCommitted,
    acks, durabilityEvidence, commitWitness, nextTxn,
    snapshotBusy, snapshotImage, snapshotPublished,
    \* id frontier of the newest durable snapshot (FileSnap); FileTxnSnapLog
    \* .truncateLog cuts only txn-log files, never snapshots.
    snapZ

serverVars == <<running, role, phase, syncMode, leaderOf>>
epochVars == <<acceptedEpoch, currentEpoch, epochProposal>>
electionVars == <<electionRound, votedFor, electionVotes>>
zabVars == <<epochAcks, newLeaderAcks, newLeaderReady, syncComplete>>
logVars == <<prepared, logPos, syncQueued, pending, durable>>
dbVars == <<memDb, memInit>>
syncVars == <<syncStage, syncBuf, syncCommits, syncPos, syncCut>>
commitVars == <<committed, applied, globalCommitted, acks, durabilityEvidence,
                commitWitness, nextTxn>>
snapVars == <<snapshotBusy, snapshotImage, snapshotPublished, snapZ>>

vars == <<serverVars, epochVars, electionVars, zabVars, logVars, dbVars,
          syncVars, commitVars, snapVars>>

-----------------------------------------------------------------------------
(* Helpers *)

Quorum(q) == q \subseteq Server /\ Cardinality(q) * 2 > Cardinality(Server)
Elems(h) == {h[n] : n \in 1..Len(h)}
LastOf(h) == IF h = <<>> THEN 0 ELSE h[Len(h)]
AppendOnce(h, t) == IF t \in Elems(h) THEN h ELSE Append(h, t)
AtMost(h, x) == SelectSeq(h, LAMBDA u : u <= x)
Above(h, x) == SelectSeq(h, LAMBDA u : u > x)
InsertOrdered(h, t) ==
    IF t \in Elems(h) THEN h ELSE AtMost(h, t) \o <<t>> \o Above(h, t)
NextAfter(h, x) == LET a == Above(h, x) IN IF a = <<>> THEN 0 ELSE a[1]
MaxNat(a, b) == IF a >= b THEN a ELSE b
PrefixOf(a, b) == Len(a) <= Len(b) /\ a = SubSeq(b, 1, Len(a))
Ordered(h) == \A i, j \in 1..Len(h) : i < j => h[i] < h[j]
SetMax(S) == CHOOSE x \in S : \A y \in S : y <= x

\* Value returned by QuorumPeer.getLastLoggedZxid (QuorumPeer.java:1257-1262):
\* the data-tree lastProcessedZxid, after reloading from disk when the
\* ZKDatabase is not initialized.  As a history: what the server claims.
LastLoggedHist(s) == IF memInit[s] THEN memDb[s] ELSE durable[s]
LastZxid(s) == LastOf(LastLoggedHist(s))

\* FastLeaderElection.totalOrderPredicate (FastLeaderElection.java:722-747):
\* peer epoch (currentEpoch), then zxid; server id breaks ties (abstracted
\* by symmetry: either order of equal votes is admitted).
UpToDate(c, v) ==
    \/ currentEpoch[c] > currentEpoch[v]
    \/ /\ currentEpoch[c] = currentEpoch[v]
       /\ LastZxid(c) >= LastZxid(v)

\* Running peers currently in c's ensemble (c LEADING plus its FOLLOWING peers).
Ensemble(c) == {c} \cup {v \in Server : running[v] /\ role[v] = "FOLLOWING"
                                        /\ leaderOf[v] = c}

\* Longest prefix of globalCommitted whose transactions are all in set S.
CommittedPrefixWithin(S) ==
    LET ks == {k \in 0..Len(globalCommitted) :
                 \A i \in 1..k : globalCommitted[i] \in S}
    IN SubSeq(globalCommitted, 1, SetMax(ks))

\* A leader l "has committed" t for COMMIT delivery: t is in its committed
\* log (data tree) or it committed t in broadcast (Leader.tryToCommit).
LeaderSentCommit(l, t) == t \in Elems(memDb[l]) \cup Elems(committed[l])

\* FileTxnSnapLog.restore semantics after a snapshot at zxid z: snapshot
\* image, then log entries with zxid > z (FileTxnSnapLog.java:243-368).
SnapshotMerge(img, log, z) == img \o SelectSeq(log, LAMBDA d : d > z)

-----------------------------------------------------------------------------
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
    /\ logPos = [s \in Server |-> 0]
    /\ syncQueued = [s \in Server |-> <<>>]
    /\ pending = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ memDb = [s \in Server |-> <<>>]
    /\ memInit = [s \in Server |-> TRUE]
    /\ syncStage = [s \in Server |-> "IDLE"]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ syncPos = [s \in Server |-> 0]
    /\ syncCut = [s \in Server |-> 0]
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
    /\ snapZ = [s \in Server |-> 0]

\* Trace bootstrap: processes not yet started; epochs unread.
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
    /\ logPos = [s \in Server |-> 0]
    /\ syncQueued = [s \in Server |-> <<>>]
    /\ pending = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ memDb = [s \in Server |-> <<>>]
    /\ memInit = [s \in Server |-> FALSE]
    /\ syncStage = [s \in Server |-> "IDLE"]
    /\ syncBuf = [s \in Server |-> <<>>]
    /\ syncCommits = [s \in Server |-> <<>>]
    /\ syncPos = [s \in Server |-> 0]
    /\ syncCut = [s \in Server |-> 0]
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
    /\ snapZ = [s \in Server |-> 0]


-----------------------------------------------------------------------------
(* Process lifecycle, crash, and database (re)load                         *)
-----------------------------------------------------------------------------

\* QuorumPeer.start -> loadDataBase at process start (QuorumPeer.java:1086-1150;
\* ZKDatabase.loadDataBase ZKDatabase.java:284-293). A fresh process has an empty
\* sync state; QuorumPeer.syncMode is initialised to NONE (QuorumPeer.java:847).
RestartLoadDatabase(s, ae, ce) ==
    /\ s \in Server /\ ~running[s]
    /\ ae \in (-1)..MaxEpoch /\ ce \in (-1)..MaxEpoch /\ ce <= ae
    /\ running' = [running EXCEPT ![s] = TRUE]
    /\ role' = [role EXCEPT ![s] = "LOOKING"]
    /\ phase' = [phase EXCEPT ![s] = "ELECTION"]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = NoServer]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = ae]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = ce]
    /\ epochProposal' = [epochProposal EXCEPT ![s] = ae]
    /\ votedFor' = [votedFor EXCEPT ![s] = NoServer]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![s] = FALSE]
    /\ syncComplete' = [syncComplete EXCEPT ![s] = FALSE]
    /\ prepared' = [prepared EXCEPT ![s] = durable[s]]
    /\ logPos' = [logPos EXCEPT ![s] = Len(durable[s])]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = <<>>]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    \* FileTxnSnapLog.restore: snapshot + later log records become the data tree.
    /\ memDb' = [memDb EXCEPT ![s] = durable[s]]
    /\ memInit' = [memInit EXCEPT ![s] = TRUE]
    /\ syncStage' = [syncStage EXCEPT ![s] = "IDLE"]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ syncPos' = [syncPos EXCEPT ![s] = 0]
    /\ syncCut' = [syncCut EXCEPT ![s] = 0]
    \* a new process has a fresh Leader object and election receive set
    /\ electionVotes' = [electionVotes EXCEPT ![s] = {}]
    /\ epochAcks' = [epochAcks EXCEPT ![s] = {}]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![s] = {}]
    /\ UNCHANGED <<electionRound, durable, commitVars, snapVars>>

\* UPDATE-MAP
\* code: QuorumPeer.java:1257-1262 (getLastLoggedZxid -> loadDataBase when
\*       !zkDb.isInitialized()); reached after the new zkDb.clear().
\* update: Update!InteractionActions (ReloadDatabase)
\* In-process reload of a cleared ZKDatabase. Same code as process start, but
\* the peer keeps role/phase/syncMode/epochs (cached epochs equal the files).
ReloadDatabase(s) ==
    /\ s \in Server /\ running[s] /\ ~memInit[s]
    /\ memDb' = [memDb EXCEPT ![s] = durable[s]]
    /\ memInit' = [memInit EXCEPT ![s] = TRUE]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   syncVars, commitVars, snapVars>>

\* QuorumPeer.shutdown sets running=false first (QuorumPeer.java:1538-1539);
\* the role objects then drain their SyncRequestProcessor (FlushTxnLog below
\* does not require running) and the process exits. Restart reloads disk.
GracefulShutdown(s) ==
    /\ s \in Server /\ running[s]
    /\ running' = [running EXCEPT ![s] = FALSE]
    /\ UNCHANGED <<role, phase, syncMode, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

\* Abrupt process loss: volatile memory and queues disappear; durable
\* snapshot/log and epoch files survive. Votes for the dead peer are void.
Crash(s) ==
    /\ s \in Server /\ running[s]
    /\ running' = [running EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "LOOKING"]
    /\ phase' = [phase EXCEPT ![s] = "ELECTION"]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = NoServer]
    /\ votedFor' = [votedFor EXCEPT ![s] = NoServer]
    /\ electionVotes' = [electionVotes EXCEPT ![s] = {}]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![s] = FALSE]
    /\ syncComplete' = [syncComplete EXCEPT ![s] = FALSE]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = <<>>]
    /\ pending' = [pending EXCEPT ![s] = <<>>]
    /\ memDb' = [memDb EXCEPT ![s] = <<>>]
    /\ memInit' = [memInit EXCEPT ![s] = FALSE]
    /\ syncStage' = [syncStage EXCEPT ![s] = "IDLE"]
    /\ syncBuf' = [syncBuf EXCEPT ![s] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![s] = <<>>]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = FALSE]
    /\ epochAcks' = [epochAcks EXCEPT ![s] = {}]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![s] = {}]
    /\ UNCHANGED <<epochVars, electionRound,
                   prepared, logPos, durable, syncPos, syncCut, commitVars,
                   snapshotImage, snapshotPublished, snapZ>>

-----------------------------------------------------------------------------
(* Learner exit: the update's directly changed action                      *)
-----------------------------------------------------------------------------

\* UPDATE-MAP
\* code: Learner.java:850-866 (shutdown; NEW line 864
\*       zk.shutdown(self.getSyncMode().equals(QuorumPeer.SyncMode.SNAP)));
\*       ZooKeeperServer.java:803-855 (shutdown(boolean); NEW lines 804-807
\*       clear the ZKDatabase when !canShutdown() && fullyShutDown).
\* update: Update!AffectedActions (LearnerShutdown)
\* Called from QuorumPeer.run's finally after followLeader exits for any
\* reason (QuorumPeer.java:1468-1479) and from QuorumPeer.shutdown
\* (QuorumPeer.java:1544-1546). syncMode is NOT reset here: a stale SNAP
\* survives into the next role (only Learner.java:563/566/589/750 write it).
LearnerShutdown(f) ==
    /\ f \in Server /\ role[f] = "FOLLOWING"
    /\ syncStage[f] # "UPTODATE"   \* UPTODATE post-loop performs no I/O (Learner.java:765-811)
    /\ LET full == UpdateFullShutdownOnSnap /\ syncMode[f] = "SNAP"
           \* canShutdown(): state RUNNING|ERROR (ZooKeeperServer.java:784-786);
           \* a learner's server is RUNNING only after startServing
           \* (Learner.java:767; ZooKeeperServer.java:677-680).
           zkRunning == syncComplete[f]
           \* Running server: SyncRequestProcessor.shutdown drains and flushes
           \* (SyncRequestProcessor.java:254-270) before the zkDb branch.
           \* records handed to logRequest but not yet enqueued in the model are
           \* enqueued atomically by logRequest in the code, so they drain too
           drained == syncQueued[f] \o SubSeq(prepared[f], logPos[f] + 1, Len(prepared[f]))
           flushed == IF zkRunning
                      THEN durable[f] \o SelectSeq(drained,
                                 LAMBDA t : t \notin Elems(durable[f]))
                      ELSE durable[f]
       IN
       /\ durable' = [durable EXCEPT ![f] = flushed]
       /\ syncQueued' = [syncQueued EXCEPT ![f] =
                           IF zkRunning THEN <<>> ELSE @]
       /\ logPos' = [logPos EXCEPT ![f] = IF zkRunning THEN Len(prepared[f]) ELSE @]
       \* closeSocket() precedes zk.shutdown (Learner.java:859-865): records
       \* flushed by the drain cannot be ACKed to the leader.
       /\ UNCHANGED durabilityEvidence
       /\ memDb' = [memDb EXCEPT ![f] =
             IF full THEN <<>>                              \* zkDb.clear()  (ZooKeeperServer.java:805,835)
             ELSE IF zkRunning
                  THEN @ \o Above(flushed, LastOf(@))      \* fastForwardDataBase (ZooKeeperServer.java:848; ZKDatabase.java:300-304)
                  ELSE @]                                   \* old early return keeps the image (ZooKeeperServer.java:808-809)
       /\ memInit' = [memInit EXCEPT ![f] = IF full THEN FALSE ELSE @]
    /\ pending' = [pending EXCEPT ![f] = <<>>]   \* FollowerZooKeeperServer is discarded (QuorumPeer.java:1477)
    /\ syncStage' = [syncStage EXCEPT ![f] = "EXITED"]
    /\ syncBuf' = [syncBuf EXCEPT ![f] = <<>>]
    /\ syncCommits' = [syncCommits EXCEPT ![f] = <<>>]
    /\ syncComplete' = [syncComplete EXCEPT ![f] = FALSE]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, epochAcks,
                   newLeaderAcks, newLeaderReady, prepared,
                   syncPos, syncCut, committed, applied, globalCommitted,
                   acks, commitWitness, nextTxn, snapVars>>

\* QuorumPeer.run finally -> updateServerState -> setPeerState(LOOKING)
\* (QuorumPeer.java:1478,1515-1520,852-856); the nested setZabState(ELECTION)
\* is the separate write EnterElectionPhase.
FollowerExitToLooking(f) ==
    /\ f \in Server /\ role[f] = "FOLLOWING" /\ syncStage[f] = "EXITED"
    /\ role' = [role EXCEPT ![f] = "LOOKING"]
    /\ leaderOf' = [leaderOf EXCEPT ![f] = NoServer]
    /\ votedFor' = [votedFor EXCEPT ![f] = NoServer]
    /\ syncStage' = [syncStage EXCEPT ![f] = "IDLE"]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electionRound,
                   electionVotes, zabVars, logVars, dbVars, syncBuf,
                   syncCommits, syncPos, syncCut, commitVars, snapVars>>

\* setPeerState(LOOKING) -> setZabState(ELECTION) (QuorumPeer.java:856-858).
EnterElectionPhase(s) ==
    /\ s \in Server /\ role[s] = "LOOKING" /\ phase[s] # "ELECTION"
    /\ phase' = [phase EXCEPT ![s] = "ELECTION"]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

\* Leader.shutdown on loss of a synced quorum or failed establishment
\* (Leader.java:739-780 tick loop, :663-686 waitForNewLeaderAck timeout,
\* :1478-1497 QuorumPeer LEADING finally) -> zk.shutdown() (non-full):
\* a running server drains its SyncRequestProcessor and fast-forwards
\* (ZooKeeperServer.java:813-850); then updateServerState -> LOOKING.
LeaderShutdown(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ ~Quorum(Ensemble(l))
    /\ LET zkRunning == phase[l] = "BROADCAST"
           drained == syncQueued[l] \o SubSeq(prepared[l], logPos[l] + 1, Len(prepared[l]))
           flushed == IF zkRunning
                      THEN durable[l] \o SelectSeq(drained,
                                 LAMBDA t : t \notin Elems(durable[l]))
                      ELSE durable[l]
       IN
       /\ durable' = [durable EXCEPT ![l] = flushed]
       /\ syncQueued' = [syncQueued EXCEPT ![l] = IF zkRunning THEN <<>> ELSE @]
       /\ logPos' = [logPos EXCEPT ![l] = IF zkRunning THEN Len(prepared[l]) ELSE @]
       \* the leader no longer processes ACKs once it shuts down
       /\ UNCHANGED durabilityEvidence
       /\ memDb' = [memDb EXCEPT ![l] = IF zkRunning THEN @ \o Above(flushed, LastOf(@)) ELSE @]
    /\ role' = [role EXCEPT ![l] = "LOOKING"]
    /\ leaderOf' = [leaderOf EXCEPT ![l] = NoServer]
    /\ votedFor' = [votedFor EXCEPT ![l] = NoServer]
    /\ electionVotes' = [electionVotes EXCEPT ![l] = {}]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![l] = FALSE]
    /\ epochAcks' = [epochAcks EXCEPT ![l] = {}]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = {}]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electionRound,
                   syncComplete, prepared, pending, memInit,
                   syncVars, committed, applied, globalCommitted, acks,
                   commitWitness, nextTxn, snapVars>>

-----------------------------------------------------------------------------
(* Leader election (FastLeaderElection.lookForLeader)                       *)
-----------------------------------------------------------------------------

\* All running peers are LOOKING: a new election round (new logical clock).
BeginElectionRound ==
    /\ \E s \in Server : running[s]
    /\ \A s \in Server : running[s] => role[s] = "LOOKING"
    /\ electionRound' = electionRound + 1
    /\ votedFor' = [s \in Server |-> NoServer]
    /\ electionVotes' = [s \in Server |-> {}]
    /\ epochAcks' = [s \in Server |-> {}]
    /\ newLeaderAcks' = [s \in Server |-> {}]
    /\ UNCHANGED <<serverVars, epochVars, newLeaderReady, syncComplete,
                   logVars, dbVars, syncVars, commitVars, snapVars>>

\* A LOOKING voter adopts candidate c only if c's (peerEpoch, zxid) is at
\* least its own; both read getInitLastLoggedZxid (FastLeaderElection.java:
\* 867-875,942,1000-1035) which loads a cleared database first.
CastVote(v, c) ==
    /\ v \in Server /\ c \in Server /\ running[v] /\ running[c]
    /\ role[v] = "LOOKING" /\ phase[v] = "ELECTION" /\ role[c] = "LOOKING"
    /\ votedFor[v] = NoServer
    /\ memInit[v] /\ memInit[c]
    /\ UpToDate(c, v)
    /\ votedFor' = [votedFor EXCEPT ![v] = c]
    \* receivers key notifications by sender id: a new vote replaces v's old one
    /\ electionVotes' = [w \in Server |->
          IF w = c THEN electionVotes[w] \cup {v} ELSE electionVotes[w] \ {v}]
    /\ UNCHANGED <<serverVars, epochVars, electionRound, zabVars, logVars,
                   dbVars, syncVars, commitVars, snapVars>>

\* Election termination. Either a quorum voted for c in this round (s is c
\* or one of its voters; FastLeaderElection.java:1012-1050), or c is an
\* established leader and a quorum of running peers report LEADING/FOLLOWING
\* c (out-of-election path, FastLeaderElection.java:1054-1088; no zxid
\* comparison is made on that path).
FinishElection(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s] /\ running[c]
    /\ role[s] = "LOOKING" /\ phase[s] = "ELECTION" /\ memInit[s]
    /\ IF role[c] = "LEADING" /\ s # c
       THEN Quorum(Ensemble(c))
       ELSE /\ Quorum(electionVotes[c])
            /\ (s = c \/ s \in electionVotes[c])
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electionVars, zabVars,
                   logVars, dbVars, syncVars, commitVars, snapVars>>

\* Trace form of a completed election: votes are not instrumented, so the
\* observed winner's quorum is recorded. For a fresh election the winner must
\* be at least as up to date as every LOOKING running peer (all three peers
\* participate in the harness elections).
ObserveElectionResult(s, c) ==
    /\ s \in Server /\ c \in Server /\ running[s] /\ memInit[s]
    /\ role[s] \in {"LOOKING", "FOLLOWING", "LEADING"}
    /\ IF role[c] = "LEADING" /\ c # s THEN TRUE
       ELSE \A v \in Server : running[v] /\ role[v] = "LOOKING" /\ memInit[v]
                                 => UpToDate(c, v)
    /\ role' = [role EXCEPT ![s] = IF s = c THEN "LEADING" ELSE "FOLLOWING"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = c]
    /\ electionVotes' = [electionVotes EXCEPT ![c] = Server]
    /\ votedFor' = [votedFor EXCEPT ![s] = c]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electionRound, zabVars,
                   logVars, dbVars, syncVars, commitVars, snapVars>>

ObserveSetZabState(s, p) ==
    /\ s \in Server /\ p \in Phases
    /\ phase' = [phase EXCEPT ![s] = p]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

ObserveSetPeerState(s, r) ==
    /\ s \in Server /\ r \in Roles
    /\ role' = [role EXCEPT ![s] = r]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = IF r = "LOOKING" THEN NoServer ELSE @]
    /\ UNCHANGED <<running, phase, syncMode, epochVars, electionVars, zabVars,
                   logVars, dbVars, syncVars, commitVars, snapVars>>

-----------------------------------------------------------------------------
(* Discovery                                                                *)
-----------------------------------------------------------------------------

\* Leader.lead / Follower.followLeader first set ZabState DISCOVERY
\* (Leader.java:591; Follower.java:86).
EnterDiscovery(s) ==
    /\ s \in Server /\ running[s] /\ phase[s] = "ELECTION"
    /\ role[s] \in {"LEADING", "FOLLOWING"}
    /\ phase' = [phase EXCEPT ![s] = "DISCOVERY"]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>


\* QuorumPeer.setAcceptedEpoch (QuorumPeer.java:2176-2180): leader at
\* Leader.java:1405 (getEpochToPropose), learner at Learner.java:509-511.
PersistAcceptedEpoch(s, e) ==
    /\ s \in Server /\ running[s] /\ e \in 0..MaxEpoch
    /\ phase[s] = "DISCOVERY"
    /\ e >= acceptedEpoch[s]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = e]
    /\ epochProposal' = [epochProposal EXCEPT ![s] = e]
    /\ UNCHANGED <<serverVars, currentEpoch, electionVars, zabVars, logVars,
                   dbVars, syncVars, commitVars, snapVars>>

\* Learner.registerWithLeader: LEADERINFO carries the leader's proposed epoch
\* (sent only after getEpochToPropose); a newer epoch is persisted
\* (Learner.java:504-511).
FollowerPersistAcceptedEpoch(f) ==
    /\ f \in Server /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] \in Server /\ running[leaderOf[f]]
    /\ role[leaderOf[f]] = "LEADING" /\ leaderOf[f] \in epochAcks[leaderOf[f]]
    /\ acceptedEpoch[leaderOf[f]] = epochProposal[leaderOf[f]]
    /\ epochProposal[leaderOf[f]] > acceptedEpoch[f]
    /\ PersistAcceptedEpoch(f, epochProposal[leaderOf[f]])

\* QuorumPeer.setCurrentEpoch (QuorumPeer.java:2169-2173). Leader call site
\* Leader.java:658 is LeaderEpochQuorum for model checking; the
\* trace replays the observed write through this generic form.
PersistCurrentEpoch(s, e) ==
    /\ s \in Server /\ running[s] /\ e \in 0..MaxEpoch
    /\ e >= currentEpoch[s] /\ e <= acceptedEpoch[s]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = e]
    /\ UNCHANGED <<serverVars, acceptedEpoch, epochProposal, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

\* Leader.waitForEpochAck collects ACKEPOCH (Leader.java:1430-1471;
\* LearnerHandler.java:530-547).
RecordEpochAck(l, f) ==
    /\ l \in Server /\ f \in Server /\ running[l] /\ running[f]
    /\ role[l] = "LEADING" /\ phase[l] = "DISCOVERY" /\ l \in epochAcks[l]
    /\ epochProposal[l] > currentEpoch[l]
    /\ acceptedEpoch[l] = epochProposal[l]
    /\ phase[f] \in {"DISCOVERY", "SYNCHRONIZATION"}
    /\ f = l \/ leaderOf[f] = l
    /\ acceptedEpoch[f] = epochProposal[l]
    /\ epochAcks' = [epochAcks EXCEPT ![l] = @ \cup {f}]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, newLeaderAcks,
                   newLeaderReady, syncComplete, logVars, dbVars, syncVars,
                   commitVars, snapVars>>

\* Leader.lead: zk.loadData (Leader.java:593), getEpochToPropose persists
\* the new accepted epoch (Leader.java:602,1391-1419), then zk.setZxid(epoch,0)
\* and lastProposed (Leader.java:604-607). The proposal history starts from
\* the loaded data tree; syncCut[l] records the epoch base (every id <= it
\* belongs to an earlier epoch). The leader's own epoch ACK is counted
\* (waitForEpochAck(self.getId()), Leader.java:657,1460).
LeaderPersistEpoch(l, e) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ phase[l] = "DISCOVERY" /\ memInit[l] /\ l \notin epochAcks[l]
    /\ e \in 0..MaxEpoch /\ e > acceptedEpoch[l]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![l] = e]
    /\ epochProposal' = [epochProposal EXCEPT ![l] = e]
    /\ epochAcks' = [epochAcks EXCEPT ![l] = @ \cup {l}]
    /\ prepared' = [prepared EXCEPT ![l] = memDb[l]]
    /\ logPos' = [logPos EXCEPT ![l] = Len(memDb[l])]
    /\ syncCut' = [syncCut EXCEPT ![l] = nextTxn - 1]
    /\ UNCHANGED <<serverVars, currentEpoch, electionVars, newLeaderAcks,
                   newLeaderReady, syncComplete, syncQueued, pending, durable,
                   dbVars, syncStage, syncBuf, syncCommits, syncPos,
                   commitVars, snapVars>>

\* Model-checking choice of the epoch: max accepted epoch among the
\* connecting quorum (modelled as the leader's voters) and itself, plus one.
LeaderProposeEpoch(l) ==
    LeaderPersistEpoch(l, 1 + SetMax({acceptedEpoch[v] : v \in electionVotes[l] \cup {l}}))

\* waitForEpochAck returned with a quorum; setCurrentEpoch(epoch)
\* (Leader.java:657-658).
LeaderEpochQuorum(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ phase[l] = "DISCOVERY" /\ l \in epochAcks[l]
    /\ Quorum(epochAcks[l])
    /\ currentEpoch[l] < epochProposal[l]
    /\ epochProposal[l] <= acceptedEpoch[l]
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = epochProposal[l]]
    /\ UNCHANGED <<serverVars, acceptedEpoch, epochProposal, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

\* setZabState(SYNCHRONIZATION) (Leader.java:660); waitForNewLeaderAck counts
\* the leader itself (Leader.java:663). Follower NEWLEADER ACKs recorded by
\* LearnerHandler threads before this point are kept.
LeaderStartSyncCore(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ phase[l] = "DISCOVERY" /\ memInit[l] /\ l \in epochAcks[l]
    /\ currentEpoch[l] = epochProposal[l] /\ epochProposal[l] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![l] = "SYNCHRONIZATION"]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = @ \cup {l}]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![l] = FALSE]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electionVars,
                   epochAcks, syncComplete, logVars, dbVars, syncVars,
                   commitVars, snapVars>>

\* Model-checking form: the epoch was proposed in this leadership and the
\* epoch-ACK quorum was reached (Leader.java:602-658).
LeaderStartSync(l) ==
    /\ Quorum(epochAcks[l])
    /\ LeaderStartSyncCore(l)

-----------------------------------------------------------------------------
(* Learner synchronization (Learner.syncWithLeader, Learner.java:546-812)   *)
-----------------------------------------------------------------------------

\* LearnerHandler threads leave waitForEpochAck as soon as the epoch quorum
\* exists (Leader.java:1442-1475), concurrently with the leader thread's
\* setCurrentEpoch/setZabState; late joiners find it already finished.
LeaderEpochAgreed(l) ==
    /\ running[l] /\ role[l] = "LEADING" /\ l \in epochAcks[l]
    /\ acceptedEpoch[l] = epochProposal[l]
    /\ (Quorum(epochAcks[l]) \/ currentEpoch[l] = epochProposal[l])

\* Follower.followLeader: registerWithLeader returned (LEADERINFO handled,
\* ACKEPOCH carrying getLastLoggedZxid sent; Learner.java:483-526), then
\* setZabState(SYNCHRONIZATION) (Follower.java:107).
EnterFollowerSync(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ phase[f] = "DISCOVERY" /\ memInit[f]
    /\ leaderOf[f] \in Server
    /\ running[leaderOf[f]] /\ role[leaderOf[f]] = "LEADING"
    /\ leaderOf[f] \in epochAcks[leaderOf[f]]
    /\ acceptedEpoch[leaderOf[f]] = epochProposal[leaderOf[f]]
    /\ acceptedEpoch[f] = epochProposal[leaderOf[f]]
    /\ phase' = [phase EXCEPT ![f] = "SYNCHRONIZATION"]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

\* LearnerHandler.syncFollower decision (LearnerHandler.java:775-932) plus
\* the learner's first-packet setSyncMode (Learner.java:557-566,587-589).
\* pl = peerLastZxid from ACKEPOCH (= LastZxid(f): f's thread is blocked and
\* its database unchanged since registration). The leader's committed log
\* is its data tree memDb[l]; maxCommittedLog = LastOf(memDb[l]).
\*  DIFF  : pl equals or is inside the leader's history (:845-853,864-869,
\*          :870-899 on-disk log); payload = leader history after pl.
\*  TRUNC : pl beyond maxCommittedLog of a nonempty committed log (:854-863);
\*          an empty committed log uses the new-epoch lastProcessedZxid,
\*          which is above every earlier-epoch pl, so TRUNC is impossible.
\*  SNAP  : always admissible (forceSnapSync, log gaps, cross-epoch; :836-843,
\*          :915-917, queueCommittedProposals :990-997).
\* startForwarding (Leader.java:1289-1322) queues everything up to
\* lastProposed before NEWLEADER is queued (LearnerHandler.java:591-600).
ChooseSyncMode(f, m) ==
    /\ f \in Server /\ m \in {"DIFF", "TRUNC", "SNAP"} /\ running[f]
    /\ role[f] = "FOLLOWING" /\ phase[f] = "SYNCHRONIZATION"
    /\ syncStage[f] = "IDLE" /\ ~syncComplete[f] /\ memInit[f]
    /\ leaderOf[f] \in Server /\ LeaderEpochAgreed(leaderOf[f])
    /\ epochProposal[leaderOf[f]] = acceptedEpoch[f]
    /\ LET l == leaderOf[f]
           pl == LastOf(memDb[f])
           cut == LastOf(memDb[l])
       IN
       /\ CASE m = "DIFF" -> pl <= cut /\ (pl = 0 \/ pl \in Elems(memDb[l]))
            [] m = "TRUNC" -> memDb[l] # <<>> /\ pl > cut
            [] m = "SNAP" -> TRUE
       /\ syncMode' = [syncMode EXCEPT ![f] = m]
       /\ syncStage' = [syncStage EXCEPT ![f] = IF m = "DIFF" THEN "DATA" ELSE "MODE"]
       /\ syncPos' = [syncPos EXCEPT ![f] = IF m = "DIFF" THEN pl ELSE cut]
       /\ syncCut' = [syncCut EXCEPT ![f] = LastOf(prepared[l])]
       \* a new FollowerZooKeeperServer per followLeader (QuorumPeer.java:1268-1270)
       /\ prepared' = [prepared EXCEPT ![f] = <<>>]
       /\ logPos' = [logPos EXCEPT ![f] = 0]
       /\ syncBuf' = [syncBuf EXCEPT ![f] = <<>>]
       /\ syncCommits' = [syncCommits EXCEPT ![f] = <<>>]
    /\ UNCHANGED <<running, role, phase, leaderOf, epochVars, electionVars,
                   zabVars, syncQueued, pending, durable, dbVars, commitVars,
                   snapVars>>

\* UPDATE-MAP
\* code: Learner.java:565-586 (SNAP: deserializeSnapshot, setlastProcessedZxid);
\*       the in-memory image this creates is what the update discards.
\* update: Update!InteractionActions (LearnerApplySnapshot)
\* Leader serializes its data tree up to the decision point
\* (LearnerHandler.java:558-588); ZKDatabase.deserializeSnapshot clears and
\* replaces the tree (ZKDatabase.java:618-622). Disk is untouched.
LearnerApplySnapshot(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncMode[f] = "SNAP" /\ syncStage[f] = "MODE"
    /\ leaderOf[f] \in Server /\ LeaderEpochAgreed(leaderOf[f])
    /\ memDb' = [memDb EXCEPT ![f] = AtMost(memDb[leaderOf[f]], syncPos[f])]
    /\ memInit' = [memInit EXCEPT ![f] = TRUE]
    /\ syncStage' = [syncStage EXCEPT ![f] = "DATA"]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   syncBuf, syncCommits, syncPos, syncCut, commitVars, snapVars>>

\* Learner.java:587-598: ZKDatabase.truncateLog = clear, cut the log after
\* the zxid, reload (ZKDatabase.java:599-611; FileTxnSnapLog.truncateLog).
LearnerTruncateLog(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncMode[f] = "TRUNC" /\ syncStage[f] = "MODE"
    \* Only log records above the cut are removed; records covered by the
    \* newest snapshot survive and are reloaded (FileTxnSnapLog.java:502-524;
    \* FileTxnLog.truncate :455-475; ZKDatabase.truncateLog :599-611). The
    \* learner then forces lastProcessedZxid to the cut (Learner.java:597),
    \* so the reported/streamed position is the cut; reloaded snapshot
    \* contents above it are re-received as duplicates.
    /\ LET kept == AtMost(durable[f], MaxNat(syncPos[f], snapZ[f])) IN
       /\ durable' = [durable EXCEPT ![f] = kept]
       /\ memDb' = [memDb EXCEPT ![f] = AtMost(kept, syncPos[f])]
       /\ memInit' = [memInit EXCEPT ![f] = TRUE]
    /\ syncStage' = [syncStage EXCEPT ![f] = "DATA"]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, prepared,
                   logPos, syncQueued, pending, syncBuf, syncCommits, syncPos,
                   syncCut, commitVars, snapVars>>

\* Learner.java:621-642: PROPOSAL read during sync is buffered in
\* packetsNotCommitted. The leader stream is its proposal history in zxid
\* order (committed-log diff, then forwarded toBeApplied/outstanding/new).
\* Packets are read only while the learner thread is between packet handlers.
LearnerSyncPacket(f, t) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncStage[f] \in {"DATA", "ACKED"}
    /\ leaderOf[f] \in Server /\ LeaderEpochAgreed(leaderOf[f])
    /\ t \in Txn /\ t = NextAfter(prepared[leaderOf[f]], syncPos[f])
    \* FIFO: NEWLEADER is queued right after syncFollower returns
    \* (LearnerHandler.java:551-600), so before NEWLEADER only proposals queued
    \* by the diff / startForwarding (up to lastProposed at decision) are read.
    /\ syncStage[f] = "DATA" => t <= syncCut[f]
    /\ syncBuf' = [syncBuf EXCEPT ![f] = Append(@, t)]
    /\ syncPos' = [syncPos EXCEPT ![f] = t]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   dbVars, syncStage, syncCommits, syncCut, commitVars,
                   snapVars>>

\* Learner.java:643-669: COMMIT during sync.
\*  !writeToTxnLog (SNAP/TRUNC before NEWLEADER, Learner.java:555,614,656-665):
\*     zk.processTxn applies the head proposal to the data tree only.
\*  writeToTxnLog (DIFF, or any mode after NEWLEADER, :744): packetsCommitted.
\* COMMITs arrive in zxid order for proposals already read.
LearnerSyncCommit(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncStage[f] \in {"DATA", "ACKED"}
    /\ leaderOf[f] \in Server /\ running[leaderOf[f]]
    /\ role[leaderOf[f]] = "LEADING"
    /\ LET l == leaderOf[f]
           inMemory == syncMode[f] \in {"SNAP", "TRUNC"} /\ syncStage[f] = "DATA"
           cands == {u \in Elems(pending[f]) \cup Elems(syncBuf[f]) :
                        u > LastOf(syncCommits[f])}
       IN
       IF inMemory
       THEN /\ syncBuf[f] # <<>>
            /\ LeaderSentCommit(l, Head(syncBuf[f]))
            /\ memDb' = [memDb EXCEPT ![f] = InsertOrdered(@, Head(syncBuf[f]))]
            /\ syncBuf' = [syncBuf EXCEPT ![f] = Tail(@)]
            /\ UNCHANGED <<syncCommits, memInit>>
       ELSE /\ cands # {}
            /\ LET t == CHOOSE u \in cands : \A w \in cands : u <= w IN
               /\ LeaderSentCommit(l, t)
               /\ syncCommits' = [syncCommits EXCEPT ![f] = Append(@, t)]
            /\ UNCHANGED <<memDb, memInit, syncBuf>>
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   syncStage, syncPos, syncCut, commitVars, snapVars>>

NewLeaderReadable(f) ==
    /\ leaderOf[f] \in Server /\ LeaderEpochAgreed(leaderOf[f])
    /\ syncPos[f] >= syncCut[f]

\* UPDATE-MAP
\* code: Learner.java:739-741 (NEWLEADER: takeSnapshot when snapshotNeeded);
\*       the durability point the update protects.
\* update: Update!InteractionActions (LearnerSyncSnapshot)
\* takeSnapshot serializes the data tree at lastProcessedZxid
\* (ZooKeeperServer.java:517-536). For SNAP that zxid is at least the leader's
\* epoch base (setlastProcessedZxid(qp.getZxid()), Learner.java:583).
LearnerSyncSnapshot(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncMode[f] \in {"SNAP", "TRUNC"} /\ syncStage[f] = "DATA"
    /\ NewLeaderReadable(f)
    /\ LET z == IF syncMode[f] = "SNAP"
                THEN MaxNat(LastOf(memDb[f]), syncCut[leaderOf[f]])
                ELSE LastOf(memDb[f])
       IN /\ durable' = [durable EXCEPT ![f] = SnapshotMerge(memDb[f], @, z)]
          /\ snapZ' = [snapZ EXCEPT ![f] = z]
    /\ durabilityEvidence' = [t \in Txn |->
          IF t \in Elems(memDb[f]) THEN durabilityEvidence[t] \cup {f}
          ELSE durabilityEvidence[t]]
    /\ syncStage' = [syncStage EXCEPT ![f] = "SNAPPED"]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, prepared,
                   logPos, syncQueued, pending, dbVars, syncBuf, syncCommits,
                   syncPos, syncCut, committed, applied, globalCommitted, acks,
                   commitWitness, nextTxn, snapshotBusy, snapshotImage,
                   snapshotPublished>>

\* Learner.java:743: setCurrentEpoch(newEpoch) while handling NEWLEADER.
LearnerPersistCurrentEpoch(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ \/ syncMode[f] = "DIFF" /\ syncStage[f] = "DATA" /\ NewLeaderReadable(f)
       \/ syncMode[f] \in {"SNAP", "TRUNC"} /\ syncStage[f] = "SNAPPED"
    /\ acceptedEpoch[f] >= currentEpoch[f]
    /\ currentEpoch' = [currentEpoch EXCEPT ![f] = acceptedEpoch[f]]
    /\ syncStage' = [syncStage EXCEPT ![f] = "EPOCH"]
    /\ UNCHANGED <<serverVars, acceptedEpoch, epochProposal, electionVars,
                   zabVars, logVars, dbVars, syncBuf, syncCommits, syncPos,
                   syncCut, commitVars, snapVars>>

\* UPDATE-MAP
\* code: Learner.java:744-751 (writeToTxnLog=true; setSyncMode(NONE)); the
\*       updated shutdown reads this mode (Learner.java:864).
\* update: Update!InteractionActions (LearnerNewLeaderModeNone)
LearnerNewLeaderModeNone(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncStage[f] = "EPOCH"
    /\ syncMode' = [syncMode EXCEPT ![f] = "NONE"]
    /\ syncStage' = [syncStage EXCEPT ![f] = "NEWLEADER"]
    /\ UNCHANGED <<running, role, phase, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncBuf, syncCommits, syncPos,
                   syncCut, commitVars, snapVars>>

\* Learner.java:760 writes ACK(newLeaderZxid) after logging every buffered
\* proposal (Learner.java:752-758); LearnerHandler records it
\* (LearnerHandler.java:603-627).
LearnerAckNewLeader(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncStage[f] = "NEWLEADER" /\ syncBuf[f] = <<>>
    /\ logPos[f] = Len(prepared[f])
    /\ leaderOf[f] \in Server /\ running[leaderOf[f]]
    /\ role[leaderOf[f]] = "LEADING"
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![leaderOf[f]] = @ \cup {f}]
    /\ syncStage' = [syncStage EXCEPT ![f] = "ACKED"]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, epochAcks,
                   newLeaderReady, syncComplete, logVars, dbVars, syncBuf,
                   syncCommits, syncPos, syncCut, commitVars, snapVars>>

\* Leader.waitForNewLeaderAck returned (Leader.java:663). Zab commits the
\* leader's initial history with the NEWLEADER quorum: no PROPOSAL/COMMIT is
\* issued for it, followers obtain it through DIFF/TRUNC/SNAP.
FormNewLeaderQuorum(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ phase[l] = "SYNCHRONIZATION" /\ ~newLeaderReady[l]
    /\ Quorum(newLeaderAcks[l])
    /\ LET newly == SelectSeq(prepared[l],
                        LAMBDA t : t \notin Elems(globalCommitted))
           gc == globalCommitted \o newly
       IN
       /\ globalCommitted' = gc
       /\ commitWitness' = [t \in Txn |->
             IF t \in Elems(newly) THEN newLeaderAcks[l] ELSE commitWitness[t]]
       /\ committed' = [committed EXCEPT ![l] = gc]
       /\ applied' = [applied EXCEPT ![l] = gc]
    /\ newLeaderReady' = [newLeaderReady EXCEPT ![l] = TRUE]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, epochAcks,
                   newLeaderAcks, syncComplete, logVars, dbVars, syncVars,
                   acks, durabilityEvidence, nextTxn, snapVars>>

\* Trace form: the leader's observed waitForNewLeaderAck success. Follower
\* NEWLEADER ACK events are replayed first; the quorum is then required.
ObserveNewLeaderQuorum(l) == FormNewLeaderQuorum(l)

\* UPTODATE: LearnerHandler waits for the leader's server to start
\* (LearnerHandler.java:641-648); learner calls startServing
\* (Learner.java:711-725,765-767).
LearnerUpToDate(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncStage[f] = "ACKED"
    /\ leaderOf[f] \in Server /\ running[leaderOf[f]]
    /\ role[leaderOf[f]] = "LEADING" /\ phase[leaderOf[f]] = "BROADCAST"
    /\ syncStage' = [syncStage EXCEPT ![f] = "UPTODATE"]
    \* The served data tree's committed prefix becomes the learner's commit and
    \* apply record; later commits are queued through FollowerZooKeeperServer.
    /\ committed' = [committed EXCEPT ![f] =
          CommittedPrefixWithin(Elems(memDb[f]) \cup Elems(committed[f]))]
    /\ applied' = [applied EXCEPT ![f] =
          LET a == CommittedPrefixWithin(Elems(memDb[f]))
          IN IF Len(a) >= Len(applied[f]) THEN a ELSE applied[f]]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   dbVars, syncBuf, syncCommits, syncPos, syncCut,
                   globalCommitted, acks, durabilityEvidence, commitWitness,
                   nextTxn, snapVars>>

\* Follower.java:108-109: syncWithLeader returned (after the post-loop
\* logRequest/commit, Learner.java:777-785).
CompleteLearnerSync(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ syncStage[f] = "UPTODATE"
    /\ syncBuf[f] = <<>> /\ syncCommits[f] = <<>>
    /\ logPos[f] = Len(prepared[f])
    /\ syncComplete' = [syncComplete EXCEPT ![f] = TRUE]
    /\ syncStage' = [syncStage EXCEPT ![f] = "IDLE"]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, epochAcks,
                   newLeaderAcks, newLeaderReady, logVars, dbVars, syncBuf,
                   syncCommits, syncPos, syncCut, commitVars, snapVars>>

\* Leader.lead: startZkServer then setZabState(BROADCAST) (Leader.java:688-700).
LeaderEnterBroadcast(l) ==
    /\ l \in Server /\ running[l] /\ role[l] = "LEADING"
    /\ phase[l] = "SYNCHRONIZATION" /\ newLeaderReady[l]
    /\ phase' = [phase EXCEPT ![l] = "BROADCAST"]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

\* Follower.followLeader: setZabState(BROADCAST) after syncWithLeader returns
\* (Follower.java:109).
FollowerEnterBroadcast(f) ==
    /\ f \in Server /\ running[f] /\ role[f] = "FOLLOWING"
    /\ phase[f] = "SYNCHRONIZATION" /\ syncComplete[f] /\ syncStage[f] = "IDLE"
    /\ phase' = [phase EXCEPT ![f] = "BROADCAST"]
    /\ UNCHANGED <<running, role, syncMode, leaderOf, epochVars, electionVars,
                   zabVars, logVars, dbVars, syncVars, commitVars, snapVars>>

-----------------------------------------------------------------------------
(* Broadcast pipeline                                                      *)
-----------------------------------------------------------------------------

\* Leader.propose (Leader.java:1215-1256) while the leader still holds a
\* synced quorum: Leader.lead's tick loop shuts the leader down once the
\* synced set is no quorum (Leader.java:739-780). Abstraction: no proposal in
\* the detection window, which keeps id order equal to zxid order.
LeaderPropose(l, t) ==
    /\ l \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ phase[l] = "BROADCAST"
    /\ newLeaderReady[l] /\ t = nextTxn
    /\ Quorum(Ensemble(l))
    /\ prepared' = [prepared EXCEPT ![l] = Append(@, t)]
    /\ acks' = [acks EXCEPT ![t] = {}]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = {}]
    /\ commitWitness' = [commitWitness EXCEPT ![t] = {}]
    /\ nextTxn' = nextTxn + 1
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logPos,
                   syncQueued, pending, durable, dbVars, syncVars, committed,
                   applied, globalCommitted, snapVars>>

\* FollowerZooKeeperServer.logRequest: pendingTxns.add (FollowerZooKeeperServer.java:82-89).
\*  broadcast: Follower.processPacket PROPOSAL (Follower.java:165-203)
\*  sync    : packetsNotCommitted at NEWLEADER / after UPTODATE (Learner.java:752-757,778-782)
FollowerPendingProposal(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f] /\ role[f] = "FOLLOWING"
    /\ leaderOf[f] \in Server
    /\ \/ /\ syncStage[f] \in {"NEWLEADER", "UPTODATE"}
          /\ syncBuf[f] # <<>> /\ t = Head(syncBuf[f])
          /\ syncBuf' = [syncBuf EXCEPT ![f] = Tail(@)]
          /\ UNCHANGED syncPos
       \/ /\ syncComplete[f] /\ phase[f] = "BROADCAST" /\ syncStage[f] = "IDLE"
          /\ running[leaderOf[f]] /\ role[leaderOf[f]] = "LEADING"
          /\ t = NextAfter(prepared[leaderOf[f]], syncPos[f])
          /\ syncPos' = [syncPos EXCEPT ![f] = t]
          /\ UNCHANGED syncBuf
    /\ pending' = [pending EXCEPT ![f] = Append(@, t)]
    /\ prepared' = [prepared EXCEPT ![f] = Append(@, t)]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logPos,
                   syncQueued, durable, dbVars, syncStage, syncCommits,
                   syncCut, commitVars, snapVars>>

\* SyncRequestProcessor.processRequest enqueues (SyncRequestProcessor.java:273-279);
\* leader after Leader.propose (ProposalRequestProcessor.java:68-90), learner
\* inside logRequest. Already-durable records are not re-appended in the model.
QueueForSync(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s]
    /\ logPos[s] < Len(prepared[s]) /\ t = prepared[s][logPos[s] + 1]
    /\ syncQueued' = [syncQueued EXCEPT ![s] =
          IF t \in Elems(durable[s]) THEN @ ELSE AppendOnce(@, t)]
    /\ logPos' = [logPos EXCEPT ![s] = @ + 1]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, prepared,
                   pending, durable, dbVars, syncVars, commitVars, snapVars>>

\* SyncRequestProcessor.flush -> ZKDatabase.commit (SyncRequestProcessor.java:227-250).
\* Not guarded by running: the processor drains on shutdown, and a learner
\* server whose shutdown returned early keeps its processor thread.
FlushTxnLog(s, t) ==
    /\ s \in Server /\ t \in Txn
    /\ syncQueued[s] # <<>> /\ t = Head(syncQueued[s])
    /\ durable' = [durable EXCEPT ![s] = AppendOnce(@, t)]
    /\ syncQueued' = [syncQueued EXCEPT ![s] = Tail(@)]
    /\ durabilityEvidence' = [durabilityEvidence EXCEPT ![t] = @ \cup {s}]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, prepared,
                   logPos, pending, dbVars, syncVars, committed, applied,
                   globalCommitted, acks, commitWitness, nextTxn, snapVars>>

\* Leader.processAck (Leader.java:974-1041): ACKs follow a completed flush
\* (AckRequestProcessor / SendAckRequestProcessor after SyncRequestProcessor).
RecordProposalAck(l, source, t) ==
    /\ l \in Server /\ source \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ newLeaderReady[l]
    /\ t \in Elems(prepared[l]) /\ t > syncCut[l]
    /\ t \notin Elems(globalCommitted)
    /\ source \in durabilityEvidence[t]
    /\ acks' = [acks EXCEPT ![t] = @ \cup {source}]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   dbVars, syncVars, committed, applied, globalCommitted,
                   durabilityEvidence, commitWitness, nextTxn, snapVars>>

\* Leader.tryToCommit (Leader.java:890-962): quorum and predecessor committed.
CommitProposal(l, t) ==
    /\ l \in Server /\ t \in Txn /\ running[l]
    /\ role[l] = "LEADING" /\ newLeaderReady[l] /\ Quorum(acks[t])
    /\ t \in Elems(prepared[l]) /\ t > syncCut[l]
    /\ t \notin Elems(globalCommitted)
    /\ \A u \in Elems(prepared[l]) : u < t => u \in Elems(globalCommitted)
    /\ globalCommitted' = Append(globalCommitted, t)
    /\ committed' = [committed EXCEPT ![l] = AppendOnce(@, t)]
    /\ commitWitness' = [commitWitness EXCEPT ![t] = acks[t]]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   dbVars, syncVars, applied, acks, durabilityEvidence,
                   nextTxn, snapVars>>

\* FollowerZooKeeperServer.commit: head of pendingTxns must match
\* (FollowerZooKeeperServer.java:97-110).
\*  broadcast: Follower.processPacket COMMIT (Follower.java:204-212)
\*  sync     : packetsCommitted after UPTODATE (Learner.java:783-785)
FollowerCommit(f, t) ==
    /\ f \in Server /\ t \in Txn /\ running[f] /\ role[f] = "FOLLOWING"
    /\ pending[f] # <<>> /\ t = Head(pending[f])
    \* logRequest queues before returning (FollowerZooKeeperServer.java:82-90)
    /\ t \in Elems(syncQueued[f]) \cup Elems(durable[f])
    /\ leaderOf[f] \in Server
    /\ \/ /\ syncStage[f] = "UPTODATE"
          /\ syncCommits[f] # <<>> /\ t = Head(syncCommits[f])
          /\ syncCommits' = [syncCommits EXCEPT ![f] = Tail(@)]
       \/ /\ syncComplete[f] /\ syncStage[f] = "IDLE"
          /\ running[leaderOf[f]] /\ role[leaderOf[f]] = "LEADING"
          /\ t \in Elems(committed[leaderOf[f]])
          /\ UNCHANGED syncCommits
    /\ pending' = [pending EXCEPT ![f] = Tail(@)]
    /\ committed' = [committed EXCEPT ![f] = AppendOnce(@, t)]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, prepared,
                   logPos, syncQueued, durable, dbVars, syncStage, syncBuf,
                   syncPos, syncCut, applied, globalCommitted, acks,
                   durabilityEvidence, commitWitness, nextTxn, snapVars>>

\* FinalRequestProcessor.applyRequest -> ZooKeeperServer.processTxn
\* (FinalRequestProcessor.java:111-113): the data tree changes.
ApplyTxn(s, t) ==
    /\ s \in Server /\ t \in Txn /\ running[s] /\ memInit[s]
    \* only a serving server's CommitProcessor -> FinalRequestProcessor chain
    \* applies: leader after startZkServer, learner after startServing
    \* (Learner.java:767); Learner.shutdown/Leader.shutdown stop it.
    /\ \/ role[s] = "LEADING" /\ phase[s] = "BROADCAST"
       \/ role[s] = "FOLLOWING" /\ (syncComplete[s] \/ syncStage[s] = "UPTODATE")
    /\ Len(applied[s]) < Len(committed[s])
    /\ t = committed[s][Len(applied[s]) + 1]
    /\ applied' = [applied EXCEPT ![s] = Append(@, t)]
    /\ memDb' = [memDb EXCEPT ![s] = InsertOrdered(@, t)]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   memInit, syncVars, committed, globalCommitted, acks,
                   durabilityEvidence, commitWitness, nextTxn, snapVars>>

\* Periodic/leader-start fuzzy snapshots (ZooKeeperServer.takeSnapshot,
\* ZooKeeperServer.java:517-536; SyncRequestProcessor.java:180-201): their
\* image is already covered by the txn log, so durable history is unchanged.
BeginSnapshot(s) ==
    /\ s \in Server /\ running[s] /\ role[s] \in {"LEADING", "FOLLOWING"}
    /\ ~snapshotBusy[s]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = TRUE]
    /\ snapshotImage' = [snapshotImage EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   dbVars, syncVars, commitVars, snapshotPublished, snapZ>>

FinishSnapshot(s) ==
    /\ s \in Server /\ snapshotBusy[s]
    /\ snapshotBusy' = [snapshotBusy EXCEPT ![s] = FALSE]
    /\ snapshotPublished' = [snapshotPublished EXCEPT ![s] = snapshotImage[s]]
    /\ snapZ' = [snapZ EXCEPT ![s] = MaxNat(@, LastOf(snapshotImage[s]))]
    /\ UNCHANGED <<serverVars, epochVars, electionVars, zabVars, logVars,
                   dbVars, syncVars, commitVars, snapshotImage>>

-----------------------------------------------------------------------------
(* Complete unbounded next-state relation of the reference.  MC.tla bounds  *)
(* the fault-injection disjuncts; base.cfg bounds it with BaseConstraint.   *)
-----------------------------------------------------------------------------
Next ==
    \/ BeginElectionRound
    \/ \E v, c \in Server : CastVote(v, c)
    \/ \E s, c \in Server : FinishElection(s, c)
    \/ \E s \in Server : EnterDiscovery(s)
    \/ \E l \in Server : LeaderProposeEpoch(l)
    \/ \E f \in Server : FollowerPersistAcceptedEpoch(f)
    \/ \E l, f \in Server : f # l /\ RecordEpochAck(l, f)
    \/ \E l \in Server : LeaderEpochQuorum(l)
    \/ \E l \in Server : LeaderStartSync(l)
    \/ \E f \in Server : EnterFollowerSync(f)
    \/ \E f \in Server : \E m \in {"DIFF", "TRUNC", "SNAP"} : ChooseSyncMode(f, m)
    \/ \E f \in Server : LearnerApplySnapshot(f)
    \/ \E f \in Server : LearnerTruncateLog(f)
    \/ \E f \in Server : \E t \in Txn : LearnerSyncPacket(f, t)
    \/ \E f \in Server : LearnerSyncCommit(f)
    \/ \E f \in Server : LearnerSyncSnapshot(f)
    \/ \E f \in Server : LearnerPersistCurrentEpoch(f)
    \/ \E f \in Server : LearnerNewLeaderModeNone(f)
    \/ \E f \in Server : LearnerAckNewLeader(f)
    \/ \E l \in Server : FormNewLeaderQuorum(l)
    \/ \E l \in Server : LeaderEnterBroadcast(l)
    \/ \E f \in Server : LearnerUpToDate(f)
    \/ \E f \in Server : CompleteLearnerSync(f)
    \/ \E f \in Server : FollowerEnterBroadcast(f)
    \/ \E l \in Server : nextTxn \in Txn /\ LeaderPropose(l, nextTxn)
    \/ \E f \in Server : \E t \in Txn : FollowerPendingProposal(f, t)
    \/ \E s \in Server : \E t \in Txn : QueueForSync(s, t)
    \/ \E s \in Server : \E t \in Txn : FlushTxnLog(s, t)
    \/ \E l, src \in Server : \E t \in Txn : RecordProposalAck(l, src, t)
    \/ \E l \in Server : \E t \in Txn : CommitProposal(l, t)
    \/ \E f \in Server : \E t \in Txn : FollowerCommit(f, t)
    \/ \E s \in Server : \E t \in Txn : ApplyTxn(s, t)
    \/ \E s \in Server : BeginSnapshot(s) \/ FinishSnapshot(s)
    \/ \E s \in Server : Crash(s)
    \/ \E s \in Server : RestartLoadDatabase(s, acceptedEpoch[s], currentEpoch[s])
    \/ \E f \in Server : LearnerShutdown(f) \/ FollowerExitToLooking(f)
    \/ \E l \in Server : LeaderShutdown(l)
    \/ \E s \in Server : EnterElectionPhase(s) \/ ReloadDatabase(s)

Spec == Init /\ [][Next]_vars

\* base.cfg bound (state constraint) for the unbounded reference relation.
BaseConstraint == electionRound <= 1

-----------------------------------------------------------------------------
(* Properties                                                              *)
-----------------------------------------------------------------------------

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
    /\ logPos \in [Server -> Nat]
    /\ \A s \in Server : logPos[s] <= Len(prepared[s])
    /\ syncQueued \in [Server -> Seq(Txn)]
    /\ pending \in [Server -> Seq(Txn)]
    /\ durable \in [Server -> Seq(Txn)]
    /\ memDb \in [Server -> Seq(Txn)]
    /\ memInit \in [Server -> BOOLEAN]
    /\ \A s \in Server : ~memInit[s] => memDb[s] = <<>>
    /\ syncStage \in [Server -> Stages]
    /\ syncBuf \in [Server -> Seq(Txn)]
    /\ syncCommits \in [Server -> Seq(Txn)]
    /\ syncPos \in [Server -> TxnOrNone]
    /\ syncCut \in [Server -> TxnOrNone]
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
    /\ snapZ \in [Server -> TxnOrNone]

\* Revised (Case A): ZooKeeper does not prevent a deposed leader from still
\* reporting BROADCAST until its next quorum check (Leader.java:739-780); the
\* promised property is one established leader per epoch.
LeaderUniquenessPerEpoch ==
    \A a, b \in Server :
        /\ a # b
        /\ running[a] /\ role[a] = "LEADING" /\ phase[a] = "BROADCAST"
        /\ running[b] /\ role[b] = "LEADING" /\ phase[b] = "BROADCAST"
        => currentEpoch[a] # currentEpoch[b]

AcceptedEpochGECurrentEpoch == \A s \in Server : acceptedEpoch[s] >= currentEpoch[s]

\* Revised (V0 required dense prefixes of 1..MaxTxn, which cannot represent
\* divergent earlier-epoch proposals): every history is in zxid order and
\* commit/apply records are prefixes of the global commit order.
OrderedHistories ==
    /\ Ordered(globalCommitted)
    /\ \A s \in Server :
        /\ Ordered(prepared[s])
        /\ Ordered(syncQueued[s])
        /\ Ordered(pending[s])
        /\ Ordered(durable[s])
        /\ Ordered(memDb[s])
        /\ Ordered(syncBuf[s])
        /\ PrefixOf(committed[s], globalCommitted)
        /\ PrefixOf(applied[s], committed[s])

CommittedPrefixAgreement ==
    \A a, b \in Server : PrefixOf(committed[a], committed[b]) \/ PrefixOf(committed[b], committed[a])

NormalAckHasDurabilityEvidence == \A t \in Txn : acks[t] \subseteq durabilityEvidence[t]

ApplyHasCommitCertificate ==
    \A s \in Server : \A t \in Elems(applied[s]) : Quorum(commitWitness[t])

\* A broadcasting leader/follower completed its synchronization. Exit windows
\* are exempt: Learner.shutdown -> updateServerState (syncStage EXITED,
\* QuorumPeer.java:1476-1478) and setPeerState(LOOKING) before the nested
\* setZabState(ELECTION) (QuorumPeer.java:852-858); neither serves.
SyncEntryJustified ==
    \A s \in Server :
        running[s] /\ phase[s] = "BROADCAST" /\ syncStage[s] # "EXITED"
        /\ role[s] \in {"LEADING", "FOLLOWING"}
        => IF role[s] = "LEADING" THEN newLeaderReady[s] ELSE syncComplete[s]

SnapshotPublishedValid ==
    \A s \in Server : PrefixOf(snapshotPublished[s], applied[s])

\* New reference property (recovered histories are mutually consistent):
\* what a restart would replay from disk equals the global commit order up
\* to the last committed record it contains -- no committed hole and no
\* never-committed record below a committed one.
DurableHistoryConsistent ==
    \A s \in Server :
        LET d == durable[s]
            idx == {i \in 1..Len(d) : d[i] \in Elems(globalCommitted)}
            k == IF idx = {} THEN 0 ELSE SetMax(idx)
        IN k <= Len(globalCommitted)
           /\ SubSeq(d, 1, k) = SubSeq(globalCommitted, 1, k)

\* New reference property: an established leader's history contains every
\* globally committed transaction (Zab leader completeness).
LeaderCompleteness ==
    \A l \in Server :
        running[l] /\ role[l] = "LEADING" /\ newLeaderReady[l]
        => Elems(globalCommitted) \subseteq Elems(prepared[l])

\* Revised action property: durable/commit/apply frontiers only move back on
\* explicit, source-authorized steps (TRUNC log cut; SNAP/TRUNC snapshot at
\* NEWLEADER). Restart replays disk and is not a retraction of `durable`.
MonotoneStep ==
    \/ \E f \in Server : syncStage[f] = "MODE" /\ syncStage'[f] = "DATA"
    \/ \E f \in Server : syncStage[f] = "DATA" /\ syncStage'[f] = "SNAPPED"
    \/ /\ \A s \in Server : Len(durable'[s]) >= Len(durable[s])
       /\ \A s \in Server : PrefixOf(committed[s], committed'[s])
       /\ \A s \in Server : PrefixOf(applied[s], applied'[s])
       /\ PrefixOf(globalCommitted, globalCommitted')

MonotoneUnlessRecovery == [][MonotoneStep]_vars

=============================================================================
