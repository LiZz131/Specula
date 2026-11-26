---------------------------- MODULE UpdateProps ----------------------------
(* Update-specific properties (owned by the Update lens, shared with the    *)
(* trace oracle).  Behavior is owned by base.tla.                          *)
EXTENDS base

(* Update-specific properties                                              *)

\* U1 (revised durability contract that the update states in its own
\* comment, Q/Learner.java:748 "make sure sync the uncommitted logs before
\* commit them (ACK NEWLEADER)"): every entry that any leader has committed
\* -- by a NEWLEADER quorum (initial history) or by ACK quorum -- is in the
\* recoverable history of a quorum.  Scenario U-DUR.
CommittedQuorumDurable ==
    \A p \in globalCommitted :
        Cardinality({x \in Server : Len(durable[x]) >= p[1]
                                    /\ durable[x][p[1]] = p[2]}) >= Quorum

\* U2 (changed Action -> unchanged consumer): LearnerHandler.run:609-623
\* reads the first packet after NEWLEADER as the NEWLEADER ACK.  The update
\* starts the SyncRequestProcessor (which writes ACK(zxid) on the same
\* stream) before that ACK is written.  Scenario U-ACK.
NewLeaderAckFirst == \A s \in Server : ~nlAckMisread[s]

\* U3 (changed Action -> unchanged consumer): the unchanged sync-loop COMMIT
\* handler dereferences packetsNotCommitted.peekFirst() which the update
\* clears at NEWLEADER.  Scenario U-NPE.
SyncCommitHasPendingProposal == \A s \in Server : ~syncNPE[s]

\* U4 (interaction): deferred commits applied at UPTODATE / in broadcast
\* always match the head of pendingTxns, whose contents the update now
\* splits between NEWLEADER and UPTODATE (FollowerZooKeeperServer.commit
\* would System.exit on a mismatch).  Scenario U-SPLIT.
DeferredCommitMatchesPending == \A s \in Server : ~unmatchedCommit[s]

UpdateProperties ==
    CommittedQuorumDurable /\ NewLeaderAckFirst /\
    SyncCommitHasPendingProposal /\ DeferredCommitMatchesPending

=============================================================================
