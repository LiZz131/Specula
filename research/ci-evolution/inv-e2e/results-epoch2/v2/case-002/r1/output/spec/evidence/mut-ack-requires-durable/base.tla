------------------------------ MODULE base ------------------------------
(***************************************************************************)
(* ZooKeeper Zab reference model, revision `update` (case-002).            *)
(*                                                                         *)
(* Source root for annotations: zookeeper-server/src/main/java/org/apache/ *)
(* zookeeper/server/ (abbreviated below as `server/`).                     *)
(*                                                                         *)
(* The update moved learner request-processor startup and the hand-off of  *)
(* buffered DIFF/outstanding proposals to `FollowerZooKeeperServer.        *)
(* logRequest` in front of the NEWLEADER ACK (quorum/Learner.java:748-760),*)
(* and split `ZooKeeperServer.startup` into `startupWithoutServing` (state *)
(* INITIAL) and `startServing` (state RUNNING) (ZooKeeperServer.java:      *)
(* 669-704).  The changed follower synchronization path is now modeled as  *)
(*   SelectSync -> CompleteSync -> PersistCurrentEpoch -> ClearSyncMode    *)
(*   -> LogSyncProposal* -> AckNewLeader -> (leader CountNewLeaderAck,     *)
(*   LeaderBroadcast) -> ReceiveUpToDate -> LogSyncProposal*/ObserveCommit *)
(*   -> EnterBroadcast                                                     *)
(* with append/fsync remaining on the independent SyncRequestProcessor     *)
(* thread (AppendOne/FsyncOne).  See Update.tla for the update focus.      *)
(***************************************************************************)
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

CONSTANTS Server, Txn, MaxEpoch, Nil

ASSUME /\ Server /= {}
       /\ Txn /= {}
       /\ MaxEpoch \in Nat \ {0}
       /\ Nil \notin Server

Role == {"looking", "leading", "following"}
Phase == {"election", "discovery", "sync", "broadcast", "offline"}
SyncModes == {"NONE", "DIFF", "TRUNC", "SNAP"}
\* UPDATE-MAP
\* code: server/ZooKeeperServer.java:669-704 (startup, startupWithoutServing,
\*       startServing, startupWithServerState); ZooKeeperServer.State
\* update: Update!AffectedActions (ClearSyncMode, ReceiveUpToDate)
\* "off": no request processors of the current learner server instance;
\* "initial": processors started, server not serving (State.INITIAL);
\* "running": serving (State.RUNNING).
ZkStates == {"off", "initial", "running"}
Epoch == 0..MaxEpoch
Entry == [id : Txn, epoch : Epoch]
MsgKind == {"proposal", "ack", "commit"}
Message == [kind : MsgKind, from : Server, to : Server,
            id : Txn, epoch : Epoch]

Quorum == (Cardinality(Server) \div 2) + 1

VARIABLES up, role, phase, leaderOf,
          acceptedEpoch, currentEpoch,
          votes, leadersByEpoch,
          proposed, queued, appended, durable, committed, applied,
          snapshot, recovered,
          acked, commitCertified, messages,
          syncMode, syncSource, syncJustified,
          usedTxn, rollbackAuthorized,
          \* UPDATE-MAP
          \* code: quorum/Leader.java:1547-1586 (newLeaderProposal ack set);
          \*       quorum/Learner.java:760 (NEWLEADER ACK write);
          \*       server/ZooKeeperServer.java:669-704 (server state)
          \* update: Update!AffectedActions, Update!UpdNewLeaderAckAfterDurable
          nlAcks,          \* leader: sids whose NEWLEADER ACK was counted
          newLeaderAcked,  \* learner: NEWLEADER ACK written in this sync
          zkState,         \* server lifecycle (ZkStates)
          leaderSummaryEpoch \* leader: currentEpoch in leaderStateSummary

allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot, recovered,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             usedTxn, rollbackAuthorized,
             nlAcks, newLeaderAcked, zkState, leaderSummaryEpoch>>

newLeaderVars == <<nlAcks, newLeaderAcked, zkState, leaderSummaryEpoch>>

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
HasEntry(h, ent) == \E k \in 1..Len(h) : h[k] = ent
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
LastId(h) == IF Len(h) = 0 THEN Nil ELSE h[Len(h)].id

ResetRollback == rollbackAuthorized' = [s \in Server |-> FALSE]

CommonPrefix(a, b) ==
    LET n == IF Len(a) <= Len(b) THEN Len(a) ELSE Len(b)
        k == CHOOSE k \in 0..n : /\ SubSeq(a, 1, k) = SubSeq(b, 1, k)
                                 /\ \A j \in (k + 1)..n : SubSeq(a, 1, j) /= SubSeq(b, 1, j)
    IN SubSeq(a, 1, k)
Longer(a, b) == IF Len(a) >= Len(b) THEN a ELSE b

Init ==
    /\ up = [s \in Server |-> TRUE]
    /\ role = [s \in Server |-> "looking"]
    /\ phase = [s \in Server |-> "election"]
    /\ leaderOf = [s \in Server |-> Nil]
    /\ acceptedEpoch = [s \in Server |-> 0]
    /\ currentEpoch = [s \in Server |-> 0]
    /\ votes = [s \in Server |-> {}]
    /\ leadersByEpoch = [e \in Epoch |-> {}]
    /\ proposed = [s \in Server |-> <<>>]
    /\ queued = [s \in Server |-> <<>>]
    /\ appended = [s \in Server |-> <<>>]
    /\ durable = [s \in Server |-> <<>>]
    /\ committed = [s \in Server |-> <<>>]
    /\ applied = [s \in Server |-> <<>>]
    /\ snapshot = [s \in Server |-> <<>>]
    /\ recovered = [s \in Server |-> <<>>]
    /\ acked = [t \in Txn |-> {}]
    /\ commitCertified = [t \in Txn |-> FALSE]
    /\ messages = {}
    /\ syncMode = [s \in Server |-> "NONE"]
    /\ syncSource = [s \in Server |-> Nil]
    /\ syncJustified = [s \in Server |-> FALSE]
    /\ usedTxn = {}
    /\ rollbackAuthorized = [s \in Server |-> FALSE]
    /\ nlAcks = [s \in Server |-> {}]
    /\ newLeaderAcked = [s \in Server |-> FALSE]
    /\ zkState = [s \in Server |-> "off"]
    /\ leaderSummaryEpoch = [s \in Server |-> 0]

(* FastLeaderElection.lookForLeader: logical round and self vote.          *)
(* QuorumPeer.run (quorum/QuorumPeer.java:1468-1480, 1515-1520): leaving   *)
(* FOLLOWING/LEADING shuts the learner/leader down and returns to LOOKING. *)
(* syncWithLeader's packetsNotCommitted/packetsCommitted are locals         *)
(* (quorum/Learner.java:558-559), so an unlogged learner buffer is lost:    *)
(* proposed is cut back to what was handed to the SyncRequestProcessor.     *)
(* Processors that were already started keep draining (AppendOne/FsyncOne  *)
(* stay enabled); for a server in State.INITIAL the shutdown is skipped    *)
(* entirely (ZooKeeperServer.java:784-786, LearnerZooKeeperServer.java:    *)
(* 155-159).                                                               *)
\* UPDATE-MAP
\* code: server/ZooKeeperServer.java:784-786 (canShutdown), :803-850 (shutdown,
\*       fastForwardDataBase); quorum/LearnerZooKeeperServer.java:155-173;
\*       server/SyncRequestProcessor.java shutdown (drain + flush)
\* update: Update!InteractionActions (BeginElection), Update!UpdLeaderCompleteness
\* A RUNNING server is shut down: its SyncRequestProcessor drains and forces
\* every queued request, then the database is fast-forwarded from the log
\* (recovered := durable).  A server that is not RUNNING -- in particular a
\* learner left in State.INITIAL by a failure between NEWLEADER and UPTODATE
\* (new in `update`) -- skips the whole shutdown: no drain, no fast-forward,
\* and the already started SyncRequestProcessor keeps draining on its own.
BeginElection(s) ==
    /\ up[s]
    /\ acceptedEpoch[s] < MaxEpoch
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ votes' = [votes EXCEPT ![s] = {s}]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ proposed' = [proposed EXCEPT ![s] = queued[s]]
    /\ IF zkState[s] = "running"
       THEN /\ appended' = [appended EXCEPT ![s] = queued[s]]
            /\ durable' = [durable EXCEPT ![s] = queued[s]]
            /\ recovered' = [recovered EXCEPT ![s] = queued[s]]
       ELSE UNCHANGED <<appended, durable, recovered>>
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ newLeaderAcked' = [newLeaderAcked EXCEPT ![s] = FALSE]
    /\ zkState' = [zkState EXCEPT ![s] = "off"]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    queued, committed, applied,
                    snapshot, acked, commitCertified, messages,
                    usedTxn, leaderSummaryEpoch>>
    /\ ResetRollback

(* FLE totalOrderPredicate: epoch, then last zxid, then id.  The zxid in a  *)
(* vote is QuorumPeer.getLastLoggedZxid() = the in-memory database's       *)
(* lastProcessedZxid (quorum/QuorumPeer.java:1257-1262), i.e. `recovered`. *)
(* [repair] V0 compared the durable log length.                           *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ Len(recovered[candidate]) >= Len(recovered[voter])

CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* FLE quorum decision followed by Leader.getEpochToPropose.               *)
(* A new Leader object has an empty newLeaderProposal ack set              *)
(* (quorum/Leader.java:434, 1547-1586).                                    *)
WinElection(candidate) ==
    /\ up[candidate]
    /\ role[candidate] = "looking"
    /\ Cardinality(votes[candidate]) >= Quorum
    /\ acceptedEpoch[candidate] < MaxEpoch
    /\ LET ep == acceptedEpoch[candidate] + 1 IN
       /\ leadersByEpoch[ep] = {}
       /\ role' = [role EXCEPT ![candidate] = "leading"]
       /\ phase' = [phase EXCEPT ![candidate] = "discovery"]
       /\ leaderOf' = [leaderOf EXCEPT ![candidate] = candidate]
       /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![candidate] = ep]
       /\ leadersByEpoch' = [leadersByEpoch EXCEPT ![ep] = {candidate}]
    /\ nlAcks' = [nlAcks EXCEPT ![candidate] = {}]
    \* Leader.lead: leaderStateSummary = (currentEpoch, lastProcessedZxid)
    \* taken before the new epoch is persisted (quorum/Leader.java:592-594).
    /\ leaderSummaryEpoch' = [leaderSummaryEpoch EXCEPT ![candidate] = currentEpoch[candidate]]
    /\ UNCHANGED <<up, currentEpoch, votes, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderAcked, zkState>>
    /\ ResetRollback

(* QuorumPeer main loop switches a LOOKING peer to FOLLOWING after FLE     *)
(* (quorum/QuorumPeer.java:1468-1472); a new Follower/FollowerZooKeeper-   *)
(* Server is created for each FOLLOWING period (QuorumPeer.java:1268-1270).*)
(* [repair] V0 allowed any role to switch directly to FOLLOWING.           *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "looking"
    /\ role[l] = "leading"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ newLeaderAcked' = [newLeaderAcked EXCEPT ![s] = FALSE]
    /\ zkState' = [zkState EXCEPT ![s] = "off"]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn, nlAcks, leaderSummaryEpoch>>
    /\ ResetRollback

(* Learner.registerWithLeader persists acceptedEpoch before ACKEPOCH. *)
AcceptEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "discovery"
    /\ leaderOf[s] \in Server
    /\ acceptedEpoch[s] < acceptedEpoch[leaderOf[s]]
    /\ acceptedEpoch' = [acceptedEpoch EXCEPT ![s] = acceptedEpoch[leaderOf[s]]]
    /\ UNCHANGED <<up, role, phase, leaderOf, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

\* Leader.waitForEpochAck is released by a quorum of epoch acknowledgements
\* (quorum/Leader.java:1440-1476); LearnerHandler threads continue to
\* syncFollower as soon as it returns (LearnerHandler.java:545-550).
EpochAckQuorum(l) ==
    Cardinality({s \in Server : up[s] /\ acceptedEpoch[s] = acceptedEpoch[l]}) >= Quorum

(* Leader.waitForEpochAck completes after a participant quorum. *)
(* Leader.lead: setCurrentEpoch then setZabState(SYNCHRONIZATION)          *)
(* (quorum/Leader.java:658-660).                                           *)
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ EpochAckQuorum(l)
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

\* LearnerHandler.syncFollower compares the learner's reported
\* lastLoggedZxid (its in-memory database) with the leader's committed log.
DiffAllowed(s, l) == IsPrefix(recovered[s], recovered[l])
TruncAllowed(s, l) == IsPrefix(recovered[l], recovered[s])

\* Leader.waitForEpochAck rejects a learner whose ACKEPOCH state summary is
\* more recent than leaderStateSummary (quorum/Leader.java:1447-1454); the
\* LearnerHandler exits and never sends a synchronization directive.
FollowerAhead(s, l) ==
    \/ currentEpoch[s] > leaderSummaryEpoch[l]
    \/ /\ currentEpoch[s] = leaderSummaryEpoch[l]
       /\ Len(recovered[s]) > Len(recovered[l])

(* QuorumPeer exposes SYNCHRONIZATION before the mode packet is consumed  *)
(* (quorum/Follower.java:107-109).  [repair] The learner reaches this     *)
(* point after its own ACKEPOCH (Learner.registerWithLeader), while the   *)
(* leader may still be in DISCOVERY or already BROADCAST (late joiner).   *)
EnterSyncPhase(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ role[l] = "leading"
    /\ phase[s] = "discovery" /\ phase[l] \in {"discovery", "sync", "broadcast"}
    \* Learner.registerWithLeader persists the proposed epoch before the
    \* learner can consume a synchronization directive.
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ syncSource' = [syncSource EXCEPT ![s] = l]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncJustified,
                    usedTxn, newLeaderVars>>
    /\ ResetRollback

(* LearnerHandler.syncFollower chooses DIFF/TRUNC/SNAP under the DB log    *)
(* lock (quorum/LearnerHandler.java:775-933); the learner records it with  *)
(* setSyncMode (quorum/Learner.java:561-600).  [repair] syncFollower runs  *)
(* on the LearnerHandler thread once waitForEpochAck returns, concurrently *)
(* with the leader thread's own SYNCHRONIZATION transition.                *)
SelectSync(s, l, mode) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ role[l] = "leading"
    /\ phase[s] = "sync"
    /\ \/ phase[l] \in {"sync", "broadcast"}
       \/ phase[l] = "discovery" /\ EpochAckQuorum(l)
    /\ syncSource[s] = l
    /\ syncMode[s] = "NONE"
    /\ ~FollowerAhead(s, l)
    /\ mode \in SyncModes \ {"NONE"}
    /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
       ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
       ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ recovered[s] = <<>>
    /\ syncMode' = [syncMode EXCEPT ![s] = mode]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn, newLeaderVars>>
    /\ ResetRollback

(* Learner.syncWithLeader consumes the directive and the packets preceding *)
(* NEWLEADER (quorum/Learner.java:557-725).                                *)
(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:561-565 (DIFF), :616-643 (PROPOSAL/COMMIT     *)
(*       buffered while writeToTxnLog), :739-741 (takeSnapshot SNAP/TRUNC) *)
(* update: Update!AffectedActions (CompleteSync DIFF branch)               *)
(* DIFF: snapshotNeeded=false and writeToTxnLog=true, so every PROPOSAL/   *)
(*   COMMIT is buffered in packetsNotCommitted/packetsCommitted and        *)
(*   nothing is persisted here; `proposed` holds the buffered history.     *)
(*   The learner's previous pipeline must be a prefix of the leader history*)
(*   (it was drained/fast-forwarded by the preceding shutdown, Zoo-        *)
(*   KeeperServer.java:836-850; otherwise the leader would TRUNC/SNAP).    *)
(* TRUNC: truncateLog at the directive (:585-596) and takeSnapshot at      *)
(*   NEWLEADER (:739-741) persist the leader prefix.                       *)
(* SNAP: deserializeSnapshot (:565-583) and takeSnapshot(syncSnapshot=true)*)
(*   at NEWLEADER before setCurrentEpoch.  The model folds the NEWLEADER   *)
(*   snapshot into this step; a crash in between restarts from the        *)
(*   pre-sync state, which is already a model state.                      *)
CompleteSync(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ ~syncJustified[s]
    /\ syncSource[s] \in Server
    /\ syncMode[s] \in SyncModes \ {"NONE"}
    /\ zkState[s] = "off"
    /\ LET l == syncSource[s] IN
       /\ up[l] /\ role[l] = "leading"
       \* The selected sync and NEWLEADER exchange are bound to one epoch;
       \* reusing the same leader identity after restart is not sufficient.
       /\ acceptedEpoch[s] = acceptedEpoch[l]
       \* H: the leader's in-memory history (committed log / data tree) that
       \* syncFollower transfers (LearnerHandler.java:775-933).
       /\ LET H == recovered[l] IN
          IF syncMode[s] = "DIFF"
          THEN \* DIFF payload: the part of H beyond the learner's reported
               \* position, buffered after whatever its log already holds.
               /\ IsPrefix(recovered[s], H)
               /\ IsPrefix(recovered[s], queued[s])
               /\ IsPrefix(committed[s], H)
               /\ proposed' = [proposed EXCEPT ![s] =
                      queued[s] \o SubSeq(H, Len(recovered[s]) + 1, Len(H))]
               /\ UNCHANGED <<queued, appended, durable, committed, applied,
                               snapshot, recovered>>
               /\ ResetRollback
          ELSE \* TRUNC reloads snapshot + truncated log (ZKDatabase.java:599-611);
               \* SNAP installs the leader's tree.  [repair] The learner keeps
               \* its certified prefix inside H, or adopts the leader's certified
               \* prefix if longer (V0 replaced it by the leader's, which could
               \* drop below the learner's own snapshot).
               /\ IsPrefix(committed[l], H)
               /\ IsPrefix(applied[l], H)
               /\ durable' = [durable EXCEPT ![s] = H]
               /\ appended' = [appended EXCEPT ![s] = H]
               /\ queued' = [queued EXCEPT ![s] = H]
               /\ proposed' = [proposed EXCEPT ![s] = H]
               /\ committed' = [committed EXCEPT ![s] =
                      Longer(CommonPrefix(committed[s], H), committed[l])]
               /\ applied' = [applied EXCEPT ![s] =
                      Longer(CommonPrefix(applied[s], H), applied[l])]
               /\ recovered' = [recovered EXCEPT ![s] = H]
               /\ snapshot' = IF syncMode[s] = "SNAP"
                               THEN [snapshot EXCEPT ![s] = applied[l]]
                               ELSE snapshot
               /\ rollbackAuthorized' = [x \in Server |-> x = s]
       /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, acked, commitCertified, messages,
                    syncMode, syncSource, usedTxn, newLeaderVars>>

(* NEWLEADER: self.setCurrentEpoch(newEpoch) (quorum/Learner.java:743),    *)
(* after the SNAP/TRUNC snapshot and before setSyncMode(NONE).             *)
PersistCurrentEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncJustified[s] /\ leaderOf[s] \in Server
    /\ syncMode[s] /= "NONE"
    /\ zkState[s] = "off"
    /\ acceptedEpoch[s] = acceptedEpoch[leaderOf[s]]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:749-751 (setSyncMode(NONE);                   *)
(*       zk.startupWithoutServing()); ZooKeeperServer.java:673-704         *)
(* update: Update!AffectedActions                                          *)
(* New revision: inside NEWLEADER handling, after setCurrentEpoch, the     *)
(* learner clears the sync mode and starts its request processors          *)
(* (SyncRequestProcessor, CommitProcessor) with server state INITIAL.      *)
ClearSyncMode(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncMode[s] /= "NONE"
    /\ syncJustified[s]
    /\ currentEpoch[s] = acceptedEpoch[s]
    /\ zkState[s] = "off"
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ zkState' = [zkState EXCEPT ![s] = "initial"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn, nlAcks, newLeaderAcked, leaderSummaryEpoch>>
    /\ ResetRollback

(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:752-757 (NEWLEADER window) and :777-783       *)
(*       (after UPTODATE); quorum/FollowerZooKeeperServer.java:82-89       *)
(* update: Update!AffectedActions                                          *)
(* fzk.logRequest adds the txn to pendingTxns and enqueues it on the       *)
(* SyncRequestProcessor; it does not append or fsync.  In the new revision *)
(* the packets buffered before NEWLEADER are handed over in the NEWLEADER  *)
(* window (processors INITIAL, before the ACK); packets buffered after the *)
(* ACK are handed over after UPTODATE (processors RUNNING).                *)
LogSyncProposal(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ \/ zkState[s] = "initial" /\ ~newLeaderAcked[s]
       \/ zkState[s] = "running"
    /\ Len(queued[s]) < Len(proposed[s])
    /\ queued' = [queued EXCEPT ![s] = Append(@, proposed[s][Len(queued[s]) + 1])]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:760 writePacket(ACK(newLeaderZxid), true)     *)
(* update: Update!AffectedActions, Update!UpdNewLeaderAckAfterDurable      *)
(* The ACK is written as soon as the logRequest loop returns; nothing waits*)
(* for SyncRequestProcessor.flush (SyncRequestProcessor.java:227-249), so  *)
(* `durable` is not constrained here.                                      *)
AckNewLeader(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ leaderOf[s] \in Server
    /\ syncJustified[s]
    /\ syncMode[s] = "NONE"
    /\ currentEpoch[s] = acceptedEpoch[s]
    /\ zkState[s] = "initial"
    /\ ~newLeaderAcked[s]
    /\ Len(queued[s]) = Len(proposed[s])
    /\ Len(durable[s]) = Len(queued[s])   \* MUTATION: hypothetical ACK-after-fsync
    /\ newLeaderAcked' = [newLeaderAcked EXCEPT ![s] = TRUE]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, nlAcks, zkState, leaderSummaryEpoch>>
    /\ ResetRollback

(* [repair] Leader.waitForNewLeaderAck (quorum/Leader.java:1547-1586) adds *)
(* the sid of a NEWLEADER ACK read first by LearnerHandler (LearnerHandler.*)
(* java:610-623) while quorumFormed is false; Leader.lead calls it for     *)
(* itself after entering SYNCHRONIZATION (Leader.java:660-663).            *)
\* LearnerHandler threads reach waitForNewLeaderAck after their own
\* waitForEpochAck returned, possibly before the leader thread publishes
\* SYNCHRONIZATION; the leader's self-ack follows setZabState(SYNC).
CountNewLeaderAck(l, s) ==
    /\ up[l] /\ role[l] = "leading"
    /\ s \notin nlAcks[l]
    /\ \/ s = l /\ phase[l] = "sync"
       \/ /\ s /= l /\ up[s]
          /\ \/ phase[l] = "sync"
             \/ phase[l] = "discovery" /\ EpochAckQuorum(l)
          /\ role[s] = "following" /\ leaderOf[s] = l
          /\ newLeaderAcked[s]
          /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ nlAcks' = [nlAcks EXCEPT ![l] = @ \cup {s}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderAcked, zkState, leaderSummaryEpoch>>
    /\ ResetRollback

(* [repair] Leader.lead: once newLeaderProposal has a quorum of NEWLEADER  *)
(* ACKs, startZkServer() and setZabState(BROADCAST) (quorum/Leader.java:   *)
(* 660-712, 1497-1535).  The leader then serves its data tree, which holds *)
(* its whole loaded/fast-forwarded log (Leader.java:592 zk.loadData;       *)
(* ZooKeeperServer.java:480-511), i.e. the new leader commits the history  *)
(* it brought into the epoch (zookeeperInternals.md:196-198, 243-249).     *)
(* The data tree equals the log here because the previous role ended with  *)
(* a flushing shutdown and fastForwardDataBase (ZooKeeperServer.java:      *)
(* 836-850), or with a crash and full reload.                              *)
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ l \in nlAcks[l]
    /\ Cardinality(nlAcks[l]) >= Quorum
    /\ IsPrefix(committed[l], recovered[l])
    /\ IsPrefix(applied[l], recovered[l])
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ committed' = [committed EXCEPT ![l] = recovered[l]]
    /\ applied' = [applied EXCEPT ![l] = recovered[l]]
    /\ commitCertified' = [t \in Txn |-> commitCertified[t] \/ t \in TxnIds(recovered[l])]
    \* startZkServer -> zk.startup(): State.RUNNING (ZooKeeperServer.java:669-671)
    /\ zkState' = [zkState EXCEPT ![l] = "running"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, snapshot, recovered, acked,
                    messages, syncMode, syncSource,
                    syncJustified, usedTxn, nlAcks, newLeaderAcked,
                    leaderSummaryEpoch>>
    /\ ResetRollback

(* UPDATE-MAP                                                              *)
(* code: quorum/Learner.java:704-717 (UPTODATE), :765-767 (ACK; zk.start-  *)
(*       Serving()); ZooKeeperServer.java:677-680; LearnerHandler.java:    *)
(*       634-648 (UPTODATE only after learnerMaster.waitForStartup)        *)
(* update: Update!AffectedActions                                          *)
(* startServing exposes the learner's in-memory database: its pre-sync    *)
(* data tree (DIFF; a prefix of the leader history) or the installed       *)
(* leader history (SNAP/TRUNC).  UPTODATE is only sent once the leader is  *)
(* active, so that prefix is certified by the NEWLEADER quorum.            *)
ReceiveUpToDate(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ newLeaderAcked[s]
    /\ zkState[s] = "initial"
    /\ leaderOf[s] \in Server
    /\ LET l == leaderOf[s] IN
       /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
       /\ acceptedEpoch[l] = acceptedEpoch[s]
    /\ LET tree == IF IsPrefix(applied[s], recovered[s]) THEN recovered[s] ELSE applied[s] IN
       /\ \A k \in 1..Len(tree) : commitCertified[tree[k].id]
       /\ IsPrefix(tree, committed[s]) \/ IsPrefix(committed[s], tree)
       /\ applied' = [applied EXCEPT ![s] = tree]
       /\ committed' = [committed EXCEPT ![s] =
              IF IsPrefix(tree, committed[s]) THEN committed[s] ELSE tree]
    /\ zkState' = [zkState EXCEPT ![s] = "running"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, nlAcks, newLeaderAcked, leaderSummaryEpoch>>
    /\ ResetRollback

(* followLeader sets BROADCAST after syncWithLeader returns                *)
(* (quorum/Follower.java:109-110), i.e. after UPTODATE and the post-UPTODATE*)
(* logRequest loop (quorum/Learner.java:777-783).                          *)
EnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncJustified[s] /\ currentEpoch[s] = acceptedEpoch[s]
    /\ zkState[s] = "running"
    /\ Len(queued[s]) = Len(proposed[s])
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* ProposalRequestProcessor calls propose before enqueuing local disk sync. *)
Propose(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ t \in Txn \ usedTxn
    /\ LET ent == EntryFor(t, currentEpoch[l]) IN
       /\ proposed' = [proposed EXCEPT ![l] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![l] = Append(@, ent)]
       /\ messages' = messages \cup
             {[kind |-> "proposal", from |-> l, to |-> s,
               id |-> t, epoch |-> currentEpoch[l]] :
                 s \in Server \ {l}}
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, newLeaderVars>>
    /\ ResetRollback

(* Follower.processPacket PROPOSAL -> fzk.logRequest in BROADCAST          *)
(* (quorum/Follower.java:150-170).  During synchronization the packet is   *)
(* buffered in packetsNotCommitted (quorum/Learner.java:616-643), which    *)
(* Leader.startForwarding feeds with outstanding proposals                 *)
(* (Leader.java:1294-1330); a proposal already present in the buffered     *)
(* history is not re-delivered.                                            *)
ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[m.to] /\ role[m.to] = "following"
    /\ leaderOf[m.to] = m.from
    /\ \/ /\ phase[m.to] = "broadcast"
          \* A learner's packet stream reaches broadcast only for its synchronized
          \* current epoch; a stale connection cannot enqueue a later-epoch proposal.
          /\ currentEpoch[m.to] = m.epoch
       \/ /\ phase[m.to] = "sync"
          /\ syncJustified[m.to]
          /\ acceptedEpoch[m.to] = m.epoch
    /\ LET ent == EntryFor(m.id, m.epoch) IN
       /\ ~HasEntry(proposed[m.to], ent)
       /\ proposed' = [proposed EXCEPT ![m.to] = Append(@, ent)]
       /\ queued' = IF phase[m.to] = "broadcast"
                    THEN [queued EXCEPT ![m.to] = Append(@, ent)]
                    ELSE queued
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* FollowerZooKeeperServer.commit hands the head of pendingTxns to the     *)
(* CommitProcessor (quorum/FollowerZooKeeperServer.java:97-111).  After    *)
(* UPTODATE the learner commits every buffered packetsCommitted zxid       *)
(* (quorum/Learner.java:777-786); in BROADCAST commits arrive as packets.  *)
(* [repair] A learner never self-certifies: the leader only sends COMMIT   *)
(* for committed proposals (LearnerHandler.queueCommittedProposals,        *)
(* Leader.tryToCommit), so the certificate must already exist.             *)
ObserveCommit(s, t, ep) ==
    /\ up[s] /\ role[s] = "following"
    /\ \/ phase[s] = "sync" /\ zkState[s] = "running"
       \/ phase[s] = "broadcast"
    /\ Len(committed[s]) < Len(proposed[s])
    /\ proposed[s][Len(committed[s]) + 1] = EntryFor(t, ep)
    /\ commitCertified[t]
    /\ committed' = [committed EXCEPT ![s] = Append(@, EntryFor(t, ep))]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked,
                    commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* SyncRequestProcessor append writes the txn stream but has not fsynced it. *)
(* (server/SyncRequestProcessor.java:181).  It runs on its own thread and  *)
(* keeps draining its queue regardless of the learner's protocol phase.    *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ LET ent == queued[s][Len(appended[s]) + 1] IN
       appended' = [appended EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* FileTxnLog.commit forces an appended entry; ACK is only created afterward. *)
(* (server/SyncRequestProcessor.java:227-249).  [repair] A processor whose *)
(* learner connection is gone still forces its log; SendAckRequestProcessor*)
(* then fails to write the ACK (quorum/SendAckRequestProcessor.java:41-60).*)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE IF leaderOf[s] \in Server
          THEN /\ acked' = acked
               /\ messages' = messages \cup
                    {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                      id |-> ent.id, epoch |-> ent.epoch]}
          ELSE /\ acked' = acked
               /\ messages' = messages
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, newLeaderVars>>
    /\ ResetRollback

(* Leader.tryToCommit requires quorum ACKs and in-order outstanding proposals. *)
Commit(l, t) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast"
    /\ Len(committed[l]) < Len(proposed[l])
    /\ LET ent == proposed[l][Len(committed[l]) + 1] IN
       /\ ent.id = t
       /\ Cardinality(acked[t]) >= Quorum
       /\ committed' = [committed EXCEPT ![l] = Append(@, ent)]
       /\ commitCertified' = [commitCertified EXCEPT ![t] = TRUE]
       /\ messages' = messages \cup
            {[kind |-> "commit", from |-> l, to |-> s,
              id |-> t, epoch |-> ent.epoch] : s \in Server \ {l}}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* A COMMIT packet is a certificate of a leader-side quorum decision.      *)
(* During synchronization COMMITs are buffered (packetsCommitted) and only *)
(* handed to the CommitProcessor after UPTODATE (quorum/Learner.java:      *)
(* 645-655, 777-786).                                                      *)
ReceiveCommit(m) ==
    /\ m \in messages /\ m.kind = "commit" /\ up[m.to]
    /\ role[m.to] = "following" /\ leaderOf[m.to] = m.from
    /\ \/ phase[m.to] = "broadcast"
       \/ phase[m.to] = "sync" /\ zkState[m.to] = "running"
    /\ currentEpoch[m.to] = m.epoch
    /\ Len(committed[m.to]) < Len(proposed[m.to])
    /\ proposed[m.to][Len(committed[m.to]) + 1] = EntryFor(m.id, m.epoch)
    /\ committed' = [committed EXCEPT ![m.to] = Append(@, EntryFor(m.id, m.epoch))]
    /\ commitCertified' = [commitCertified EXCEPT ![m.id] = TRUE]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* FinalRequestProcessor applies only a certified, in-order commit. *)
\* The in-memory database follows the applied history (DataTree.processTxn).
ApplyOne(s) ==
    /\ up[s] /\ Len(applied[s]) < Len(committed[s])
    /\ LET ent == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[ent.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, ent)]
       /\ recovered' = [recovered EXCEPT ![s] =
              IF IsPrefix(applied'[s], recovered[s]) THEN recovered[s] ELSE applied'[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, snapshot, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* Snapshot captures an applied prefix and is named by lastProcessedZxid. *)
TakeSnapshot(s) ==
    /\ up[s] /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn, newLeaderVars>>
    /\ ResetRollback

(* Crash drops non-durable queues; snapshot is the safe visible restart prefix. *)
(* Fail-stop: the SyncRequestProcessor queue, the unforced log tail and    *)
(* every in-memory learner buffer are lost (FileTxnLog.java:375-405).      *)
Crash(s) ==
    /\ up[s]
    /\ up' = [up EXCEPT ![s] = FALSE]
    /\ role' = [role EXCEPT ![s] = "looking"]
    /\ phase' = [phase EXCEPT ![s] = "offline"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = Nil]
    /\ proposed' = [proposed EXCEPT ![s] = durable[s]]
    /\ queued' = [queued EXCEPT ![s] = durable[s]]
    /\ appended' = [appended EXCEPT ![s] = durable[s]]
    /\ committed' = [committed EXCEPT ![s] = snapshot[s]]
    /\ applied' = [applied EXCEPT ![s] = snapshot[s]]
    /\ recovered' = [recovered EXCEPT ![s] = <<>>]
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ syncSource' = [syncSource EXCEPT ![s] = Nil]
    /\ syncJustified' = [syncJustified EXCEPT ![s] = FALSE]
    /\ nlAcks' = [nlAcks EXCEPT ![s] = {}]
    /\ newLeaderAcked' = [newLeaderAcked EXCEPT ![s] = FALSE]
    /\ zkState' = [zkState EXCEPT ![s] = "off"]
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    durable, snapshot, acked, commitCertified, messages,
                    usedTxn, leaderSummaryEpoch>>

(* restore() loads snapshot then replays durable log into tentative recovery state. *)
(* QuorumPeer.loadDataBase (quorum/QuorumPeer.java:1101-1150): the in-memory *)
(* database (recovered) is rebuilt from snapshot + durable log.            *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ recovered' = [recovered EXCEPT ![s] = durable[s]]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, usedTxn,
                    newLeaderVars>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn, newLeaderVars>>
    /\ ResetRollback

Next ==
    \/ \E s \in Server : BeginElection(s)
    \/ \E voter, candidate \in Server : CastVote(voter, candidate)
    \/ \E s \in Server : WinElection(s)
    \/ \E s, l \in Server : FollowLeader(s, l)
    \/ \E s \in Server : AcceptEpoch(s)
    \/ \E l \in Server : FinishDiscovery(l)
    \/ \E s, l \in Server : EnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : SelectSync(s, l, mode)
    \/ \E s \in Server : CompleteSync(s)
    \/ \E s \in Server : PersistCurrentEpoch(s)
    \/ \E s \in Server : ClearSyncMode(s)
    \/ \E s \in Server : LogSyncProposal(s)
    \/ \E s \in Server : AckNewLeader(s)
    \/ \E l, s \in Server : CountNewLeaderAck(l, s)
    \/ \E l \in Server : LeaderBroadcast(l)
    \/ \E s \in Server : ReceiveUpToDate(s)
    \/ \E s \in Server : EnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : Propose(l, t)
    \/ \E m \in messages : ReceiveProposal(m)
    \/ \E s \in Server, t \in Txn, ep \in Epoch : ObserveCommit(s, t, ep)
    \/ \E s \in Server : AppendOne(s)
    \/ \E s \in Server : FsyncOne(s)
    \/ \E m \in messages : DeliverAck(m)
    \/ \E l \in Server, t \in Txn : Commit(l, t)
    \/ \E m \in messages : ReceiveCommit(m)
    \/ \E s \in Server : ApplyOne(s)
    \/ \E s \in Server : TakeSnapshot(s)
    \/ \E s \in Server : Crash(s)
    \/ \E s \in Server : Restart(s)
    \/ \E m \in messages : DropMessage(m)

Spec == Init /\ [][Next]_allVars

\* REQ-EVIDENCE TypeOK
\* intent:   Every model variable always holds a value of its declared type.
\* status:   model-internal
\* watch:    none (type invariant of the model itself)
\* verified: update
\* review:   extended with nlAcks/newLeaderAcked/zkState for the update
TypeOK ==
    /\ up \in [Server -> BOOLEAN]
    /\ role \in [Server -> Role]
    /\ phase \in [Server -> Phase]
    /\ leaderOf \in [Server -> (Server \cup {Nil})]
    /\ acceptedEpoch \in [Server -> Epoch]
    /\ currentEpoch \in [Server -> Epoch]
    /\ votes \in [Server -> SUBSET Server]
    /\ leadersByEpoch \in [Epoch -> SUBSET Server]
    /\ proposed \in [Server -> Seq(Entry)]
    /\ queued \in [Server -> Seq(Entry)]
    /\ appended \in [Server -> Seq(Entry)]
    /\ durable \in [Server -> Seq(Entry)]
    /\ committed \in [Server -> Seq(Entry)]
    /\ applied \in [Server -> Seq(Entry)]
    /\ snapshot \in [Server -> Seq(Entry)]
    /\ recovered \in [Server -> Seq(Entry)]
    /\ acked \in [Txn -> SUBSET Server]
    /\ commitCertified \in [Txn -> BOOLEAN]
    /\ messages \subseteq Message
    /\ syncMode \in [Server -> SyncModes]
    /\ syncSource \in [Server -> (Server \cup {Nil})]
    /\ syncJustified \in [Server -> BOOLEAN]
    /\ usedTxn \subseteq Txn
    /\ rollbackAuthorized \in [Server -> BOOLEAN]
    /\ nlAcks \in [Server -> SUBSET Server]
    /\ newLeaderAcked \in [Server -> BOOLEAN]
    /\ zkState \in [Server -> ZkStates]
    /\ leaderSummaryEpoch \in [Server -> Epoch]

\* REQ-EVIDENCE ElectionSafety
\* intent:   At most one server ever takes leadership of any given epoch.
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:130 "Leadership activation will ensure that only one leader uses a given epoch" -> at most one leader per epoch
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:195 "will only ACK a NEW_LEADER proposal with a given zxid from a single server" -> a follower ACKs the NEW_LEADER proposal for a given zxid (epoch) from only one server (mechanism toward one leader per epoch)
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:513 "since we have already acked an epoch equal to the leaders, we cannot ack" -> a follower acknowledges a given epoch at most once
\* evidence: history 1a556bd1 (message) "getEpochToPropose should check if lastAcceptedEpoch is greater or equal than epoch" -> a proposed epoch must exceed, not merely equal, a follower's last accepted epoch (mechanism against epoch reuse)
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:213 testLastAcceptedEpoch "New proposed epoch is wrong" -> the proposed epoch exceeds the accepted epoch a connecting follower reports (6 gives 7)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1401 "if (lastAcceptedEpoch >= epoch) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:517 "wrappedEpochBytes.putInt(-1);"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:getEpochToPropose; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:waitForEpochAck; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FastLeaderElection.java:lookForLeader
\* verified: update (watch locations unchanged by the update; kept, see invariant-evidence.json)
\* note:     searched docs and main sources for "one leader", "single leader", "same epoch", "unique epoch"; zookeeperInternals.md:130 is the only direct statement. No Zab paper text exists in /work, so no protocol-type evidence is cited. The Learner.java:513 comment and commit 1a556bd1 describe the mechanism that yields the property rather than the property itself.
\* review:   intent said "established as leader" but the formula counts every server that won the election for an epoch, so it now says "takes leadership"; the :195, 1a556bd1 and testLastAcceptedEpoch arrows were narrowed to what each quote literally states.
ElectionSafety == \A e \in Epoch : Cardinality(leadersByEpoch[e]) <= 1

\* REQ-EVIDENCE OneActiveLeaderPerEpoch
\* intent:   At any moment, at most one running server is leading in any given epoch.
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:130 "Leadership activation will ensure that only one leader uses a given epoch" -> at most one leader uses an epoch
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:246 "there is only one active leader at a time" -> at most one active leader (taken per epoch, see note)
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:211 "no other leader will be able to get a quorum of followers" -> a second leader cannot become established while one holds its quorum
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:760 "if (!tickSkip && !syncedAckSet.hasAllQuorums()) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:1401 "if (lastAcceptedEpoch >= epoch) {"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:lead; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:getEpochToPropose; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader
\* verified: update (watch locations unchanged; kept)
\* note:     zookeeperInternals.md:278 describes two servers that simultaneously think they are the leader, so the "one active leader at a time" sentence (line 246) is relied on only in its per-epoch reading. Searched main sources for "two leaders", "multiple leaders", "single leader": no further statement found.
\* review:   ok
OneActiveLeaderPerEpoch ==
    \A e \in Epoch :
        Cardinality({s \in Server : up[s] /\ role[s] = "leading"
                                    /\ acceptedEpoch[s] = e}) <= 1

\* REQ-EVIDENCE CommittedHistoriesPrefix
\* intent:   For any two servers, one server's sequence of committed transactions is a prefix of the other's.
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:63 "message `a` will be delivered before `b` by all" -> all servers commit/deliver transactions in the same order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:59 "message `m` will be eventually delivered by all servers." -> every server eventually delivers a message that one server delivered (none is skipped for good)
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:234 "COMMITs are processed in order." -> each follower commits in the leader's order
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:891 "make sure that ops are committed in order." -> the leader commits in proposal order
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:103 "if (firstElementZxid != zxid) {"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:tryToCommit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:processAck; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:syncFollower; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:queueCommittedProposals; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:commit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java:processPacket
\* verified: update (watch Learner.java:syncWithLeader touched; kept as requirement, see invariant-evidence.json K1)
\* note:     no single source states the prefix relation; it follows from Total order (zookeeperInternals.md:61-64) together with Reliable delivery (zookeeperInternals.md:57-59). FollowerResyncConcurrencyTest.java:608 (helper verifyState, called from testResyncByDiffAfterFollowerCrashes) was not counted: it asserts only that leader and follower hold the same number of ephemerals for a session.
\* review:   removed the FollowerResyncConcurrencyTest:608 line, whose assertion compares only per-session ephemeral counts and so supports no part of the prefix intent, and narrowed the line-59 arrow to what Reliable delivery states.
CommittedHistoriesPrefix ==
    \A a, b \in Server : IsPrefix(committed[a], committed[b]) \/
                          IsPrefix(committed[b], committed[a])

\* REQ-EVIDENCE ApplyRequiresCommitCertificate
\* intent:   A server applies only transactions that a quorum has committed, and applies them in its commit order.
\* status:   requirement
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:902 "in order to be committed, a proposal must be accepted by a quorum." -> a commit is backed by a quorum certificate
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:117 "committed when a quorum of them acknowledge the proposal." -> committed means quorum-acknowledged
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:235 "message when that proposal is committed." -> a follower delivers (applies) a proposal only once it is committed
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/CommitProcessor.java:70 "Write requests must be processed in zxid order" -> applied sequence follows commit order
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:655 testNormalFollowerRun "The change should not have happened yet, since we haven't committed" -> a proposed transaction is not applied before its COMMIT arrives (assertion at line 656, one scenario)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:663 "zk.processTxn(pif.hdr, pif.rec);"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/CommitProcessor.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/FinalRequestProcessor.java:processRequest; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:tryToCommit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:commit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:restore
\* verified: update (watch Learner.java:syncWithLeader touched; kept, see invariant-evidence.json K2)
\* note:     the doc sentence spans zookeeperInternals.md:234-235 ("Followers deliver a proposal message when that proposal is committed."); only the line-235 part is quoted. FollowerZooKeeperServer.java:95 (@param contract of commit) was not counted: it requires a COMMIT to match the head of pendingTxns, which is about commit order, not about what is applied.
\* review:   removed the FollowerZooKeeperServer.java:95 contract line, which constrains which zxid a COMMIT may name and supports no part of the apply intent, and narrowed the Zab1_0Test:655 arrow to the one scenario it asserts.
ApplyRequiresCommitCertificate ==
    \A s \in Server :
        /\ IsPrefix(applied[s], committed[s])
        /\ \A k \in 1..Len(applied[s]) : commitCertified[applied[s][k].id]

\* REQ-EVIDENCE PipelinePrefix
\* intent:   On every server the fsynced, written and queued sequences are successive prefixes of the proposal sequence (so the fsynced log follows proposal order), and the snapshot is a prefix of the applied sequence.
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:229 "has been written to non-volatile storage, all messages that were proposed before" -> the fsynced log is a prefix of the proposal order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:245 "see and record proposals in order" -> each server records proposals in proposal order
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:226 "Followers process messages in the order they are received." -> a follower processes proposals in arrival order (for followers, the recorded log follows proposal order)
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperAdmin.md:2593 "last committed transaction at the start of the snapshot" -> a snapshot is labelled with a transaction already applied when it starts
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:181 "if (!si.isThrottled() && zks.getZKDatabase().append(si)) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:235 "zks.getZKDatabase().commit();"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:468 "long lastZxid = dataTree.lastProcessedZxid;"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:flush; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnLog.java:append; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnLog.java:commit; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/ProposalRequestProcessor.java:processRequest; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:logRequest; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:takeSnapshot; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:save
\* verified: update (logRequest call sites moved; `proposed` now also holds the learner sync buffer; kept, see invariant-evidence.json K3)
\* clause durableInProposalOrder: requirement — what conjuncts 1-3 jointly imply, that the fsynced log is a prefix of the proposal sequence: zookeeperInternals.md:229, :245, :226.
\* clause intermediateStages: impl-abstraction — conjuncts 1-3 as written, i.e. separate queued and written-but-unsynced stages each a prefix of the one before: only impl (SyncRequestProcessor.java queuedRequests, append at :181, flush/commit at :235).
\* clause snapshotWithinApplied: requirement — conjunct 4: zookeeperAdmin.md:2588-2594 (snapshot named by the last committed transaction at its start, contents taken from the data tree).
\* note:     the separate queued and written (appended) stages are named only in the implementation (SyncRequestProcessor queuedRequests/toFlush); the docs speak of in-order recording as a whole. zookeeperAdmin.md:2589-2600 calls snapshots fuzzy (content may match no tree that existed); the quote supports only that a snapshot never reaches beyond applied updates. Searched SyncRequestProcessor.java, FileTxnLog.java, ProposalRequestProcessor.java and the history (hist.sh log -S'toFlush'; read 876aaf42 and cc431f70) for a statement on the order of the queue and write stages: none found.
\* review:   status changed from requirement to mixed: the separate queue and written-but-unsynced stages are backed only by impl (the :226 arrow had generalized "followers process messages in order" to every stage), so only the fsync-order and snapshot parts stay requirement.
PipelinePrefix ==
    \A s \in Server :
        /\ IsPrefix(durable[s], appended[s])
        /\ IsPrefix(appended[s], queued[s])
        /\ IsPrefix(queued[s], proposed[s])
        /\ IsPrefix(snapshot[s], applied[s])

\* REQ-EVIDENCE EpochHistoryConsistency
\* intent:   On every server the current epoch never exceeds the accepted epoch, and the last fsynced log entry carries no epoch later than the accepted epoch.
\* status:   mixed
\* evidence: history 19d85670 (message) "ZooKeeper not starting because acceptedEpoch is less than the currentEpoch" -> an accepted epoch below the current epoch is a defect
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:615 testNormalFollowerRun "assertEquals(0, f.self.getCurrentEpoch());" -> after ACKEPOCH the current epoch (0) lags the accepted epoch (1, line 614)
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:749 testNormalFollowerRunWithDiff "assertEquals(0, f.self.getCurrentEpoch());" -> same ordering in the DIFF-sync conversation (accepted 1 at line 748)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1142 "if (acceptedEpoch < currentEpoch) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1122 "if (epochOfZxid > currentEpoch) {"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:521 "is less than accepted epoch,"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:loadDataBase; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:setCurrentEpoch; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:setAcceptedEpoch; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:lead; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:getEpochToPropose
\* verified: update (setCurrentEpoch position unchanged; kept)
\* clause currentEpochAtMostAccepted: requirement — commit 19d85670 (ZOOKEEPER-2307) treats acceptedEpoch < currentEpoch as a startup-blocking defect; Zab1_0Test:614-615 and 748-749 assert accepted advances before current.
\* clause logEpochAtMostAccepted: unknown — only impl: QuorumPeer.loadDataBase (line 1122) refuses to start when the last zxid's epoch exceeds the current epoch; no doc, comment, test or commit message states the rule.
\* note:     searched history with -S'acceptedEpoch < currentEpoch' and -S'epochOfZxid > currentEpoch' (both introduced by 776db780, whose message lists only JIRA titles) and read 1ea6879b (error-message fix only); searched tests for "older than the last zxid" and "is less than the current epoch": none. The startup check at QuorumPeer.java:1122 compares the last zxid's epoch with currentEpoch, not with acceptedEpoch.
\* review:   intent said no logged transaction carries a later epoch, but the formula bounds only the epoch of the last fsynced entry, so the intent was narrowed to that; evidence, clauses and statuses checked and kept.
EpochHistoryConsistency ==
    /\ \A s \in Server : currentEpoch[s] <= acceptedEpoch[s]
    /\ \A s \in Server : LastEpoch(durable[s]) <= acceptedEpoch[s]

\* REQ-EVIDENCE SyncCompletionJustified
\* intent:   A follower in the broadcast phase has completed synchronization with its leader, has an identified leader, and has set its current epoch equal to its accepted epoch.
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:194 "A follower will ACK the NEW_LEADER proposal after it has synced with the leader." -> a follower has synced with the leader before it ACKs NEW_LEADER
\* evidence: history f8f15de5 (message) "setCurrentEpoch should be done upon receipt of NEWLEADER (before acking it)" -> current epoch equals the new (accepted) epoch before the follower leaves sync
\* evidence: history 148c2cd6 (message) "Fix data inconsistency due to NEWLEADER being sent too early" -> NEWLEADER, which ends sync, must follow the complete sync payload
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java:1179 testInconsistentDueToNewLeaderOrder "start follower A, after it's in broadcast state, make sure" -> a broadcasting follower holds the leader's synced data
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:637 testNormalFollowerRun "assertEquals(1, f.self.getCurrentEpoch());" -> after the NEWLEADER ACK current epoch equals accepted epoch (1, line 636)
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java:780 testNormalFollowerRunWithDiff "assertEquals(1, f.self.getCurrentEpoch());" -> same after a DIFF sync (accepted 1, line 779)
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java:109 "syncWithLeader(newEpochZxid);"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743 "self.setCurrentEpoch(newEpoch);"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java:followLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:registerWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:run; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:waitForNewLeaderAck
\* verified: update (watch Learner.java:syncWithLeader touched; kept, see invariant-evidence.json K4)
\* clause syncedBeforeBroadcast: requirement — zookeeperInternals.md:194; commit 148c2cd6 (ZOOKEEPER-3104); QuorumPeerMainTest:1179 testInconsistentDueToNewLeaderOrder.
\* clause epochsAlignedInBroadcast: requirement — commit f8f15de5 (ZOOKEEPER-1282) message; Zab1_0Test:636-637 and 779-780.
\* clause leaderKnown: model-internal — well-formedness of the leaderOf bookkeeping; only impl backs it (Follower.java:107 setLeaderAddressAndId before sync).
\* note:     searched commit messages for "currentEpoch", "current epoch", "NEWLEADER" (hist.sh log -i --grep); f8f15de5, 148c2cd6, 19d85670, 8b4520f7/21ef61aa and 776db780 were found, the first two are cited.
\* review:   narrowed the :194 arrow from "leaves synchronization" to the NEW_LEADER ACK that the doc actually orders after syncing; other evidence, clauses and statuses checked and kept.
SyncCompletionJustified ==
    \A s \in Server :
        (role[s] = "following" /\ phase[s] = "broadcast") =>
          /\ syncJustified[s]
          /\ leaderOf[s] \in Server
          /\ currentEpoch[s] = acceptedEpoch[s]

\* REQ-EVIDENCE NoIllegalRollback
\* intent:   A server's durable log, committed prefix and applied prefix never shrink, except when the server crashes or installs its leader's history during synchronization.
\* status:   mixed
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:183 "the leader will tell the follower to discard `U`." -> the sync-time exception: uncommitted proposals a follower logged are discarded when the leader tells it to
\* evidence: contract source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/TxnLog.java:83 "truncate the log to get in sync with the" -> log truncation exists to get in sync with the leader
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:119 "Acknowledgement means the server has recorded the proposal to persistent storage." -> an acknowledged proposal is recorded in persistent storage, so it is not lost
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperOver.md:168 "client will never see an older view of the system even if the" -> a serving server's applied state does not move backwards
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperProgrammers.md:1177 "request or successful update, will never be rolled back when" -> updates a client has seen are never rolled back when recovering from server failures
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/test/TruncateTest.java:225 testTruncate "as a result /12 is the first of the truncated znodes to check for" -> the permitted exception: an unquorumed log suffix is truncated when syncing with the leader
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:591 "boolean truncated = zk.getZKDatabase().truncateLog(qp.getZxid());"
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:600 "clear();"
\* watch:    source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:syncWithLeader; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:truncateLog; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:deserializeSnapshot; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java:loadDataBase; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java:truncateLog; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnLog.java:truncate; source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java:syncFollower
\* verified: update (DIFF branch no longer installs durable state at CompleteSync; kept)
\* clause durableNoRollback: requirement — zookeeperInternals.md:119 and 182-183, TxnLog.java:83 contract; TruncateTest:225 shows the sync-time exception.
\* clause appliedNoRollback: requirement — zookeeperOver.md:166-171 (Single System Image, Reliability) and zookeeperProgrammers.md:1176-1178.
\* clause committedNoRollback: unknown — only impl (Learner.syncWithLeader packetsCommitted, FollowerZooKeeperServer.commit pendingTxns); no statement covers a learner's committed-but-unapplied prefix.
\* note:     the client guarantees in zookeeperOver.md and zookeeperProgrammers.md are stated at service level, not per server. History searched: -S'truncateLog(' (a4bc9857, 6abd8593, 43eedab1, 3ba0a545, 0957b840, 0254f868, 344a3079), -S'Not able to truncate the log', -S'get in sync with the', -S'Cannot send TRUNC to peer' (9f102d31); read a4bc9857 and 43eedab1: they fix truncation failures/data loss but state no rule on when shrinking is allowed.
\* review:   narrowed three arrows to what the quotes state (line 183 has the leader direct the discard of U but no "only", line 119 defines ACK as persistent recording, line 1177 covers updates a client has seen); clause statuses kept.
NoIllegalRollback ==
    \A s \in Server :
       /\ (Len(durable'[s]) >= Len(durable[s]) \/ rollbackAuthorized'[s])
       /\ (Len(committed'[s]) >= Len(committed[s]) \/ rollbackAuthorized'[s])
       /\ (Len(applied'[s]) >= Len(applied[s]) \/ rollbackAuthorized'[s])

\* REQ-EVIDENCE HistoryPositionsMonotonicExceptRecovery -> alias of [][NoIllegalRollback]_allVars; see REQ-EVIDENCE NoIllegalRollback
\* review:   ok
HistoryPositionsMonotonicExceptRecovery == [][NoIllegalRollback]_allVars

Safety == TypeOK /\ ElectionSafety /\ OneActiveLeaderPerEpoch /\
          CommittedHistoriesPrefix /\ ApplyRequiresCommitCertificate /\
          PipelinePrefix /\ EpochHistoryConsistency /\ SyncCompletionJustified

\* All voting-server identities are interchangeable in the finite models.
\* TLC's permutation quotient removes only renamed copies of the same state.
ModelSymmetry == Permutations(Server)

\* Canonical depth constraint retained from V0, recalibrated for the longer
\* NEWLEADER/UPTODATE sequence (see MC.cfg and spec/changelog.md).
CanonicalDepthBound == TLCGet("level") <= 30

=============================================================================
