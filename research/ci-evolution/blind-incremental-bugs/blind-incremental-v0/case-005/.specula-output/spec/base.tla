------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* Code-faithful Specula V0 prior for ZooKeeper's exact-old Zab subsystem. *)
(* Source citations identify the implementation boundary represented by     *)
(* each action. This is an executable abstraction, not a proof of ZooKeeper. *)
(***************************************************************************)
EXTENDS Integers, FiniteSets, Sequences, TLC

CONSTANTS Server, Voters, Observers, Txn, TxnEpoch, MaxEpoch, NoNode, NoTxn

ASSUME Voters \subseteq Server
ASSUME Observers = Server \ Voters
ASSUME Txn \subseteq (Int \ {NoTxn})
ASSUME NoNode \notin Server
ASSUME Txn \subseteq DOMAIN TxnEpoch
ASSUME \A t \in Txn : TxnEpoch[t] \in 0..MaxEpoch

Roles == {"DOWN", "LOOKING", "FOLLOWING", "OBSERVING", "LEADING"}
Modes == {"NONE", "DIFF", "TRUNC", "SNAP"}

VARIABLES
    up, role, leaderOf, acceptedEpoch, currentEpoch,
    durableAccepted, durableCurrent,
    epochSupport, epochAcks, supportAtAccepted,
    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate,
    queuedLog, volatileLog, durableLog, committedLog, appliedLog,
    snapshotLog, snapshotZxid, proposedBy, ackers, globalCommitted,
    broadcastReady, lastAction

vars == <<up, role, leaderOf, acceptedEpoch, currentEpoch,
          durableAccepted, durableCurrent,
          epochSupport, epochAcks, supportAtAccepted,
          newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate,
          queuedLog, volatileLog, durableLog, committedLog, appliedLog,
          snapshotLog, snapshotZxid, proposedBy, ackers, globalCommitted,
          broadcastReady, lastAction>>

stateVars == <<up, role, leaderOf, acceptedEpoch, currentEpoch,
               durableAccepted, durableCurrent,
               epochSupport, epochAcks, supportAtAccepted,
               newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate,
               queuedLog, volatileLog, durableLog, committedLog, appliedLog,
               snapshotLog, snapshotZxid, proposedBy, ackers, globalCommitted,
               broadcastReady>>

Observe(name) == /\ lastAction' = name /\ UNCHANGED stateVars

VotingQuorum(S) == Cardinality(S \cap Voters) > Cardinality(Voters) \div 2

(* Leader.getEpochToPropose/waitForEpochAck use QuorumVerifier.containsQuorum
   on raw connecting/electing learner ids (Leader.java:1168-1235). *)
RawEpochQuorum(S) == Cardinality(S) > Cardinality(Voters) \div 2

StableAt(i) == durableLog[i] \cup snapshotLog[i]
(* TLC's integer implementation cannot arithmetically decode every native
   64-bit zxid retained in NDJSON.  The model therefore receives the exact
   zxid-to-epoch projection as a constant; Trace derives it from Proposal
   events, while finite MC configurations derive it from compact zxids. *)
ModelTxnEpoch == [t \in Txn |-> t \div 100]
ZxidEpoch(z) == IF z = NoTxn THEN 0 ELSE TxnEpoch[z]
MaxOrZero(S) == IF S = {} THEN NoTxn ELSE CHOOSE x \in S : \A y \in S : y <= x
PrefixClosed(S) == \A t \in S : \A u \in Txn : u < t => u \in S

Init ==
    /\ up = [i \in Server |-> FALSE]
    /\ role = [i \in Server |-> "DOWN"]
    /\ leaderOf = [i \in Server |-> NoNode]
    /\ acceptedEpoch = [i \in Server |-> 0]
    /\ currentEpoch = [i \in Server |-> 0]
    /\ durableAccepted = [i \in Server |-> 0]
    /\ durableCurrent = [i \in Server |-> 0]
    /\ epochSupport = [i \in Server |-> {}]
    /\ epochAcks = [i \in Server |-> {}]
    /\ supportAtAccepted = [i \in Server |-> {}]
    /\ newLeaderAcks = [i \in Server |-> {}]
    /\ syncMode = [i \in Server |-> "NONE"]
    /\ syncTarget = [i \in Server |-> NoTxn]
    /\ syncApplied = {}
    /\ upToDate = {}
    /\ queuedLog = [i \in Server |-> {}]
    /\ volatileLog = [i \in Server |-> {}]
    /\ durableLog = [i \in Server |-> {}]
    /\ committedLog = [i \in Server |-> {}]
    /\ appliedLog = [i \in Server |-> {}]
    /\ snapshotLog = [i \in Server |-> {}]
    /\ snapshotZxid = [i \in Server |-> NoTxn]
    /\ proposedBy = [t \in Txn |-> NoNode]
    /\ ackers = [t \in Txn |-> {}]
    /\ globalCommitted = {}
    /\ broadcastReady = {}
    /\ lastAction = "Init"

(* QuorumPeer.start/loadDataBase and FileTxnSnapLog.restore replay stable data:
   QuorumPeer.java:768-824; FileTxnSnapLog.java:175-245. *)
StartServer(i) ==
    /\ i \in Server /\ ~up[i]
    /\ up' = [up EXCEPT ![i] = TRUE]
    /\ role' = [role EXCEPT ![i] = "LOOKING"]
    /\ leaderOf' = [leaderOf EXCEPT ![i] = NoNode]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![i] = durableAccepted[i]]
    /\ currentEpoch' = [currentEpoch EXCEPT ![i] = durableCurrent[i]]
    /\ queuedLog' = [queuedLog EXCEPT ![i] = StableAt(i)]
    /\ volatileLog' = [volatileLog EXCEPT ![i] = StableAt(i)]
    (* Restore exposes txn-log records for recovery, but only a snapshot is a
       committed/applied prefix before leader synchronization justifies the
       remaining durable records: FileTxnSnapLog.java:175-245;
       Learner.java:358-398. *)
    /\ committedLog' = [committedLog EXCEPT
                          ![i] = StableAt(i) \cap globalCommitted]
    /\ appliedLog' = [appliedLog EXCEPT
                        ![i] = StableAt(i) \cap globalCommitted]
    /\ broadcastReady' = broadcastReady \ {i}
    /\ syncMode' = [syncMode EXCEPT ![i] = "NONE"]
    /\ syncTarget' = [syncTarget EXCEPT ![i] = NoTxn]
    /\ syncApplied' = syncApplied \ {i}
    /\ epochSupport' = [epochSupport EXCEPT ![i] = {}]
    /\ epochAcks' = [epochAcks EXCEPT ![i] = {}]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![i] = {}]
    /\ lastAction' = "StartServer"
    /\ UNCHANGED <<durableAccepted, durableCurrent, supportAtAccepted,
                    upToDate, durableLog, snapshotLog, snapshotZxid,
                    proposedBy, ackers, globalCommitted>>

(* FastLeaderElection total-order/quorum decision: FastLeaderElection.java:707-755,870-1058. *)
ElectionDecision(i, l, e, electedRole) ==
    /\ i \in Server /\ l \in Server /\ up[i]
    /\ role[i] = "LOOKING"
    /\ electedRole \in {"FOLLOWING", "OBSERVING", "LEADING"}
    /\ e \in 0..MaxEpoch
    /\ <<role[i], leaderOf[i], currentEpoch[i]>> # <<electedRole, l, e>>
    /\ electedRole # "LEADING" \/
       {j \in Server : up[j] /\ role[j] = "LEADING" /\ currentEpoch[j] = e} \subseteq {i}
    /\ role' = [role EXCEPT ![i] = electedRole]
    /\ leaderOf' = [leaderOf EXCEPT ![i] = l]
    /\ lastAction' = "ElectionDecision"
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, durableAccepted, durableCurrent,
                    epochSupport, epochAcks, supportAtAccepted, newLeaderAcks,
                    syncMode, syncTarget, syncApplied, upToDate, queuedLog, volatileLog,
                    durableLog, committedLog, appliedLog, snapshotLog,
                    snapshotZxid, proposedBy, ackers, globalCommitted,
                    broadcastReady>>

ReceiveEpochSupport(l, f) ==
    /\ l \in Server /\ f \in Server /\ up[l] /\ role[l] = "LEADING"
    /\ l \notin broadcastReady
    /\ epochSupport' = [epochSupport EXCEPT ![l] = @ \cup {f}]
    /\ lastAction' = "ReceiveEpochSupport"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate, queuedLog,
                    volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

LeaderAcceptedEpochMemory(l, e) ==
    /\ l \in Server /\ up[l] /\ role[l] = "LEADING"
    /\ l \notin broadcastReady
    /\ l \in epochSupport[l]
    /\ RawEpochQuorum(epochSupport[l])
    /\ e \in 1..MaxEpoch /\ e > acceptedEpoch[l]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![l] = e]
    /\ supportAtAccepted' = [supportAtAccepted EXCEPT ![l] = epochSupport[l]]
    /\ lastAction' = "LeaderAcceptedEpochMemory"
    /\ UNCHANGED <<up, role, leaderOf, currentEpoch, durableAccepted,
                    durableCurrent, epochSupport, epochAcks, newLeaderAcks,
                    syncMode, syncTarget, syncApplied, upToDate, queuedLog, volatileLog,
                    durableLog, committedLog, appliedLog, snapshotLog,
                    snapshotZxid, proposedBy, ackers, globalCommitted,
                    broadcastReady>>

LearnerAcceptedEpochMemory(i, e) ==
    /\ i \in Server /\ up[i] /\ role[i] \in {"FOLLOWING", "OBSERVING"}
    /\ i \notin broadcastReady
    /\ e \in 1..MaxEpoch /\ e > acceptedEpoch[i]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![i] = e]
    /\ lastAction' = "LearnerAcceptedEpochMemory"
    /\ UNCHANGED <<up, role, leaderOf, currentEpoch, durableAccepted,
                    durableCurrent, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate, queuedLog,
                    volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

PersistAcceptedEpoch(i) ==
    /\ i \in Server /\ up[i]
    /\ durableAccepted[i] # acceptedEpoch[i]
    /\ durableAccepted' = [durableAccepted EXCEPT ![i] = acceptedEpoch[i]]
    /\ lastAction' = "PersistAcceptedEpoch"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableCurrent, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate, queuedLog,
                    volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

RecordEpochAck(l, f) ==
    /\ l \in Server /\ f \in Server /\ up[l] /\ role[l] = "LEADING"
    /\ l \notin broadcastReady
    /\ f \notin epochAcks[l]
    /\ epochAcks' = [epochAcks EXCEPT ![l] = @ \cup {f}]
    /\ lastAction' = "RecordEpochAck"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, committedLog,
                    appliedLog, snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

CurrentEpochMemory(i, e) ==
    /\ i \in Server /\ up[i] /\ e \in 1..MaxEpoch
    /\ i \notin broadcastReady
    /\ e = acceptedEpoch[i] /\ e = durableAccepted[i]
    /\ e >= currentEpoch[i]
    /\ role[i] # "LEADING" \/ RawEpochQuorum(epochAcks[i])
    /\ currentEpoch' = [currentEpoch EXCEPT ![i] = e]
    /\ lastAction' = "CurrentEpochMemory"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, durableAccepted,
                    durableCurrent, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate, queuedLog,
                    volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

PersistCurrentEpoch(i) ==
    /\ i \in Server /\ up[i]
    /\ durableCurrent' = [durableCurrent EXCEPT ![i] = currentEpoch[i]]
    /\ lastAction' = "PersistCurrentEpoch"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate, queuedLog,
                    volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

(* LearnerHandler sync choice DIFF/TRUNC/SNAP: LearnerHandler.java:658-895. *)
SelectSync(l, f, mode, target) ==
    /\ l \in Server /\ f \in Server /\ up[l] /\ up[f]
    /\ f \notin broadcastReady
    /\ l # f /\ role[f] \in {"FOLLOWING", "OBSERVING"}
    /\ role[l] = "LEADING" /\ mode \in {"DIFF", "TRUNC", "SNAP"}
    /\ syncMode[f] = "NONE"
    /\ target \in Txn \cup {NoTxn}
    /\ (mode # "DIFF" \/ StableAt(f) \subseteq globalCommitted)
    /\ (mode # "TRUNC" \/ target = NoTxn \/ target \in globalCommitted)
    /\ (target = NoTxn \/ ZxidEpoch(target) <= acceptedEpoch[l])
    /\ syncMode' = [syncMode EXCEPT ![f] = mode]
    /\ syncTarget' = [syncTarget EXCEPT ![f] = target]
    /\ leaderOf' = [leaderOf EXCEPT ![f] = l]
    /\ lastAction' = "SelectSync"
    /\ UNCHANGED <<up, role, acceptedEpoch, currentEpoch, durableAccepted,
                    durableCurrent, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncApplied, upToDate, queuedLog, volatileLog, durableLog,
                    committedLog, appliedLog, snapshotLog, snapshotZxid,
                    proposedBy, ackers, globalCommitted, broadcastReady>>

ApplySync(i, l, mode, target) ==
    /\ i \in Server /\ l \in Server /\ up[i] /\ up[l]
    /\ i # l /\ role[l] = "LEADING"
    /\ i \notin syncApplied
    /\ syncMode[i] = mode /\ syncTarget[i] = target
    /\ mode \in {"DIFF", "TRUNC", "SNAP"}
    /\ queuedLog' = [queuedLog EXCEPT ![i] =
            IF mode = "TRUNC" THEN {t \in @ : t <= target}
            ELSE IF mode = "SNAP" THEN appliedLog[l] ELSE @]
    /\ volatileLog' = [volatileLog EXCEPT ![i] =
            IF mode = "TRUNC" THEN {t \in @ : t <= target}
            ELSE IF mode = "SNAP" THEN appliedLog[l] ELSE @]
    /\ durableLog' = [durableLog EXCEPT ![i] =
            IF mode = "TRUNC" THEN {t \in @ : t <= target} ELSE @]
    /\ committedLog' = [committedLog EXCEPT ![i] =
            IF mode = "TRUNC" THEN {t \in StableAt(i) : t <= target}
            ELSE IF mode = "SNAP" THEN appliedLog[l]
            ELSE StableAt(i)]
    /\ appliedLog' = [appliedLog EXCEPT ![i] =
            IF mode = "TRUNC" THEN {t \in StableAt(i) : t <= target}
            ELSE IF mode = "SNAP" THEN appliedLog[l]
            ELSE StableAt(i)]
    /\ syncApplied' = syncApplied \cup {i}
    /\ lastAction' = "ApplySync"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget,
                    upToDate, snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

ReceiveSyncProposal(i, l, t) ==
    /\ i \in Server /\ l \in Server /\ t \in Txn /\ up[i]
    /\ i # l /\ role[l] = "LEADING" /\ syncMode[i] = "DIFF"
    /\ i \in syncApplied
    /\ t \notin queuedLog[i]
    /\ queuedLog' = [queuedLog EXCEPT ![i] = @ \cup {t}]
    /\ volatileLog' = [volatileLog EXCEPT ![i] = @ \cup {t}]
    /\ leaderOf' = [leaderOf EXCEPT ![i] = l]
    /\ lastAction' = "ReceiveSyncProposal"
    /\ UNCHANGED <<up, role, acceptedEpoch, currentEpoch, durableAccepted,
                    durableCurrent, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate, durableLog,
                    committedLog, appliedLog, snapshotLog, snapshotZxid,
                    proposedBy, ackers, globalCommitted, broadcastReady>>

ApplySyncCommit(i, l, t) ==
    /\ i \in Server /\ l \in Server /\ t \in Txn /\ up[i]
    /\ i \in syncApplied
    /\ t \in queuedLog[i] /\ t \in globalCommitted
    /\ committedLog' = [committedLog EXCEPT ![i] = @ \cup {t}]
    /\ appliedLog' = [appliedLog EXCEPT ![i] = @ \cup {t}]
    /\ lastAction' = "ApplySyncCommit"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, snapshotLog,
                    snapshotZxid, proposedBy, ackers, globalCommitted,
                    broadcastReady>>

(* Learner takes a bootstrap snapshot before persisting currentEpoch:
   Learner.java:554-575. *)
BootstrapSnapshot(i, target) ==
    /\ i \in Server /\ up[i] /\ target \in Txn \cup {NoTxn}
    /\ i \in syncApplied
    /\ syncTarget[i] = target
    /\ snapshotLog' = [snapshotLog EXCEPT ![i] = appliedLog[i]]
    /\ snapshotZxid' = [snapshotZxid EXCEPT ![i] = target]
    /\ lastAction' = "BootstrapSnapshot"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, committedLog,
                    appliedLog, proposedBy, ackers, globalCommitted,
                    broadcastReady>>

RecordNewLeaderAck(l, f) ==
    /\ l \in Server /\ f \in Server /\ up[l] /\ role[l] = "LEADING"
    /\ (f = l \/
        /\ up[f] /\ f \in syncApplied /\ leaderOf[f] = l
        /\ durableCurrent[f] = currentEpoch[f]
        /\ currentEpoch[f] = acceptedEpoch[l])
    /\ f \notin newLeaderAcks[l]
    /\ newLeaderAcks' = [newLeaderAcks EXCEPT ![l] = @ \cup {f}]
    /\ lastAction' = "RecordNewLeaderAck"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, syncMode, syncTarget, syncApplied, upToDate, queuedLog,
                    volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

LeaderReady(l) ==
    /\ l \in Server /\ up[l] /\ role[l] = "LEADING"
    /\ durableCurrent[l] = currentEpoch[l]
    /\ currentEpoch[l] = acceptedEpoch[l]
    /\ VotingQuorum(newLeaderAcks[l])
    /\ l \notin broadcastReady
    /\ {j \in broadcastReady : role[j] = "LEADING" /\ currentEpoch[j] = currentEpoch[l]} = {}
    /\ broadcastReady' = broadcastReady \cup {l}
    /\ lastAction' = "LeaderReady"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, committedLog,
                    appliedLog, snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted>>

SendUpToDate(l, f) ==
    /\ l \in Server /\ f \in Server /\ l \in broadcastReady /\ up[f]
    /\ f \in syncApplied
    /\ <<l, f>> \notin upToDate
    /\ upToDate' = upToDate \cup {<<l, f>>}
    /\ lastAction' = "SendUpToDate"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    queuedLog, volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

FollowerReady(i, l) ==
    /\ i \in Server /\ l \in Server /\ up[i] /\ <<l, i>> \in upToDate
    /\ i \in syncApplied
    /\ durableCurrent[i] = durableAccepted[i]
    /\ i \notin broadcastReady
    /\ broadcastReady' = broadcastReady \cup {i}
    /\ lastAction' = "FollowerReady"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, committedLog,
                    appliedLog, snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted>>

(* Leader proposal and independent persistence/ack/commit/apply processors:
   Leader.java:716-864,1036-1085; SyncRequestProcessor.java:98-188;
   FinalRequestProcessor.java:89-129. *)
Propose(l, t) ==
    /\ l \in Server /\ t \in Txn /\ l \in broadcastReady
    /\ role[l] = "LEADING" /\ proposedBy[t] = NoNode
    /\ \A u \in Txn : u < t => proposedBy[u] # NoNode
    /\ proposedBy' = [proposedBy EXCEPT ![t] = l]
    /\ queuedLog' = [queuedLog EXCEPT ![l] = @ \cup {t}]
    /\ lastAction' = "Propose"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, volatileLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, ackers, globalCommitted,
                    broadcastReady>>

ReceiveProposal(i, l, t) ==
    /\ i \in Server /\ l \in Server /\ t \in Txn /\ up[i]
    /\ i \in broadcastReady /\ l \in broadcastReady
    /\ role[i] \in {"FOLLOWING", "OBSERVING"} /\ role[l] = "LEADING"
    /\ proposedBy[t] = l
    /\ t \notin queuedLog[i]
    /\ queuedLog' = [queuedLog EXCEPT ![i] = @ \cup {t}]
    /\ leaderOf' = [leaderOf EXCEPT ![i] = l]
    /\ lastAction' = "ReceiveProposal"
    /\ UNCHANGED <<up, role, acceptedEpoch, currentEpoch, durableAccepted,
                    durableCurrent, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, syncApplied, upToDate, volatileLog,
                    durableLog, committedLog, appliedLog, snapshotLog,
                    snapshotZxid, proposedBy, ackers, globalCommitted,
                    broadcastReady>>

AppendLog(i, t) ==
    /\ i \in Server /\ t \in Txn /\ up[i] /\ i \in broadcastReady
    /\ t \in queuedLog[i]
    /\ t \notin volatileLog[i]
    /\ volatileLog' = [volatileLog EXCEPT ![i] = @ \cup {t}]
    /\ lastAction' = "AppendLog"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, durableLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

ForceLog(i, t) ==
    /\ i \in Server /\ t \in Txn /\ up[i] /\ i \in broadcastReady
    /\ t \in volatileLog[i]
    /\ t \notin durableLog[i]
    /\ durableLog' = [durableLog EXCEPT ![i] = @ \cup {t}]
    /\ lastAction' = "ForceLog"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, committedLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

ReceiveAck(l, f, t) ==
    /\ l \in Server /\ f \in Server /\ t \in Txn
    /\ up[l] /\ role[l] = "LEADING" /\ l \in broadcastReady
    /\ proposedBy[t] = l
    /\ t \in StableAt(f)
    /\ f \notin ackers[t]
    /\ ackers' = [ackers EXCEPT ![t] = @ \cup ({f} \cap Voters)]
    /\ lastAction' = "ReceiveAck"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, committedLog,
                    appliedLog, snapshotLog, snapshotZxid, proposedBy,
                    globalCommitted, broadcastReady>>

CommitAtLeader(l, t) ==
    /\ l \in Server /\ t \in Txn /\ up[l] /\ role[l] = "LEADING"
    /\ l \in broadcastReady
    /\ proposedBy[t] = l /\ VotingQuorum(ackers[t])
    /\ t \notin globalCommitted
    /\ \A u \in Txn : u < t /\ proposedBy[u] # NoNode => u \in globalCommitted
    /\ globalCommitted' = globalCommitted \cup {t}
    /\ committedLog' = [committedLog EXCEPT ![l] = @ \cup {t}]
    /\ lastAction' = "CommitAtLeader"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    broadcastReady>>

ReceiveCommit(i, l, t) ==
    /\ i \in Server /\ l \in Server /\ t \in Txn /\ up[i]
    /\ i \in broadcastReady /\ l \in broadcastReady
    /\ t \in globalCommitted /\ proposedBy[t] = l
    /\ t \notin committedLog[i]
    /\ committedLog' = [committedLog EXCEPT ![i] = @ \cup {t}]
    /\ lastAction' = "ReceiveCommit"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, appliedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

ApplyTxn(i, t) ==
    /\ i \in Server /\ t \in Txn /\ up[i] /\ t \in committedLog[i]
    /\ t \notin appliedLog[i]
    /\ appliedLog' = [appliedLog EXCEPT ![i] = @ \cup {t}]
    /\ lastAction' = "ApplyTxn"
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    durableAccepted, durableCurrent, epochSupport, epochAcks,
                    supportAtAccepted, newLeaderAcks, syncMode, syncTarget, syncApplied,
                    upToDate, queuedLog, volatileLog, durableLog, committedLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted, broadcastReady>>

(* QuorumPeer shutdown and process loss preserve only files/snapshots:
   QuorumPeer.java:1137-1160; SyncRequestProcessor.java:190-209. *)
Crash(i) ==
    /\ i \in Server /\ up[i]
    /\ up' = [up EXCEPT ![i] = FALSE]
    /\ role' = [role EXCEPT ![i] = "DOWN"]
    /\ leaderOf' = [leaderOf EXCEPT ![i] = NoNode]
    /\ broadcastReady' = broadcastReady \ {i}
    /\ queuedLog' = [queuedLog EXCEPT ![i] = {}]
    /\ volatileLog' = [volatileLog EXCEPT ![i] = {}]
    /\ committedLog' = [committedLog EXCEPT ![i] = {}]
    /\ appliedLog' = [appliedLog EXCEPT ![i] = {}]
    /\ syncApplied' = syncApplied \ {i}
    /\ upToDate' = {p \in upToDate : p[1] # i /\ p[2] # i}
    /\ lastAction' = "Crash"
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, durableAccepted,
                    durableCurrent, epochSupport, epochAcks, supportAtAccepted,
                    newLeaderAcks, syncMode, syncTarget, durableLog,
                    snapshotLog, snapshotZxid, proposedBy, ackers,
                    globalCommitted>>

NormalNext ==
    \/ \E i \in Server, l \in Server, e \in 0..MaxEpoch,
          r \in {"FOLLOWING", "OBSERVING", "LEADING"} : ElectionDecision(i,l,e,r)
    \/ \E l \in Server, f \in Server : ReceiveEpochSupport(l,f)
    \/ \E l \in Server, e \in 1..MaxEpoch : LeaderAcceptedEpochMemory(l,e)
    \/ \E i \in Server, e \in 1..MaxEpoch : LearnerAcceptedEpochMemory(i,e)
    \/ \E i \in Server : PersistAcceptedEpoch(i)
    \/ \E l \in Server, f \in Server : RecordEpochAck(l,f)
    \/ \E i \in Server, e \in 1..MaxEpoch : CurrentEpochMemory(i,e)
    \/ \E i \in Server : PersistCurrentEpoch(i)
    \/ \E l \in Server, f \in Server, m \in {"DIFF","TRUNC","SNAP"},
          t \in Txn \cup {NoTxn} : SelectSync(l,f,m,t)
    \/ \E i \in Server, l \in Server, m \in {"DIFF","TRUNC","SNAP"},
          t \in Txn \cup {NoTxn} : ApplySync(i,l,m,t)
    \/ \E i \in Server, l \in Server, t \in Txn : ReceiveSyncProposal(i,l,t)
    \/ \E i \in Server, l \in Server, t \in Txn : ApplySyncCommit(i,l,t)
    \/ \E i \in Server, t \in Txn \cup {NoTxn} : BootstrapSnapshot(i,t)
    \/ \E l \in Server, f \in Server : RecordNewLeaderAck(l,f)
    \/ \E l \in Server : LeaderReady(l)
    \/ \E l \in Server, f \in Server : SendUpToDate(l,f)
    \/ \E i \in Server, l \in Server : FollowerReady(i,l)
    \/ \E i \in Server, l \in Server, t \in Txn : ReceiveProposal(i,l,t)
    \/ \E i \in Server, t \in Txn : AppendLog(i,t)
    \/ \E i \in Server, t \in Txn : ForceLog(i,t)
    \/ \E l \in Server, f \in Server, t \in Txn : ReceiveAck(l,f,t)
    \/ \E l \in Server, t \in Txn : CommitAtLeader(l,t)
    \/ \E i \in Server, l \in Server, t \in Txn : ReceiveCommit(i,l,t)
    \/ \E i \in Server, t \in Txn : ApplyTxn(i,t)

Spec == Init /\ [][NormalNext \/ (\E i \in Server : StartServer(i))
                         \/ (\E l \in Server, t \in Txn : Propose(l,t))
                         \/ (\E i \in Server : Crash(i))]_vars

(* Canonical base BFS covers ordinary election/sync/broadcast without injected
   crash; bounded crash/restart is exercised by canonical MC and the trace
   suite.  The full Spec above remains the broader fault-inclusive behavior. *)
CanonicalBaseSpec ==
    Init /\ [][NormalNext
               \/ (\E i \in Server : StartServer(i))
               \/ (\E l \in Server, t \in Txn : Propose(l,t))]_vars

TypeOK ==
    /\ up \in [Server -> BOOLEAN]
    /\ role \in [Server -> Roles]
    /\ leaderOf \in [Server -> Server \cup {NoNode}]
    /\ acceptedEpoch \in [Server -> 0..MaxEpoch]
    /\ currentEpoch \in [Server -> 0..MaxEpoch]
    /\ durableAccepted \in [Server -> 0..MaxEpoch]
    /\ durableCurrent \in [Server -> 0..MaxEpoch]
    /\ epochSupport \in [Server -> SUBSET Server]
    /\ epochAcks \in [Server -> SUBSET Server]
    /\ supportAtAccepted \in [Server -> SUBSET Server]
    /\ newLeaderAcks \in [Server -> SUBSET Server]
    /\ syncMode \in [Server -> Modes]
    /\ syncTarget \in [Server -> Txn \cup {NoTxn}]
    /\ syncApplied \subseteq Server
    /\ upToDate \subseteq (Server \X Server)
    /\ queuedLog \in [Server -> SUBSET Txn]
    /\ volatileLog \in [Server -> SUBSET Txn]
    /\ durableLog \in [Server -> SUBSET Txn]
    /\ committedLog \in [Server -> SUBSET Txn]
    /\ appliedLog \in [Server -> SUBSET Txn]
    /\ snapshotLog \in [Server -> SUBSET Txn]
    /\ snapshotZxid \in [Server -> Txn \cup {NoTxn}]
    /\ proposedBy \in [Txn -> Server \cup {NoNode}]
    /\ ackers \in [Txn -> SUBSET Voters]
    /\ globalCommitted \subseteq Txn
    /\ broadcastReady \subseteq Server

EpochConsistency ==
    \A i \in Server :
        /\ currentEpoch[i] <= acceptedEpoch[i]
        /\ durableCurrent[i] <= durableAccepted[i]
        /\ durableAccepted[i] <= acceptedEpoch[i]

PipelineOrdering ==
    \A i \in Server :
        /\ up[i] => volatileLog[i] \subseteq queuedLog[i]
        (* SNAP deserializes replacement state before takeSnapshot persists it;
           the old txn log remains the explicit crash-recovery fallback during
           that window: Learner.java:358-398,486-525. *)
        /\ (up[i] /\ ~(syncMode[i] = "SNAP" /\ i \in syncApplied))
           => durableLog[i] \subseteq volatileLog[i] \cup snapshotLog[i]
        /\ appliedLog[i] \subseteq committedLog[i]

GlobalCommitHasVotingDurability ==
    \A t \in globalCommitted : VotingQuorum({i \in Voters : t \in StableAt(i)})

CommittedHistoriesArePrefixes ==
    \A i,j \in Server :
         committedLog[i] \subseteq committedLog[j] \/ committedLog[j] \subseteq committedLog[i]

SingleReadyLeaderPerEpoch ==
    \A e \in 0..MaxEpoch :
      Cardinality({i \in broadcastReady : role[i] = "LEADING" /\ currentEpoch[i] = e}) <= 1

ServingEpochDurable ==
    \A i \in broadcastReady : durableCurrent[i] = currentEpoch[i]

AppliedWasGloballyCommitted ==
    \A i \in Server : appliedLog[i] \subseteq globalCommitted

ServingHistoryCommitted ==
    \A i \in broadcastReady : appliedLog[i] \subseteq globalCommitted

EpochAdvanceHasVotingQuorum ==
    \A i \in Server : supportAtAccepted[i] = {} \/ VotingQuorum(supportAtAccepted[i])

RecoverableEpochState ==
    \A i \in Server : up[i] \/ snapshotZxid[i] = NoTxn
                      \/ ZxidEpoch(snapshotZxid[i]) <= durableCurrent[i]

SnapshotReflectsApplied == \A i \in Server : snapshotLog[i] \subseteq appliedLog[i] \cup StableAt(i)

StateConstraint == TRUE

=============================================================================
