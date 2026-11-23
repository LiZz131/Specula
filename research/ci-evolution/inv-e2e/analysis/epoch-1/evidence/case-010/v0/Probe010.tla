---- MODULE Probe010 ----
\* Decision probes for the case-010 evidence card. Adds no actions; only action properties.
EXTENDS Update
\* v0 exit step: LearnerShutdown (base.tla:311) moves syncStage to EXITED.
ExitStep(f) == syncStage[f] # "EXITED" /\ syncStage'[f] = "EXITED" /\ running'[f]
\* v0's own notion of a serving server (canShutdown): zkRunning == syncComplete[f] (base.tla:318)
Serving(f) == syncComplete[f]
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
\* The prior-suite SyncEntryJustified, verbatim from the old model (blind-incremental-v0 case-010
\* spec/base.tla:582-587), for the "was v0's relaxation needed / what did it let through" check.
SyncEntryJustifiedOrig ==
    \A s \in Server :
        running[s] /\ phase[s] = "BROADCAST"
        => IF role[s] = "LEADING" THEN newLeaderReady[s]
           ELSE IF role[s] = "FOLLOWING" THEN syncComplete[s]
           ELSE FALSE
\* v0's final form minus only its first relaxation (syncStage # "EXITED"), to see what that one lets through.
SyncEntryJustifiedNoExitedExemption ==
    \A s \in Server :
        running[s] /\ phase[s] = "BROADCAST"
        /\ role[s] \in {"LEADING", "FOLLOWING"}
        => IF role[s] = "LEADING" THEN newLeaderReady[s] ELSE syncComplete[s]
====
