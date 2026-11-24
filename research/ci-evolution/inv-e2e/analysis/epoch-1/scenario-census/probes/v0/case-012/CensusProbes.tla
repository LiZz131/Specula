---- MODULE CensusProbes ----
EXTENDS MC

\* Positive control: some node is leader.
SC_PC == \E i \in Server : role[i] = "leader"

\* U1a: "Update Scenario U1: cached VecProgress commit on the leader commit path ... LeaderState::
\* handle_update_matched -> Engine::update_progress -> VecProgress::update" (output/modeling-brief.md:160-163).
\* Precondition: a leader has committed through the progress (commit witness set).
SC_U1a == \E i \in Server : role[i] = "leader" /\ committed[i] # Nil /\ witnessIndex[i] # Nil

\* U1b: "`committed` is re-derived only when an updated value crosses it; values above it are raised
\* in place" (output/modeling-brief.md:163-164). Precondition: a leader progress with a cached committed
\* value and an entry above it.
SC_U1b ==
    \E i \in Server :
        /\ leaderSome[i] /\ progCommitted[i] # 0
        /\ \E k \in DOMAIN progVec[i] : progVec[i][k].val > progCommitted[i]

\* U2a: "early return when `matched <= committed`" (output/modeling-brief.md:171). Precondition: a
\* positive ack at or below the leader's committed index can be handled.
SC_U2a ==
    \E m \in messages :
        /\ m.type = "ack" /\ m.ok /\ m.last <= committed[m.to]
        /\ ENABLED MCHandleUpdateMatched(m)

\* U2b: "leader self-progress only on append" (output/modeling-brief.md:171-172). Precondition: a leader
\* holding progress can append (client entry or membership entry).
SC_U2b ==
    \E i \in Server :
        /\ role[i] = "leader" /\ leaderSome[i] /\ ~blankPending[i]
        /\ ENABLED (MCClientAppend(i) \/ \E g \in Goals : MCProposeMembership(i, g))

\* U3: "membership change rebuilds the progress ... leader_append_entries -> update_effective_membership
\* -> upgrade_quorum_set" (output/modeling-brief.md:176-178). Precondition: a leader whose progress quorum
\* set was upgraded to a joint config.
SC_U3 ==
    \E i \in Server : role[i] = "leader" /\ leaderSome[i] /\ Cardinality(progQS[i]) = 2

\* U3b: "Rebuild replays old ids in ascending id order through update; ties keep insertion order, so a
\* lower-id follower that has caught up can precede the leader" (output/analysis-report.md:133-135).
SC_U3b ==
    \E i \in Server :
        /\ role[i] = "leader"
        /\ \E k \in DOMAIN progVec[i] : k > 1 /\ progVec[i][k].id = i /\ progVec[i][k].val > 0

\* X13: "a joint quorum set in which the tied prefix {lower-id follower, leader} is not a quorum leaves
\* both above committed; the leader's next append raises its own value in place"
\* (output/analysis-report.md:140-143). Precondition: joint progress quorum set, the leader's own entry
\* not first and above committed.
SC_X13 ==
    \E i \in Server :
        /\ role[i] = "leader" /\ Cardinality(progQS[i]) = 2
        /\ \E k \in DOMAIN progVec[i] :
              k > 1 /\ progVec[i][k].id = i /\ progVec[i][k].val > progCommitted[i]

\* U4a: "stale progress must not survive a re-election" (output/analysis-report.md:137-138); "elect/
\* new_leader" (output/modeling-brief.md:184). Precondition: a leader of a later term whose fresh progress
\* recorded a follower acknowledgement.
SC_U4a ==
    \E i \in Server :
        /\ role[i] = "leader" /\ currentTerm[i] >= 2
        /\ \E k \in DOMAIN progVec[i] : progVec[i][k].id # i /\ progVec[i][k].val > 0

\* U4b: "internal_handle_vote_req clearing the Leader" (output/modeling-brief.md:184-185). Precondition: a
\* node holding a Leader can grant a vote.
SC_U4b == \E c, v \in Server : leaderSome[v] /\ ENABLED MCGrantVote(c, v)

\* U4c: "crash/restart (no Leader)" (output/modeling-brief.md:185). Precondition: a node holding a Leader
\* can crash.
SC_U4c == \E i \in Server : leaderSome[i] /\ ENABLED MCCrash(i)

\* U4d: "Deliver/Reject clearing the Leader" (output/analysis-report.md:136-137). Precondition: a node
\* holding a Leader can accept or reject an append and thereby drop the Leader.
SC_U4d ==
    \E m \in messages :
        /\ m.type = "append" /\ leaderSome[m.to]
        /\ ENABLED ((MCDeliverAppendEntries(m) \/ MCRejectAppendConflict(m)) /\ ~leaderSome'[m.to])
====
