------------------------------ MODULE Update ------------------------------
(***************************************************************************)
(* Update-focused checking lens for case-002 (`baseline` -> `update`).     *)
(* Behaviour is owned by base.tla / MC.tla; this module only selects       *)
(* Actions, adds an observer for committed history, defines the update     *)
(* properties, and the focused/open/discharge entry points.                *)
(*                                                                         *)
(* Changed code:                                                           *)
(*   quorum/Learner.java:748-760  setSyncMode(NONE), startupWithoutServing,*)
(*        logRequest(packetsNotCommitted), clear, NEWLEADER ACK            *)
(*   quorum/Learner.java:765-767  ACK(UPTODATE), startServing              *)
(*   ZooKeeperServer.java:669-704 startup split (INITIAL vs RUNNING)       *)
(***************************************************************************)
EXTENDS MC

\* Observer of everything a broadcasting leader has committed, tagged with the
\* epoch in which it was first observed committed (for LeaderCompleteness).
VARIABLE everCommitted
uvars == <<allVars, mcVars, everCommitted>>

CommitRecord == [ent : Entry, ep : Epoch]

EstablishedLeaders(r, ph, u) == {x \in Server : u[x] /\ r[x] = "leading" /\ ph[x] = "broadcast"}

GhostNext ==
    everCommitted' = everCommitted \cup
        UNION {{[ent |-> committed'[l][k], ep |-> acceptedEpoch'[l]] :
                    k \in 1..Len(committed'[l])} :
                 l \in EstablishedLeaders(role', phase', up')}

UpdInit == MCInit /\ everCommitted = {}

(***************************************************************************)
(* Affected Actions: MC forms of the reference Actions whose behaviour the *)
(* source update changed.                                                  *)
(***************************************************************************)
\* reference: base!CompleteSync (DIFF branch buffers, persists nothing)
\* code: quorum/Learner.java:561-565, 616-643
\* reference: base!ClearSyncMode   code: quorum/Learner.java:749-751
\* reference: base!LogSyncProposal code: quorum/Learner.java:752-757, 777-783
\* reference: base!AckNewLeader    code: quorum/Learner.java:760
\* reference: base!ReceiveUpToDate code: quorum/Learner.java:765-767; ZooKeeperServer.java:677-680
\* reference: base!EnterBroadcast  code: quorum/Follower.java:109-110 (after the post-UPTODATE loop)
AffectedActions ==
    \/ \E s \in Server : MCCompleteSync(s)
    \/ \E s \in Server : MCClearSyncMode(s)
    \/ \E s \in Server : MCLogSyncProposal(s)
    \/ \E s \in Server : MCAckNewLeader(s)
    \/ \E s \in Server : MCReceiveUpToDate(s)
    \/ \E s \in Server : MCEnterBroadcast(s)

(***************************************************************************)
(* Interaction Actions: unchanged (or repaired) Actions that establish,    *)
(* consume, persist, or recover the changed results.                       *)
(***************************************************************************)
\* producers: election/discovery/sync selection establish the NEWLEADER window;
\* SyncRequestProcessor (AppendOne/FsyncOne) persists the queued DIFF suffix;
\* CountNewLeaderAck/LeaderBroadcast consume the ACK (repaired, Leader.java:1547-1586, 660-712);
\* Crash/Restart cross the queued-vs-durable boundary; Propose/ReceiveProposal/
\* DeliverAck/Commit/ReceiveCommit/ObserveCommit are the old consumers of the
\* synchronized history; the next election (CastVote/WinElection) reads durable.
InteractionActions ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E s \in Server : MCPersistCurrentEpoch(s)
    \/ \E l, s \in Server : MCCountNewLeaderAck(l, s)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E m \in messages : MCReceiveProposal(m)
    \/ \E s \in Server, t \in Txn, ep \in Epoch : MCObserveCommit(s, t, ep)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E m \in messages : MCDeliverAck(m)
    \/ \E l \in Server, t \in Txn : MCCommit(l, t)
    \/ \E m \in messages : MCReceiveCommit(m)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
    \* ApplyOne advances the in-memory database (`recovered`) read by votes.
    \/ \E s \in Server : MCApplyOne(s)

\* Reference Actions omitted from the concrete focus.
OmittedContextActions ==
    \/ \E s \in Server : MCTakeSnapshot(s)
    \/ \E m \in messages : MCDropMessage(m)

(***************************************************************************)
(* EnvUpdate: rely for the omitted context.  It may replace snapshots by   *)
(* the current applied prefix, drop messages, and consume the matching     *)
(* fault counters; it preserves every update-visible variable (logs,      *)
(* in-memory database, commit/apply state, epochs, roles, NEWLEADER       *)
(* bookkeeping, server lifecycle).                                         *)
(***************************************************************************)
EnvUpdate ==
    /\ UNCHANGED <<up, role, phase, leaderOf, acceptedEpoch, currentEpoch,
                    votes, leadersByEpoch, proposed, queued, appended,
                    durable, committed, applied, recovered, acked, commitCertified,
                    syncMode, syncSource, syncJustified, usedTxn,
                    nlAcks, newLeaderAcked, zkState, leaderSummaryEpoch>>
    \* (constructive forms so that the open spec can enumerate rely steps)
    /\ messages' \in SUBSET messages
    /\ snapshot' \in {[s \in Server |-> IF s \in S THEN applied[s] ELSE snapshot[s]] :
                        S \in SUBSET Server}
    /\ rollbackAuthorized' = [s \in Server |-> FALSE]
    /\ counters' \in [crash : {counters.crash},
                      snapshot : {counters.snapshot, counters.snapshot + 1},
                      drop : {counters.drop, counters.drop + 1}]
    /\ counters'.snapshot <= MaxSnapshot
    /\ (snapshot' /= snapshot) => counters'.snapshot = counters.snapshot + 1
    /\ counters'.drop <= MaxDrop
    /\ (messages' /= messages) => counters'.drop = counters.drop + 1
    /\ seen' \in {seen \cup X : X \in SUBSET {"snapshot", "drop"}}

UpdFullNext == MCNext /\ GhostNext
UpdFocusedNext == (AffectedActions \/ InteractionActions) /\ GhostNext
UpdOpenNext == (AffectedActions \/ InteractionActions \/ EnvUpdate) /\ GhostNext

UpdFullSpec == UpdInit /\ [][UpdFullNext]_uvars
UpdFocusedSpec == UpdInit /\ [][UpdFocusedNext]_uvars
UpdOpenSpec == UpdInit /\ [][UpdOpenNext]_uvars

\* Discharge obligation, checked over the complete MC behaviour: every
\* omitted real context step satisfies the rely (frame included).
UpdDischarge ==
    [][OmittedContextActions => EnvUpdate]_<<allVars, mcVars>>

(***************************************************************************)
(* Scenario view U-Scenario 1/2 (lost committed history): the producers   *)
(* and consumers on the path "leader logs t -> re-elected leader DIFFs t ->*)
(* learner ACKs NEWLEADER -> learner leaves (INITIAL) or crashes -> next   *)
(* election/activation".  A strict subset of MCNext used for hunting; a    *)
(* violation found here is a behaviour of the complete reference.          *)
(***************************************************************************)
LostCommitActions ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E s \in Server : MCWinElection(s)
    \/ \E s, l \in Server : MCFollowLeader(s, l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s, l \in Server : MCEnterSyncPhase(s, l)
    \/ \E s, l \in Server, mode \in SyncModes \ {"NONE"} : MCSelectSync(s, l, mode)
    \/ \E s \in Server : MCCompleteSync(s)
    \/ \E s \in Server : MCPersistCurrentEpoch(s)
    \/ \E s \in Server : MCClearSyncMode(s)
    \/ \E s \in Server : MCLogSyncProposal(s)
    \/ \E s \in Server : MCAckNewLeader(s)
    \/ \E l, s \in Server : MCCountNewLeaderAck(l, s)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E s \in Server : MCReceiveUpToDate(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)
UpdLostCommitSpec == UpdInit /\ [][LostCommitActions /\ GhostNext]_uvars

(***************************************************************************)
(* Update properties                                                       *)
(***************************************************************************)

\* REQ-EVIDENCE UpdNewLeaderAckAfterDurable
\* intent:   A learner writes its NEWLEADER ACK only after every transaction it received from the leader before NEWLEADER is recorded in persistent storage.
\* status:   requirement
\* evidence: comment quorum/Learner.java:748 "make sure sync the uncommitted logs before commit them (ACK NEWLEADER)." -> the updated source states the obligation
\* evidence: doc zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:194 "A follower will ACK the NEW_LEADER proposal after it has synced with the leader."
\* evidence: doc zookeeperInternals.md:119 "Acknowledgement means the server has recorded the proposal to persistent storage."
\* evidence: test quorum/DIFFSyncConsistencyTest.java:133-138 "followers ACK NEWLEADER (which makes leader think she has the quorum support, but actually not afterwards) but immediately fail afterwards without persisting the proposals from DIFF sync" -> the hazard the update is meant to close
\* evidence: impl quorum/FollowerZooKeeperServer.java:82-89 "syncProcessor.processRequest(request);" (enqueue only)
\* watch:    quorum/Learner.java:syncWithLeader; quorum/FollowerZooKeeperServer.java:logRequest; server/SyncRequestProcessor.java:run; server/SyncRequestProcessor.java:flush
\* verified: update
\* note:     new property (no V0 counterpart); separating state in spec/evidence/E1.
UpdNewLeaderAckAfterDurable ==
    [][\A s \in Server :
         (~newLeaderAcked[s] /\ newLeaderAcked'[s]) => IsPrefix(proposed[s], durable[s])
      ]_<<allVars, mcVars>>

\* REQ-EVIDENCE UpdEstablishedHistoryDurableOnQuorum
\* intent:   While a leader is active, everything it has committed (including the history it committed on activation) is in the persistent log of a quorum of servers.
\* status:   requirement
\* evidence: doc zookeeperInternals.md:117-119 "committed when a quorum of them acknowledge the proposal ... Acknowledgement means the server has recorded the proposal to persistent storage."
\* evidence: doc zookeeperInternals.md:196 "A new leader will COMMIT the NEW_LEADER proposal when a quorum of followers has ACKed it."
\* evidence: doc zookeeperInternals.md:247-249 "a new leader has seen all committed proposals from the previous epoch since it has seen the highest zxid from a quorum of servers"
\* watch:    quorum/Leader.java:waitForNewLeaderAck; quorum/Leader.java:lead; quorum/Leader.java:tryToCommit; quorum/Learner.java:syncWithLeader
\* verified: update
\* note:     new property; separating state in spec/evidence/E2.
UpdEstablishedHistoryDurableOnQuorum ==
    \A l \in EstablishedLeaders(role, phase, up) :
        Cardinality({s \in Server : IsPrefix(committed[l], durable[s])}) >= Quorum

\* REQ-EVIDENCE UpdLeaderCompleteness
\* intent:   An active leader's committed history contains every transaction committed by an active leader of an earlier epoch.
\* status:   requirement
\* evidence: doc zookeeperInternals.md:243-249 "why does a set of proposals believed by a new leader always contain any proposal that has actually been committed? ... a new leader has seen all committed proposals from the previous epoch"
\* evidence: doc zookeeperProgrammers.md:1177 "request or successful update, will never be rolled back when" -> a committed update is not lost across recovery
\* evidence: test quorum/DIFFSyncConsistencyTest.java:205-215 "Data inconsistency detected! Server ... should have a view of /zk..." -> the new leader must still have the old leader's committed create
\* watch:    quorum/Learner.java:syncWithLeader; quorum/Leader.java:lead; quorum/FastLeaderElection.java:lookForLeader
\* verified: update
\* note:     new interaction property (old consumer = next election/leader); separating state in spec/evidence/E3.
UpdLeaderCompleteness ==
    \A l \in EstablishedLeaders(role, phase, up) :
        \A r \in everCommitted :
            r.ep < acceptedEpoch[l] => HasEntry(committed[l], r.ent)

UpdGhostTypeOK == everCommitted \subseteq CommitRecord

\* Reachability canaries (expected to be violated): the update path is live.
UpdNotDiffPayload == "diffpayload" \notin seen
UpdNotSyncLog == "synclog" \notin seen
UpdNotNlAck == "nlack" \notin seen
UpdNotNlAckBeforeDurable == "nlackBeforeDurable" \notin seen
UpdNotUpToDate == "uptodate" \notin seen
UpdNotEstablishedWithHistory ==
    ~\E l \in EstablishedLeaders(role, phase, up) : Len(committed[l]) > 0
UpdNotLaterLeaderAfterCommit ==
    ~\E l \in EstablishedLeaders(role, phase, up) :
        \E r \in everCommitted : r.ep < acceptedEpoch[l]

=============================================================================
