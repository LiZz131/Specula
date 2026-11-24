---- MODULE CensusProbes ----
EXTENDS Update

\* Positive control: some lease was disabled (agent canary CanaryLeaseDisabled negated, Update.tla:168).
SC_CTRL_lease_disabled == \E n \in Server : ~leaseEnabled[n]

\* U-S1: "TransferLeader with `to = learner` calls `elect()`" (modeling-brief.md:33-34)
\* = agent canary CanaryNonVoterCandidate negated (Update.tla:180)
SC_US1a_learner_candidate == \E n \in Server : candidate[n] /\ n \notin Voters(candidateConfigs[n])

\* U-S1: "Uncertainty: does the learner panic or win?" (modeling-brief.md:37) -- panic branch
SC_US1b_learner_panics == \E n \in Server : panicked[n]

\* U-S2: "same-vote AppendEntries/heartbeats call `touch()` which must keep it disabled"
\* (modeling-brief.md:44-45): precondition of a same-vote append (MCFollowerAppend, MC.tla:129-135)
\* to a node whose lease is disabled.
SC_US2a_touch_on_disabled ==
    \E n, l \in Server :
        /\ n # l /\ up[n] /\ ~leaseEnabled[n]
        /\ leader[l] /\ voteCommitted[l]
        /\ voteTerm[n] = voteTerm[l] /\ voteNode[n] = l /\ voteCommitted[n]
        /\ LastIndex(n) < LastIndex(l)
        /\ replicateCount < ReplicateLimit

\* U-S2: "any vote change (`update()`) re-enables it" (modeling-brief.md:45): a node with a
\* disabled lease has an in-flight RequestVote carrying a greater vote.
SC_US2b_votechange_on_disabled ==
    \E n \in Server :
        /\ up[n] /\ ~leaseEnabled[n]
        /\ \E m \in voteReqs : m.dst = n /\
              VoteLT(voteTerm[n], voteNode[n], voteCommitted[n], m.term, m.src, FALSE)

\* U-S3: "Target voter elects at last_seen.term + 1; voters with disabled leases grant"
\* (modeling-brief.md:52): a transfer-elected leader that is a voter (ElectNodes = {1},
\* so any other self-elected leader came from a transfer; cf. CanaryTransferElectedLeader, Update.tla:171)
SC_US3a_voter_target_leader ==
    \E n \in Server : n # 1 /\ leader[n] /\ voteCommitted[n] /\ voteNode[n] = n
                      /\ n \in Voters(candidateConfigs[n])

\* U-S3: "the old leader accepts the higher vote and steps down" (modeling-brief.md:53)
\* = agent canary CanaryOldLeaderDeposed negated (Update.tla:177-178)
SC_US3b_old_leader_deposed == ~leader[1] /\ up[1] /\ voteTerm[1] >= 2 /\ voteNode[1] # 1

\* U-S3: "the new leader appends its blank and commits" (modeling-brief.md:53)
\* = agent canary CanaryCommitAfterTransfer negated (Update.tla:173-175)
SC_US3c_commit_after_transfer ==
    \E n \in Server : n # 1 /\ leader[n] /\ commitIndex[n] >= 1
                      /\ EntryAt(n, commitIndex[n]).node = n

\* U-S4: "Removed (absent) target runs `elect()` but `become_following` clears the candidate"
\* (modeling-brief.md:58) = agent canary CanaryAbsentElect negated (Update.tla:182-184)
SC_US4a_absent_elect ==
    \E n \in Server : up[n] /\ ~Contains(n, n) /\ voteNode[n] = n /\ ~voteCommitted[n]
                      /\ voteTerm[n] >= 1

\* U-S4: "Leader transferring to itself becomes leader+candidate" (modeling-brief.md:59-60)
SC_US4b_leader_and_candidate == \E n \in Server : up[n] /\ leader[n] /\ candidate[n]

\* U-S5: "A fresh `RaftState` re-enables the lease" (modeling-brief.md:64): a node crashes while
\* its lease is disabled by a transfer.
SC_US5a_crash_with_disabled_lease == \E n \in Server : ~up[n] /\ ~leaseEnabled[n]

\* U-S5: "startup restores leadership only when the node is contained in membership"
\* (modeling-brief.md:64-65), around a transfer: a node with a durable committed self vote is down
\* after a transfer happened.
SC_US5b_leader_down_after_transfer ==
    transferCount >= 1 /\
    \E n \in Server : ~up[n] /\ durableVoteCommitted[n] /\ durableVoteNode[n] = n
====
