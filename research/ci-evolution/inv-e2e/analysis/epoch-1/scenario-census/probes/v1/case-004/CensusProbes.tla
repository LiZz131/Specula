---- MODULE CensusProbes ----
EXTENDS Update

\* U4a: "Crash of the target after Elect but before SaveVote completes" (output/modeling-brief.md:228)
\* (same predicate as the agent's CanaryCrashBeforeSaveVote, negated)
SC_U4a == ~CanaryCrashBeforeSaveVote

\* U4b: "... or of the old leader; restart from durable vote/log" (output/modeling-brief.md:228-229);
\* "crash ... of the old leader during transfer" (output/analysis-report.md:189-190).
\* Old leader = an ElectNodes node; transfer under way = a different transfer target has voted for itself
\* in a later term.
SC_U4b == \E a \in ElectNodes, b \in TransferTargets :
            /\ a /= b /\ ~up[a]
            /\ voteNode[b] = b /\ voteTerm[b] > 1

\* U3c: "replicate/commit" by the new leader (output/modeling-brief.md:221-222)
\* (same predicate as the agent's CanaryTransferLeaderCommits, negated)
SC_U3c == ~CanaryTransferLeaderCommits

\* positive control
SC_CTRL == \E n \in Server : role[n] = "Leader"
====
