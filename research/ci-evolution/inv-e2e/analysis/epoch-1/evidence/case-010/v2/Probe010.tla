---- MODULE Probe010 ----
\* Decision probes for the case-010 evidence card. Adds no actions; only action properties.
EXTENDS Update
\* exit step: LearnerExit (FOLLOWING -> LOOKING with the learner session reset), process alive.
ExitStep(f) == role[f] = "FOLLOWING" /\ role'[f] = "LOOKING" /\ learnerStage'[f] = "IDLE" /\ running'[f]
\* the arm's own notion of a serving learner server (canShutdown)
Serving(f) == LearnerZkRunning(f)   \* v2 base.tla:704
\* Loss at exit: a record already handed to the sync processor (syncQueued) is not in the
\* durable log right after the exit step.  Old code: LearnerZooKeeperServer.shutdown() ->
\* syncProcessor.shutdown() drains and flushes before returning (LearnerZooKeeperServer.java:154-173,
\* SyncRequestProcessor.java:251-270); new code bypasses it (Learner.java:864).
LostAtExit(f) == \E t \in Elems(syncQueued[f]) : t \notin Elems(durable'[f])
ServingExitLoss(f) == ExitStep(f) /\ Serving(f) /\ LostAtExit(f)
ProbeNoServingExitLoss == [][\A f \in Server : ~ServingExitLoss(f)]_mcvars

\* Frame canary: a serving learner exits while its sync queue is non-empty (the precondition).
ProbeNoServingExitWithQueue ==
    [][\A f \in Server : ~(ExitStep(f) /\ Serving(f) /\ syncQueued[f] # <<>>)]_mcvars

\* The sync thread survives the serving exit (leakedQueued is the arm's leaked-thread queue).
ProbeNoServingExitThreadAlive ==
    [][\A f \in Server : ~(ExitStep(f) /\ Serving(f) /\ leakedQueued'[f] # leakedQueued[f])]_mcvars
====
