---- MODULE TraceEvidence ----
\* Evaluates update properties on TLC-validated trace replays. The bodies are
\* Update!LeaderObjectVoteNotBehind and Update!PreVoteRoundNotOutlivedByOwnLeadershipStep
\* restated over the Trace replay (in a replay the Pre-Vote response is
\* constructed from the event, not taken from `messages`, so the step is
\* recognised by the event name instead of by message consumption).
EXTENDS Trace
LeaderObjectVoteNotBehind ==
    \A i \in Server : (leaderActive[i] /\ ~crashed[i]) => VoteLE(vote[i], leaderVote[i])
TracePreVoteElectStep(i) ==
    /\ cursor \in 1..Len(TraceLog)
    /\ cursor' = cursor + 1
    /\ TraceLog[cursor].name = "HandlePreVoteResponse"
    /\ preCandidateActive[i] /\ ~preCandidateActive'[i] /\ vote'[i] /= vote[i]
PreVoteRoundNotOutlivedByOwnLeadershipT ==
    [][\A i \in Server : TracePreVoteElectStep(i) => (role[i] = "Leader" => preRoundFromLeader[i])]_traceVars
====
