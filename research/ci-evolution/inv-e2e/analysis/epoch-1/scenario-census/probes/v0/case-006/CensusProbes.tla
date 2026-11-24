---- MODULE CensusProbes ----
EXTENDS Update

\* Positive control: some read was released (any element of readReleases).
SC_CTRL_release == readReleases /= {}

\* S6a: "releasing a FIFO prefix now frees those keys, so the duplicate guard admits a released
\* context again" (modeling-brief.md:207-209) = agent canary UpdReachReenqueue negated (UpdateProps.tla:57-58)
SC_S6a_reenqueue == \E i \in Server, c \in ReadContexts : pendingReads[i][c].inc >= 2

\* S6a: "Expectation: the pending map equals the queue; reuse is served" (analysis-report.md:234)
\* = agent canary UpdReachReuseRelease negated (UpdateProps.tla:60-61)
SC_S6a_reuse_released == \E r \in readReleases : r.inc >= 2

\* S6b: "A response generated for an earlier use of a context can therefore be counted toward a
\* later use" (modeling-brief.md:210-211) = agent canary UpdReachStaleAckCounted negated (UpdateProps.tla:64-65)
SC_S6b_stale_ack_counted == \E r \in readReleases : r.acks /= r.freshAcks

\* S6b (+ newer leader commit): "Combined with a partition in which a newer leader commits, can the
\* stale leader produce a read index below that commit?" (modeling-brief.md:252)
\* precondition: a pending read accepted with an index below an index already committed by some leader
SC_S6b_pending_below_bound ==
    \E i \in Server, c \in ReadContexts :
        pendingReads[i][c].active /\ pendingReads[i][c].index < pendingReads[i][c].bound
\* consequence: such a read released
SC_S6b_stale_read_released == \E r \in readReleases : r.index < r.bound

\* S6c: "follower-forwarded requests use the same key and delete; remote MsgReadIndexResp consumer"
\* (analysis-report.md:242-243): a forwarded request (owner /= leader) released for a reused context
SC_S6c_forwarded_reuse_released == \E r \in readReleases : r.owner /= r.leader /\ r.inc >= 2

\* S6d / MC-Q3: "Does reset (step-down/higher term) leave pending reads that a later leadership could
\* release?" (modeling-brief.md:253): a leader holding an active pending read while a higher term exists
SC_S6d_leader_pending_higher_term ==
    \E i \in Server :
        /\ role[i] = Leader
        /\ \E c \in ReadContexts : pendingReads[i][c].active
        /\ \E j \in Server : term[j] > term[i]

\* UpdPublishedFromRelease intent: "Ready/forwarded consumers publish only released reads"
\* (modeling-brief.md:244) = agent canary UpdReachPublished negated (UpdateProps.tla:76)
SC_P_published == Len(publishedReads) > 0
====
