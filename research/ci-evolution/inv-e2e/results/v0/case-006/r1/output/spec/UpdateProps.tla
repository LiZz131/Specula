---------------------------- MODULE UpdateProps ----------------------------
(***************************************************************************
 * Update-specific properties and reachability canaries for Scenario 6.
 * Single owner of these definitions; extended by Update.tla (model checking)
 * and Trace.tla (replayed states).  Reads only reference variables.
 *************************************************************************)
EXTENDS base

(***************************************************************************
 * Update properties.
 *************************************************************************)
InQueue(i, c) == \E k \in 1..Len(readQueue[i]) : readQueue[i][k] = c

\* New (Scenario 6, read_only.go:100-105): the pending map holds exactly the
\* queued contexts.  The exact-old delete left released entries behind.
UpdPendingQueueAgreement ==
    \A i \in Server, c \in ReadContexts :
        pendingReads[i][c].active <=> InQueue(i, c)

\* Structural (read_only.go:54-58): the queue never holds a context twice.
UpdQueueNoDuplicates ==
    \A i \in Server : \A k1, k2 \in 1..Len(readQueue[i]) :
        k1 /= k2 => readQueue[i][k1] /= readQueue[i][k2]

\* Revised V0 property (Scenario 6): a delivered read index must be
\* justified by quorum acknowledgement for the corresponding pending request:
\* responses generated after that request (incarnation) was accepted, plus
\* the leader itself (raft.go:824-837, 903-932; the ReadIndex confirmation
\* round).  Revision r2: the r1 form required responses to heartbeats *sent*
\* for the incarnation; the implementation correlates acknowledgements only by
\* context and a response generated after acceptance already confirms
\* leadership, so r1 flagged benign delayed-heartbeat interleavings (Case A,
\* spec/changelog.md).
UpdReadAckAfterEnqueue ==
    \A r \in readReleases : Cardinality(r.freshAcks) >= Quorum

\* Interaction (Scenario 6, consumer-visible): a released read index is at
\* least every index any leader had committed when the leader accepted the
\* request (ReadIndex linearizability; raft.go:824-837, 915-932).
UpdReadIndexLinearizable ==
    \A r \in readReleases : r.index >= r.bound

\* Interaction (Scenario 6): Ready and the follower response path only
\* publish reads produced by a release (node.go:506-525, raft.go:1075-1080).
UpdPublishedFromRelease ==
    \A k \in 1..Len(publishedReads) :
        \E r \in readReleases :
            /\ r.leader = publishedReads[k].leader
            /\ r.owner = publishedReads[k].owner
            /\ r.ctx = publishedReads[k].ctx
            /\ r.index = publishedReads[k].index

(***************************************************************************
 * Reachability canaries (negated; a violation is the expected witness).
 *************************************************************************)
\* A context released once and enqueued again by the same leader.
UpdReachReenqueue ==
    ~\E i \in Server, c \in ReadContexts : pendingReads[i][c].inc >= 2
\* A reused context released again.
UpdReachReuseRelease ==
    ~\E r \in readReleases : r.inc >= 2
\* A release whose counted acknowledgement set includes a response generated
\* before the released incarnation was accepted.
UpdReachStaleAckCounted ==
    ~\E r \in readReleases : r.acks /= r.freshAcks
\* A forwarded request released and answered remotely.
UpdReachRemoteRelease ==
    ~\E r \in readReleases : r.owner /= r.leader
\* A FIFO prefix release: two requests released by one acknowledgement set.
UpdReachPrefixRelease ==
    ~\E r1, r2 \in readReleases :
        /\ r1 /= r2 /\ r1.leader = r2.leader /\ r1.term = r2.term
        /\ r1.ctx /= r2.ctx /\ r1.acks = r2.acks
        /\ r1.freshAcks = r2.freshAcks
\* A published read.
UpdReachPublished == Len(publishedReads) = 0

=============================================================================
