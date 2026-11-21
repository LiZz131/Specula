------------------------- MODULE UpdateProps -------------------------
(***************************************************************************
 * Update-specific read properties owned by Update.tla (kept in a base-only
 * module so Trace.tla can evaluate the identical definitions on replayed
 * implementation states).  See spec/invariant-evidence.json for decisions.
 *************************************************************************)
EXTENDS base

(***************************************************************************
 * Update properties.
 *************************************************************************)

\* Scenario US1 (release frees the request).  Strengthening, added.
\* requirement: raft_test.go:1249-1296 TestRaftFreesReadOnlyMem asserts that
\* both readIndexQueue and pendingReadIndex are empty after the quorum ack;
\* read_only.go:111-118 and raft.go:457-464 treat the queue as the pending set.
\* reference: base!HandleHeartbeatResponse, base!ProcessReadIndex, reset sites.
PendingMatchesQueue ==
    \A i \in Server : \A c \in ReadContexts :
        pendingReads[i][c].active <=>
            \E k \in 1..Len(readQueue[i]) : readQueue[i][k] = c

\* Structural guard for FIFO advance (read_only.go:87-104): a context occurs at
\* most once in the queue, so the released prefix is well defined.
ReadQueueDistinct ==
    \A i \in Server : \A k1, k2 \in 1..Len(readQueue[i]) :
        k1 /= k2 => readQueue[i][k1] /= readQueue[i][k2]

\* Scenario US3 (revision of base!ReadDeliveryJustified, strengthening).
\* The V0 property counted acknowledgements only.  The scope promise is a
\* quorum acknowledgement "for the corresponding pending request"; with the
\* update a context can be pending again in the same term, so an ack produced
\* for an earlier instance must not count.  fresh = peers that processed a
\* heartbeat for this context while this instance was pending (ghost).
\* requirement: node.go:154-157 and rawnode.go:258-261 (read index valid for
\* reads issued before the request), README.md:27-29 (leader checks with quorum
\* before serving read-only queries).
ReadDeliveryJustifiedFresh ==
    \A k \in 1..Len(publishedReads) :
        /\ Cardinality(publishedReads[k].acks) >= Quorum
        /\ Cardinality(publishedReads[k].acks \cap publishedReads[k].fresh)
             >= Quorum

\* Scenario US4 (new consumer-visible property).  A delivered ReadState must
\* cover every entry any leader had committed when the request was accepted.
\* requirement: node.go:154-157, node.go:63-66, rawnode.go:258-261,
\* README.md:27-32 (linearizable read-only queries).
ReadIndexFreshness ==
    \A k \in 1..Len(publishedReads) :
        publishedReads[k].index >= publishedReads[k].floor

UpdateSafety ==
    /\ PendingMatchesQueue
    /\ ReadQueueDistinct
    /\ ReadDeliveryJustifiedFresh
    /\ ReadIndexFreshness

=============================================================================
