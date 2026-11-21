---------------------------- MODULE UpdateProps ----------------------------
(***************************************************************************)
(* Update-specific properties for case-010, over reference (base) state    *)
(* only, so that they can be checked by MC/Update campaigns and evaluated  *)
(* on replayed implementation traces (TraceUpdate).                         *)
(***************************************************************************)
EXTENDS base

\* REQ-EVIDENCE UpdIdleDbBackedByDisk
\* intent:   a running peer that holds an initialized in-memory database between following sessions (about to report getLastLoggedZxid to an election or a leader) holds no transaction that is absent from its transaction log/snapshots or still queued to a sync processor
\* status:   mixed
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java:1619 testDiffSyncAfterSnap "If learner failed to do SNAP sync with leader before it's writing" -> a learner that failed sync before persisting must not carry the unpersisted state into a DIFF sync or a leadership
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java:1623 testDiffSyncAfterSnap "This test is trying to guarantee there is no data inconsistency for" -> after reload from disk the learner must still have every node it reported (assertion :1733)
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:862 "If we haven't finished SNAP sync, force fully shutdown" -> unpersisted sync state must not be reused (line 863 "to avoid potential inconsistency")
\* evidence: comment source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:842 "When a new quorum is established we can still apply the diff" -> reusing the database is justified only when a DIFF on top of it is correct, i.e. when it matches the logged history
\* evidence: impl source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java:1258 "if (!zkDb.isInitialized()) {"
\* watch:    Learner.java:shutdown; Learner.java:syncWithLeader; ZooKeeperServer.java:shutdown; ZKDatabase.java:clear; QuorumPeer.java:getLastLoggedZxid
\* verified: update (case-010)
\* clause no-unpersisted-reuse: requirement — test doc/assertion QuorumPeerMainTest.java:1619-1623,1733 and the update comment Learner.java:862-863
\* clause queued-or-leaked-allowed: impl-abstraction — entries still owned by a running sync processor will be logged by it (SyncRequestProcessor.java:155-270); the formula does not flag them
\* review:   new for case-010
UpdIdleDbBackedByDisk ==
    \A s \in Server :
        (running[s] /\ dbInitialized[s] /\ learnerStage[s] = "IDLE") =>
            \A t \in Elems(recoveryVisible[s]) :
                t \in Elems(durable[s]) \cup Elems(syncQueued[s]) \cup Elems(leakedQueued[s])

\* REQ-EVIDENCE UpdDurableCoversCommitted
\* intent:   a server's recoverable log never holds a transaction while missing an earlier globally committed transaction (a restart from disk would silently lose that committed transaction while reporting the later zxid)
\* status:   requirement
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:229 "has been written to non-volatile storage, all messages that were proposed before" -> a logged proposal implies all earlier proposals are logged
\* evidence: test source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java:1733 testDiffSyncAfterSnap "assertNotNull(zk[followerA].exists(nodePath + i, false), \"node \" + i + \" should exist\");" -> after restart from disk every committed node created before the last one exists
\* evidence: doc source/zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md:242 "believed by a new leader always contain any proposal that has actually been committed" -> committed proposals are never dropped from a server that may lead
\* watch:    Learner.java:shutdown; Learner.java:syncWithLeader; SyncRequestProcessor.java:run; FileTxnLog.java:append; LearnerZooKeeperServer.java:shutdown
\* verified: update (case-010)
\* review:   new for case-010; it is the end-to-end consequence checked by the diff's own test
UpdDurableCoversCommitted ==
    \A s \in Server :
        \A i \in 1..Len(durable[s]) :
            \A c \in Elems(globalCommitted) :
                c < durable[s][i] => c \in Elems(durable[s])

=============================================================================
