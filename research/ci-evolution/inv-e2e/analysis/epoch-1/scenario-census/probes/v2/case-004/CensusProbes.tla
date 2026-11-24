---- MODULE CensusProbes ----
EXTENDS MC
\* Census precondition probes for v2/case-004 (state predicates only; no actions).
\* transferLog (MC history) holds <<node, term>> of elections started by TransferLeader;
\* grantLog holds <<node, term, votedFor, committed>> flushed votes.

\* U1 "Affected: TransferLeader at the target -> Elect at last_seen.term+1" (output/modeling-brief.md:213-214)
SC_U1a == transferLog /= {}
\* U1 consumers "handle_vote_resp / establish_leader" (output/modeling-brief.md:215-216)
SC_U1b == \E n \in Server : role[n] = "Leader" /\ <<n, voteTerm[n]>> \in transferLog
\* U1 "the old leader stepping down on the higher vote" (output/modeling-brief.md:216)
SC_U1c == \E n, m \in Server : n /= m /\ <<m, voteTerm[n]>> \in transferLog
                               /\ role[n] = "Follower" /\ voteNode[n] = m /\ voteTerm[n] > 1
\* U1 "replication and commit by the new leader" (output/modeling-brief.md:216-217)
SC_U1d == \E n \in Server : leader[n] /\ <<n, voteTerm[n]>> \in transferLog /\ commitIndex[n] > 0
                            /\ EntryAt(n, commitIndex[n]).term = voteTerm[n]

\* U2 "A learner whose vote equals the leader's committed vote ... therefore campaigns" (output/modeling-brief.md:225-226)
SC_U2a == \E n \in Server : candidate[n] /\ n \in learners[n]
\* U2 "The same happens to a voter demoted to learner by a membership change that reaches it before
\* the transfer message" (output/modeling-brief.md:229-230) -> an initial voter that is now a learner
SC_U2b == \E n \in InitialVoters : up[n] /\ n \in learners[n] /\ n \notin Voters(configs[n])
\* U2 "a quorum of voter grants makes it Leader" (output/modeling-brief.md:228-229)
SC_U2c == \E n \in Server : role[n] = "Leader" /\ n \notin Voters(configs[n])

\* U4 "Target crashes after Elect but before SaveVote completes" (output/modeling-brief.md:246)
SC_U4a == \E n \in Server : ~up[n] /\ (\E t \in 0..MaxTerm : <<n, t>> \in transferLog)
                            /\ durableVoteTerm[n] < voteTerm[n]
\* U4 "or after granting peers flushed" (output/modeling-brief.md:246-247)
SC_U4b == \E n \in Server : ~up[n] /\ \E t \in 0..MaxTerm :
              /\ <<n, t>> \in transferLog
              /\ \E p \in Server \ {n} : <<p, t, n, FALSE>> \in grantLog

\* ElectionByVoterOnly intent "learners and removed nodes never try to elect themselves"
\* (output/spec/Update.tla:89) -> removed-node situation: an initial voter no longer a member
SC_P_EBVOr == \E n \in InitialVoters : n \notin Voters(configs[n]) /\ n \notin learners[n]

\* NoRaftCorePanic intent "No node's RaftCore task terminates by panicking while handling protocol
\* messages." (output/spec/Update.tla:105) -> a learner candidate processes a grant (panic path precondition)
SC_P_NRP == \E n \in Server : candidate[n] /\ ~(n \in Voters(candidateConfigs[n]))
                              /\ \E t \in 0..MaxTerm : <<n, t, n, FALSE>> \in grantLog

\* Positive control: some node is Leader.
SC_CTRL == \E n \in Server : role[n] = "Leader"
====
