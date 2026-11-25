--------------------------- MODULE EvidenceTrace ---------------------------
(***************************************************************************
 * Evidence lens over validated implementation traces (Trace.tla replay).  *
 * Trace wrappers construct the delivered response instead of consuming it *
 * from `messages`, so message-consumption observers of UpdateProps are    *
 * not applicable here; these step predicates observe the same effects     *
 * through state only. A violation reported by TLC is a trace-sourced      *
 * witness that the implementation performs the transition.                *
 *************************************************************************)
EXTENDS Trace, UpdateProps

\* Effect targeted by TimerPreVoteElectionFromFollowerState: an established
\* Leader drops its pre-candidate and starts the pre-voted election.
LeaderAbandonsForPreVote(i) ==
    /\ role[i] = "Leader"
    /\ preCandidateActive[i] /\ ~preCandidateActive'[i]
    /\ ElectedNow(i)
    /\ vote'[i] = preCandidateVote[i]
EvLeaderNeverAbandonsForPreVote ==
    [][\A i \in Server : ~LeaderAbandonsForPreVote(i)]_traceVars

\* Effect targeted by PreVoteResponseNeverPanics: no step stops the node.
EvNoPanic == [][\A i \in Server : ~PanickedNow(i)]_traceVars
=============================================================================
