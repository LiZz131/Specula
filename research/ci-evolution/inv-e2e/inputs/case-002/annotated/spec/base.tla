------------------------------ MODULE base ------------------------------
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

CONSTANTS Server, Txn, MaxEpoch, Nil

ASSUME /\ Server /= {}
       /\ Txn /= {}
       /\ MaxEpoch \in Nat \ {0}
       /\ Nil \notin Server

Role == {"looking", "leading", "following"}
Phase == {"election", "discovery", "sync", "broadcast", "offline"}
SyncModes == {"NONE", "DIFF", "TRUNC", "SNAP"}
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
          usedTxn, rollbackAuthorized

allVars == <<up, role, phase, leaderOf,
             acceptedEpoch, currentEpoch,
             votes, leadersByEpoch,
             proposed, queued, appended, durable, committed, applied,
             snapshot, recovered,
             acked, commitCertified, messages,
             syncMode, syncSource, syncJustified,
             usedTxn, rollbackAuthorized>>

IsPrefix(a, b) == Len(a) <= Len(b) /\ SubSeq(b, 1, Len(a)) = a
EntryFor(id, ep) == [id |-> id, epoch |-> ep]
TxnIds(h) == {h[k].id : k \in 1..Len(h)}
LastEpoch(h) == IF Len(h) = 0 THEN 0 ELSE h[Len(h)].epoch
LastId(h) == IF Len(h) = 0 THEN Nil ELSE h[Len(h)].id

ResetRollback == rollbackAuthorized' = [s \in Server |-> FALSE]

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

(* FastLeaderElection.lookForLeader: logical round and self vote. *)
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
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    usedTxn>>
    /\ ResetRollback

(* FLE totalOrderPredicate: epoch, then last zxid/log length, then id. *)
HistoryAtLeast(candidate, voter) ==
    \/ currentEpoch[candidate] > currentEpoch[voter]
    \/ /\ currentEpoch[candidate] = currentEpoch[voter]
       /\ Len(durable[candidate]) >= Len(durable[voter])

CastVote(voter, candidate) ==
    /\ up[voter] /\ up[candidate]
    /\ role[voter] = "looking"
    /\ HistoryAtLeast(candidate, voter)
    /\ votes' = [votes EXCEPT ![candidate] = @ \cup {voter}]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* FLE quorum decision followed by Leader.getEpochToPropose. *)
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
    /\ UNCHANGED <<up, currentEpoch, votes, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* QuorumPeer main loop switches a learner to FOLLOWING before Zab discovery. *)
FollowLeader(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[l] = "leading"
    /\ role' = [role EXCEPT ![s] = "following"]
    /\ phase' = [phase EXCEPT ![s] = "discovery"]
    /\ leaderOf' = [leaderOf EXCEPT ![s] = l]
    /\ UNCHANGED <<up, acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    proposed, queued, appended, durable, committed, applied,
                    snapshot, recovered, acked, commitCertified, messages,
                    syncMode, syncSource, syncJustified, usedTxn>>
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
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* Leader.waitForEpochAck completes after a participant quorum. *)
FinishDiscovery(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "discovery"
    /\ Cardinality({s \in Server : up[s] /\ acceptedEpoch[s] = acceptedEpoch[l]}) >= Quorum
    /\ currentEpoch' = [currentEpoch EXCEPT ![l] = acceptedEpoch[l]]
    /\ phase' = [phase EXCEPT ![l] = "sync"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

DiffAllowed(s, l) == IsPrefix(durable[s], durable[l])
TruncAllowed(s, l) == IsPrefix(durable[l], durable[s])

(* QuorumPeer exposes SYNCHRONIZATION before the mode packet is consumed. *)
EnterSyncPhase(s, l) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "discovery" /\ phase[l] = "sync"
    \* Learner.registerWithLeader persists the proposed epoch before the
    \* learner can consume a synchronization directive.
    /\ acceptedEpoch[s] = acceptedEpoch[l]
    /\ phase' = [phase EXCEPT ![s] = "sync"]
    /\ syncSource' = [syncSource EXCEPT ![s] = l]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncJustified,
                    usedTxn>>
    /\ ResetRollback

(* LearnerHandler.syncFollower chooses DIFF/TRUNC/SNAP under the DB log lock. *)
SelectSync(s, l, mode) ==
    /\ s /= l /\ up[s] /\ up[l]
    /\ role[s] = "following" /\ leaderOf[s] = l
    /\ phase[s] = "sync" /\ phase[l] = "sync"
    /\ syncSource[s] = l
    /\ mode \in SyncModes \ {"NONE"}
    /\ IF mode = "DIFF" THEN DiffAllowed(s, l)
       ELSE IF mode = "TRUNC" THEN TruncAllowed(s, l)
       ELSE ~(DiffAllowed(s, l) \/ TruncAllowed(s, l)) \/ durable[s] = <<>>
    /\ syncMode' = [syncMode EXCEPT ![s] = mode]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn>>
    /\ ResetRollback

(* Learner.syncWithLeader installs the selected history before NEWLEADER ACK. *)
CompleteSync(s) ==
    /\ up[s] /\ phase[s] = "sync"
    /\ syncSource[s] \in Server
    /\ syncMode[s] \in SyncModes \ {"NONE"}
    /\ LET l == syncSource[s] IN
       /\ up[l] /\ role[l] = "leading"
       \* The selected sync and NEWLEADER exchange are bound to one epoch;
       \* reusing the same leader identity after restart is not sufficient.
       /\ acceptedEpoch[s] = acceptedEpoch[l]
       /\ durable' = [durable EXCEPT ![s] = durable[l]]
       /\ appended' = [appended EXCEPT ![s] = durable[l]]
       /\ queued' = [queued EXCEPT ![s] = durable[l]]
       /\ proposed' = [proposed EXCEPT ![s] = durable[l]]
       /\ committed' = [committed EXCEPT ![s] = committed[l]]
       /\ applied' = [applied EXCEPT ![s] = applied[l]]
       /\ recovered' = [recovered EXCEPT ![s] = durable[l]]
       /\ snapshot' = IF syncMode[s] = "SNAP"
                       THEN [snapshot EXCEPT ![s] = applied[l]]
                       ELSE snapshot
       /\ syncJustified' = [syncJustified EXCEPT ![s] = TRUE]
       /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, acked, commitCertified, messages,
                    syncMode, syncSource, usedTxn>>

(* NEWLEADER makes currentEpoch durable before the learner returns from sync. *)
PersistCurrentEpoch(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncJustified[s] /\ leaderOf[s] \in Server
    /\ acceptedEpoch[s] = acceptedEpoch[leaderOf[s]]
    /\ currentEpoch' = [currentEpoch EXCEPT ![s] = acceptedEpoch[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* followLeader changes the public Zab phase only after syncWithLeader returns. *)
EnterBroadcast(s) ==
    /\ up[s] /\ role[s] = "following" /\ phase[s] = "sync"
    /\ syncJustified[s] /\ currentEpoch[s] = acceptedEpoch[s]
    /\ phase' = [phase EXCEPT ![s] = "broadcast"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* syncWithLeader clears the externally reported sync mode before startup. *)
ClearSyncMode(s) ==
    /\ up[s] /\ phase[s] = "sync" /\ syncMode[s] /= "NONE"
    /\ syncMode' = [syncMode EXCEPT ![s] = "NONE"]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncSource, syncJustified,
                    usedTxn>>
    /\ ResetRollback

(* Leader.waitForNewLeaderAck starts the server after a NEWLEADER quorum. *)
LeaderBroadcast(l) ==
    /\ up[l] /\ role[l] = "leading" /\ phase[l] = "sync"
    /\ Cardinality({s \in Server : up[s]
                       /\ (s = l \/ (leaderOf[s] = l /\ phase[s] = "broadcast"))}) >= Quorum
    /\ phase' = [phase EXCEPT ![l] = "broadcast"]
    /\ UNCHANGED <<up, role, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
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
                    syncMode, syncSource, syncJustified>>
    /\ ResetRollback

ReceiveProposal(m) ==
    /\ m \in messages /\ m.kind = "proposal"
    /\ up[m.to] /\ role[m.to] = "following" /\ phase[m.to] = "broadcast"
    /\ leaderOf[m.to] = m.from
    \* A learner's packet stream reaches broadcast only for its synchronized
    \* current epoch; a stale connection cannot enqueue a later-epoch proposal.
    /\ currentEpoch[m.to] = m.epoch
    /\ LET ent == EntryFor(m.id, m.epoch) IN
       /\ proposed' = [proposed EXCEPT ![m.to] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![m.to] = Append(@, ent)]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, usedTxn>>
    /\ ResetRollback

(* Learner buffers proposals received while synchronization is finishing. *)
QueueLearnerProposal(s, t, ep) ==
    /\ up[s] /\ role[s] = "following"
    /\ phase[s] \in {"sync", "broadcast"}
    /\ leaderOf[s] \in Server
    /\ t \in Txn \ usedTxn /\ ep = currentEpoch[s]
    /\ LET ent == EntryFor(t, ep) IN
       /\ proposed' = [proposed EXCEPT ![s] = Append(@, ent)]
       /\ queued' = [queued EXCEPT ![s] = Append(@, ent)]
    /\ usedTxn' = usedTxn \cup {t}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, appended, durable, committed,
                    applied, snapshot, recovered, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified>>
    /\ ResetRollback

(* A learner-side COMMIT packet carries the leader's quorum certificate. *)
ObserveCommit(s, t, ep) ==
    /\ up[s] /\ role[s] = "following"
    /\ phase[s] \in {"sync", "broadcast"}
    /\ Len(committed[s]) < Len(proposed[s])
    /\ proposed[s][Len(committed[s]) + 1] = EntryFor(t, ep)
    /\ committed' = [committed EXCEPT ![s] = Append(@, EntryFor(t, ep))]
    /\ commitCertified' = [commitCertified EXCEPT ![t] = TRUE]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, messages,
                    syncMode, syncSource, syncJustified, usedTxn>>
    /\ ResetRollback

(* SyncRequestProcessor append writes the txn stream but has not fsynced it. *)
AppendOne(s) ==
    /\ up[s] /\ Len(appended[s]) < Len(queued[s])
    /\ LET ent == queued[s][Len(appended[s]) + 1] IN
       appended' = [appended EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, durable,
                    committed, applied, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* FileTxnLog.commit forces an appended entry; ACK is only created afterward. *)
FsyncOne(s) ==
    /\ up[s] /\ Len(durable[s]) < Len(appended[s])
    /\ LET ent == appended[s][Len(durable[s]) + 1] IN
       /\ durable' = [durable EXCEPT ![s] = Append(@, ent)]
       /\ IF role[s] = "leading"
          THEN /\ acked' = [acked EXCEPT ![ent.id] = @ \cup {s}]
               /\ messages' = messages
          ELSE /\ leaderOf[s] \in Server
               /\ acked' = acked
               /\ messages' = messages \cup
                    {[kind |-> "ack", from |-> s, to |-> leaderOf[s],
                      id |-> ent.id, epoch |-> ent.epoch]}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

DeliverAck(m) ==
    /\ m \in messages /\ m.kind = "ack" /\ up[m.to]
    /\ acked' = [acked EXCEPT ![m.id] = @ \cup {m.from}]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn>>
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
                    syncSource, syncJustified, usedTxn>>
    /\ ResetRollback

(* A COMMIT packet is a certificate of a leader-side quorum decision. *)
ReceiveCommit(m) ==
    /\ m \in messages /\ m.kind = "commit" /\ up[m.to]
    /\ role[m.to] = "following" /\ leaderOf[m.to] = m.from
    /\ currentEpoch[m.to] = m.epoch
    /\ Len(committed[m.to]) < Len(proposed[m.to])
    /\ proposed[m.to][Len(committed[m.to]) + 1] = EntryFor(m.id, m.epoch)
    /\ committed' = [committed EXCEPT ![m.to] = Append(@, EntryFor(m.id, m.epoch))]
    /\ commitCertified' = [commitCertified EXCEPT ![m.id] = TRUE]
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, applied, snapshot, recovered, acked, syncMode,
                    syncSource, syncJustified, usedTxn>>
    /\ ResetRollback

(* FinalRequestProcessor applies only a certified, in-order commit. *)
ApplyOne(s) ==
    /\ up[s] /\ Len(applied[s]) < Len(committed[s])
    /\ LET ent == committed[s][Len(applied[s]) + 1] IN
       /\ commitCertified[ent.id]
       /\ applied' = [applied EXCEPT ![s] = Append(@, ent)]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, snapshot, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* Snapshot captures an applied prefix and is named by lastProcessedZxid. *)
TakeSnapshot(s) ==
    /\ up[s] /\ snapshot[s] /= applied[s]
    /\ snapshot' = [snapshot EXCEPT ![s] = applied[s]]
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, recovered, acked,
                    commitCertified, messages, syncMode, syncSource,
                    syncJustified, usedTxn>>
    /\ ResetRollback

(* Crash drops non-durable queues; snapshot is the safe visible restart prefix. *)
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
    /\ rollbackAuthorized' = [x \in Server |-> x = s]
    /\ UNCHANGED <<acceptedEpoch, currentEpoch, votes, leadersByEpoch,
                    durable, snapshot, acked, commitCertified, messages,
                    usedTxn>>

(* restore() loads snapshot then replays durable log into tentative recovery state. *)
Restart(s) ==
    /\ ~up[s]
    /\ up' = [up EXCEPT ![s] = TRUE]
    /\ phase' = [phase EXCEPT ![s] = "election"]
    /\ recovered' = [recovered EXCEPT ![s] = durable[s]]
    /\ UNCHANGED <<role, leaderOf, acceptedEpoch, currentEpoch, votes,
                    leadersByEpoch, proposed, queued, appended, durable,
                    committed, applied, snapshot, acked, commitCertified,
                    messages, syncMode, syncSource, syncJustified, usedTxn>>
    /\ ResetRollback

DropMessage(m) ==
    /\ m \in messages
    /\ messages' = messages \ {m}
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, snapshot, recovered, acked,
                    commitCertified, syncMode, syncSource, syncJustified,
                    usedTxn>>
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
    \/ \E s \in Server : EnterBroadcast(s)
    \/ \E s \in Server : ClearSyncMode(s)
    \/ \E l \in Server : LeaderBroadcast(l)
    \/ \E l \in Server, t \in Txn : Propose(l, t)
    \/ \E m \in messages : ReceiveProposal(m)
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
\* verified: base
\* review:   ok
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
\* verified: base
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
\* verified: base
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
\* verified: base
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
\* verified: base
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
\* verified: base
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
\* verified: base
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
\* verified: base
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
\* verified: base
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

\* Canonical TLC runs are exhaustive through this explicit finite execution
\* depth.  Level 23 exceeds the preserved depth-22 mutation/apply witness and
\* retains election, synchronization, crash/restart, and re-election prefixes.
CanonicalDepthBound == TLCGet("level") <= 23

=============================================================================
