---- MODULE Probe_v2c011_S09 ----
\* Dismissal (modeling-brief.md:368-369): "Timer-only rounds are protected by the RPC timeout
\* (modeled after the Case B repair)."
\* Canary (action): a granted Pre-Vote response from an EARLIER round (m.round /= preRound[i]) is
\* counted while the current round was started by the timer.
EXTENDS Update
Canary == \E i \in Server : \E m \in messages :
            /\ CountedPreVoteGrant(i, m)
            /\ m.round /= preRound[i]
            /\ preCandidateByTimer[i]
NotCanaryAct == [][~Canary]_vars
====
