---- MODULE CensusProbes ----
EXTENDS Update

\* Positive control: a leader was elected (agent canary NotElectionReached negated, MC.tla:144).
SC_CTRL_leader == "leader" \in seen

\* U-NPE: "COMMIT of a pre-NEWLEADER proposal arrives after NEWLEADER" (modeling-brief.md:30)
\* (same condition as the agent's canary NotCommitAfterNewLeaderReached, MC.tla:42,150)
SC_UNPE == "commitAfterNewLeader" \in seen

\* U-NPE consequence: "the unchanged COMMIT handler dereferences packetsNotCommitted.peekFirst()
\* without a null check" (modeling-brief.md:34-35) -> NPE branch recorded in syncError
SC_UNPE_npe == \E e \in syncError : e.kind = "NPE"

\* U-DUR: "NEWLEADER ACK before the synchronised history is durable" (modeling-brief.md:42)
SC_UDUR == "nlAckNotDurable" \in seen

\* U-EPOCH crash case: "setCurrentEpoch(newEpoch) is forced before the DIFF entries are durable
\* (crash case)" (modeling-brief.md:51-52) -> a crashed server whose forced log lacks its epoch history
SC_UEPOCH_crash == \E s \in Server : ~up[s] /\ ~IsPrefix(epochTarget[s], durable[s])

\* U-EPOCH non-crash case: "an exception between NEWLEADER and UPTODATE leaves the server in INITIAL ...
\* getLastLoggedZxid() (FLE vote) reports the pre-sync position with the new epoch" (modeling-brief.md:52-54)
SC_UEPOCH_nocrash == \E s \in Server : up[s] /\ role[s] = "looking" /\ ~IsPrefix(epochTarget[s], DbPos(s))

\* U-LOSS: "changed NEWLEADER window -> crash or INITIAL exit -> election by epoch ->
\* TRUNC/missing history at the new leader" (modeling-brief.md:60-61)
\* (a) INITIAL-exit variant: no crash happened, an established leader misses committed history
SC_ULOSS_initial == counters.crash = 0 /\
    \E l \in Server : Established(l) /\ ~IsPrefix(everCommitted, committed[l])
\* (b) crash variant: a crash happened, an established leader misses committed history
SC_ULOSS_crash == "crash" \in seen /\
    \E l \in Server : Established(l) /\ ~IsPrefix(everCommitted, committed[l])
====
