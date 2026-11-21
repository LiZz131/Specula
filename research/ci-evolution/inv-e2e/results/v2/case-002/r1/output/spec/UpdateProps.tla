---------------------------- MODULE UpdateProps ----------------------------
(* Update-specific property predicates over the reference (base) variables.
   Kept in a separate module so the SAME definitions are evaluated by the
   update model checks (Update.tla), the trace witnesses (TraceWitness.tla)
   and the divergence-evidence states (spec/evidence/).  Scenario labels
   U1-U4 refer to modeling-brief.md section 8. *)
EXTENDS base

\* REQ-EVIDENCE NewLeaderAckDurable
\* intent:   When a learner sends its ACK of NEWLEADER, the history it received in that synchronization is recorded in its persistent storage.
\* status:   requirement
\* evidence: doc zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:194 "A follower will ACK the NEW_LEADER proposal after it has synced with the leader." -> the NEWLEADER ACK follows synchronization
\* evidence: doc zookeeperInternals.md:119 "Acknowledgement means the server has recorded the proposal to persistent storage." -> an ACK certifies persistence
\* evidence: comment new-source Learner.java:757 "make sure sync the uncommitted logs before commit them (ACK NEWLEADER)." -> the update's own stated contract
\* evidence: doc zookeeperInternals.md:196-197 "A new leader will COMMIT the NEW_LEADER proposal when a quorum of followers has ACKed it." -> the leader relies on these ACKs to commit
\* watch:    Learner.java:syncWithLeader; FollowerZooKeeperServer.java:logRequest; SyncRequestProcessor.java:run
\* verified: update
\* note:     added property (old verdict: not checked). Scenario U1.
NewLeaderAckDurableStep ==
    \A s \in Server :
        (~nlAckSent[s] /\ nlAckSent'[s]) => IsPrefix(recovered[s], durable'[s])

\* REQ-EVIDENCE CommittedDurableOnQuorum
\* intent:   Every committed transaction is in the persistent log of at least a quorum of servers.
\* status:   requirement
\* evidence: doc zookeeperInternals.md:117-119 "committed when a quorum of them acknowledge the proposal ... Acknowledgement means the server has recorded the proposal to persistent storage."
\* evidence: doc zookeeperInternals.md:180 "Since committed proposals must be seen by a quorum of servers"
\* watch:    Leader.java:tryToCommit; Leader.java:waitForNewLeaderAck; Learner.java:syncWithLeader
\* verified: update
\* note:     added property; Scenario U1/U2. Durable (not merely queued) is required because a crash discards queued records.
CommittedDurableOnQuorum ==
    \A t \in Txn :
        commitCertified[t] =>
            Cardinality({s \in Server : t \in TxnIds(durable[s])}) >= Quorum

\* REQ-EVIDENCE LeaderCompleteness
\* intent:   A leader that activates in a later epoch serves every transaction committed in an earlier epoch.
\* status:   requirement
\* evidence: doc zookeeperInternals.md:59 "message `m` will be eventually delivered by all servers." -> a committed transaction is never lost
\* evidence: doc zookeeperProgrammers.md:1177 "request or successful update, will never be rolled back when" -> a committed update survives recovery
\* evidence: doc zookeeperInternals.md:197 "A follower will commit any state it received from the leader when the NEW_LEADER proposal is COMMIT."
\* watch:    Leader.java:lead; LearnerHandler.java:syncFollower; Learner.java:syncWithLeader; FastLeaderElection.java:lookForLeader
\* verified: update
\* note:     added consequence property for Scenario U2 (crash inside the ACK/fsync window).
LeaderCompleteness ==
    \A l \in Server :
        (up[l] /\ role[l] = "leading" /\ phase[l] = "broadcast") =>
            \A t \in Txn :
                (commitCertified[t] /\ certEpoch[t] < acceptedEpoch[l]) =>
                    t \in TxnIds(committed[l])

\* REQ-EVIDENCE SyncedLogMatchesLeader
\* intent:   After a follower completes synchronization, its persistent log holds no transaction that its current leader does not have (no "ghost" transaction); duplicates of the leader's transactions are tolerated.
\* status:   requirement
\* evidence: doc zookeeperInternals.md:182-183 "When the follower connects to the leader, the leader will tell the follower to discard `U`." -> proposals the leader does not have must not survive synchronization
\* evidence: contract TxnLog.java:83 "truncate the log to get in sync with the" -> the log is brought in sync with the leader
\* evidence: doc zookeeperAdmin.md:2599 "idempotent nature of its updates. By replaying the transaction log" -> re-logged (duplicate) transactions are tolerated on replay
\* watch:    LearnerHandler.java:syncFollower; Learner.java:syncWithLeader; ZooKeeperServer.java:shutdown; LearnerZooKeeperServer.java:shutdown
\* verified: update
\* note:     revised (Case A, spec/changelog.md): the first formulation (durable/committed prefix-comparable) also rejected a duplicated record of a committed transaction, which the idempotent replay design tolerates (separating state spec/evidence/E5).
SyncedLogMatchesLeader ==
    \A s \in Server :
        (up[s] /\ role[s] = "following" /\ phase[s] = "broadcast"
           /\ leaderOf[s] \in Server /\ up[leaderOf[s]]) =>
            TxnIds(durable[s]) \subseteq TxnIds(proposed[leaderOf[s]])

\* REQ-EVIDENCE PendingOnlyDuringSync
\* intent:   The learner sync buffer is non-empty only while that learner is synchronizing.
\* status:   model-internal
\* verified: update
PendingOnlyDuringSync ==
    \A s \in Server :
        pendingSync[s] /= <<>> => (role[s] = "following" /\ phase[s] = "sync")

=============================================================================
