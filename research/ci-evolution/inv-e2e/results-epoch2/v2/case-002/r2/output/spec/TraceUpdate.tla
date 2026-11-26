---------------------------- MODULE TraceUpdate ----------------------------
\* Evaluates the Update.tla property CommittedQuorumDurable (actual
\* definition, via INSTANCE) on the replayed states of a real trace.  A
\* violation here is an implementation witness, not a replay mismatch:
\* Trace.cfg (conformance) stays independent of this check.
EXTENDS Trace
U == INSTANCE Update WITH counters <- [crash |-> 0, drop |-> 0, snapshot |-> 0],
                          seen <- {}, everCommitted <- {},
                          MaxCrash <- 0, MaxDrop <- 0, MaxSnapshot <- 0
TraceCommittedQuorumDurable == U!CommittedQuorumDurable
=============================================================================
