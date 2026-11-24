---- MODULE CensusProbes ----
EXTENDS base

CActive == {i \in Server : leaderActive[i]}
PosOf(p, j) == CHOOSE k \in 1..Len(p.order) : p.order[k] = j

\* U1a. "A membership entry upgrades the progress (`upgrade_quorum_set`, progress/mod.rs:222-232)"
\* (output/modeling-brief.md:162). Encoded: an active leader progress with a joint quorum set.
SC_U1a == \E i \in CActive : Cardinality(progress[i].cfg) = 2

\* U1b. "replaying old values in id order; ties leave a smaller-id follower ahead of the leader"
\* (output/modeling-brief.md:162). Encoded: after an upgrade, a follower with a value equal to the
\* leader's sits before the leader in the vector.
SC_U1b == \E i \in CActive :
    LET p == progress[i] IN
    /\ Cardinality(p.cfg) = 2 /\ i \in SeqElems(p.order)
    /\ \E a \in 1..Len(p.order) : a < PosOf(p, i) /\ p.val[p.order[a]] = p.val[i]

\* U1c. "The leader's next value is stored in place without reordering ... when its previous value is
\* above the (reset) progress committed" (output/modeling-brief.md:162). Encoded: the leader's value
\* is above committed and greater than a value stored before it in the vector.
SC_U1c == \E i \in CActive :
    LET p == progress[i] IN
    /\ i \in SeqElems(p.order) /\ LogLT(p.committed, p.val[i])
    /\ \E a \in 1..Len(p.order) : a < PosOf(p, i) /\ LogLT(p.val[p.order[a]], p.val[i])

\* U1d. "so a later acknowledgement recomputes over a prefix that includes a lagging node"
\* (output/modeling-brief.md:162). Encoded: the progress committed value is not supported by a quorum.
SC_U1d == \E i \in CActive :
    progress[i].committed /= NoLog /\ ~QuorumAt(progress[i], progress[i].committed)

\* U1e. "Expected: commit only with a quorum of every group (joint)" (output/analysis-report.md:103)
\* Encoded: a leader commit witnessed under a joint (two-group) membership.
SC_U1e == \E i \in Server : witnessIndex[i] /= Nil /\ Cardinality(witnessConfig[i]) = 2

\* U2. "Uniform config, client append + acknowledgements through `update_progress`"
\* (output/modeling-brief.md:170). Encoded: a leader commit witnessed under a uniform config.
SC_U2 == \E i \in Server :
    role[i] = "leader" /\ committed[i] /= Nil /\ witnessIndex[i] /= Nil
    /\ Cardinality(witnessConfig[i]) = 1

\* U3a. "follower membership promotion only on commit advance" (output/modeling-brief.md:172-174)
SC_U3a == \E i \in Server : role[i] = "follower" /\ committedMembershipIndex[i] /= Nil

\* U3b. "(`FollowerCommitEntries` with no commit advance)" (output/analysis-report.md:105) vs the old
\* "promote committed membership whenever `committed >= effective`" (output/analysis-report.md:81).
\* Encoded: a follower whose commit covers its effective membership entry that is not promoted.
SC_U3b == \E i \in Server :
    /\ role[i] = "follower" /\ effectiveMembershipIndex[i] /= Nil
    /\ effectiveMembershipIndex[i] > committedMembershipIndex[i]
    /\ committed[i] >= effectiveMembershipIndex[i]

\* U3c. "(`FollowerCommitEntries` with no commit advance)" (output/analysis-report.md:105)
\* Encoded (weaker than U3b): a follower holding an uncommitted membership entry has a pending
\* append whose leader commit does not exceed its current commit (delivery cannot advance it).
SC_U3c == \E i \in Server :
    /\ role[i] = "follower" /\ i \notin crashed
    /\ effectiveMembershipIndex[i] > committedMembershipIndex[i]
    /\ \E m \in messages : m.type = "append" /\ m.to = i /\ m.leaderCommit <= committed[i]

\* U4. "grants are counted by `Leader::is_vote_granted`" (output/modeling-brief.md:178)
\* Encoded: a leader elected with at least one grant from another node.
SC_U4 == \E i \in Server : role[i] = "leader" /\ voteGranted[i] /= {i}

\* Positive control.
SC_CTRL == \E i \in Server : role[i] = "leader"

====
