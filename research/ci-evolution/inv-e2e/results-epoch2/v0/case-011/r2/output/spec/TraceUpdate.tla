--------------------------- MODULE TraceUpdate ---------------------------
(***************************************************************************
 * Evaluate Update.tla properties on implementation traces. Used to show   *
 * that the real Engine (not only the model) reaches the MC-1 state.       *
 ***************************************************************************)
EXTENDS Trace

CONSTANTS MaxElectionCount, MaxMembershipCount, MaxCrashCount, MaxDropCount,
          MaxMessageCount, MaxPreElectCount, AllowAdminElect

U == INSTANCE Update WITH
        faultCounters <- [election |-> 0, preElect |-> 0, membership |-> 0,
                          crash |-> 0, drop |-> 0, env |-> 0]

TraceLeaderVoteCoversLocalVote == U!LeaderVoteCoversLocalVote
TracePreCandidateTracksNextTerm == U!PreCandidateTracksNextTerm
=============================================================================
