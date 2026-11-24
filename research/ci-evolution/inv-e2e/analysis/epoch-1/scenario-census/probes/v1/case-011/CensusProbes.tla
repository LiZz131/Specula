---- MODULE CensusProbes ----
EXTENDS Update

PVReqReady(i) == ~crashed[i] /\ ~votePersistPending[i] /\ ~replyPending[i]
PVLease(i) == vote[i].committed /\ leaseValid[i]
PVMatches(i, m) ==
    /\ preCandidateActive[i]
    /\ m.vote.term = preCandidateVote[i].term
    /\ m.vote.node = preCandidateVote[i].node

\* U1a. "handle_pre_vote_req judges lease ..., last log, then req.vote >= vote" ; traces
\* "pre_vote_req_{grant,...}" (output/modeling-brief.md:243-248). Encoded: a granted PreVoteResp exists.
SC_U1a == \E m \in messages : m.kind = "PreVoteResp" /\ m.granted

\* U1b. "judges lease (no transfer bypass)" / "pre_vote_req_reject_lease" (output/modeling-brief.md:243,248)
\* Encoded: a deliverable PreVoteReq whose receiver holds a committed vote with a valid lease.
SC_U1b == \E m \in messages : m.kind = "PreVoteReq" /\ PVReqReady(m.dest) /\ PVLease(m.dest)

\* U1c. "last log" guard / "pre_vote_req_reject_log" (output/modeling-brief.md:244,248)
\* Encoded: lease passes, requester's last log is behind the receiver's.
SC_U1c == \E m \in messages :
    m.kind = "PreVoteReq" /\ PVReqReady(m.dest) /\ ~PVLease(m.dest) /\ ~LogLE(lastLog[m.dest], m.lastLog)

\* U1d. "then `req.vote >= vote`" / "pre_vote_req_reject_vote" (output/modeling-brief.md:244,248)
\* Encoded: lease and log pass, the requested vote is below the receiver's vote.
SC_U1d == \E m \in messages :
    /\ m.kind = "PreVoteReq" /\ PVReqReady(m.dest) /\ ~PVLease(m.dest)
    /\ LogLE(lastLog[m.dest], m.lastLog) /\ ~VoteLE(vote[m.dest], m.vote)

\* U2a. "`pre_elect` (self grant, self-quorum shortcut)" (output/modeling-brief.md:251)
\* Encoded: a voter whose effective config is a quorum by itself can start a pre-vote round.
SC_U2a == \E i \in Server :
    /\ ElectGuard(i) /\ IsQuorum(effectiveConfig[i], {i})
    /\ faultCounters.preVote < MaxPreVoteCount

\* U2b. "`PreVoteResponse` correlation -> `grant_by`" (output/modeling-brief.md:252)
\* Encoded: a pre-candidate has counted a grant from another node.
SC_U2b == \E i \in Server : preCandidateActive[i] /\ (preGrants[i] \ {i}) /= {}

\* U2c. "-> `grant_by` -> `elect()`" (output/modeling-brief.md:252). Encoded: a deliverable,
\* matching granted PreVoteResp that completes the frozen pre-vote quorum.
QuorumResp(i, m) ==
    /\ m.kind = "PreVoteResp" /\ m.dest = i /\ m.granted
    /\ PVReqReady(i) /\ PVMatches(i, m) /\ vote[i].term < MaxTerm
    /\ IsQuorum(preCandidateConfig[i], preGrants[i] \cup {m.source})
SC_U2c == \E m \in messages : QuorumResp(m.dest, m)

\* U3a. "a direct election ... drop the round" (output/analysis-report.md:268-270;
\* brief: "`do_elect` ... clear `pre_candidate`", output/modeling-brief.md:260)
\* Encoded: a live pre-candidate can start a counted direct election.
SC_U3a == \E i \in Server :
    preCandidateActive[i] /\ ElectGuard(i) /\ faultCounters.election < MaxElectionCount

\* U3b. "become_following clear `pre_candidate` (vote-request grant, ...)" (output/modeling-brief.md:260-261)
\* Encoded: a live pre-candidate has a deliverable VoteReq it would grant to another node.
SC_U3b == \E m \in messages :
    LET i == m.dest IN
    /\ m.kind = "VoteReq" /\ preCandidateActive[i] /\ PVReqReady(i)
    /\ ~(vote[i].committed /\ leaseValid[i] /\ ~m.transfer)
    /\ LogLE(lastLog[i], m.lastLog) /\ VoteLE(vote[i], m.vote)
    /\ m.vote.node /= i

\* U3c. "(... AppendEntries, ...)" (output/modeling-brief.md:261)
SC_U3c == \E m \in messages :
    LET i == m.dest IN
    /\ m.kind = "Append" /\ preCandidateActive[i] /\ ~crashed[i] /\ ~votePersistPending[i]
    /\ VoteLE(vote[i], m.vote) /\ m.vote.node /= i

\* U3d. "(... rejected-vote adoption, ...)" (output/modeling-brief.md:261)
SC_U3d == \E m \in messages :
    LET i == m.dest
        stripped == Vote(m.vote.term, m.vote.node, FALSE)
        exact == candidateActive[i] /\ m.granted /\ m.vote = candidateVote[i]
    IN /\ m.kind = "VoteResp" /\ preCandidateActive[i] /\ ~crashed[i]
       /\ candidateActive[i] /\ ~exact /\ VoteLT(vote[i], stripped) /\ stripped.node /= i

\* U3e. "(... refresh)" (output/modeling-brief.md:262)
SC_U3e == \E i \in Server :
    /\ preCandidateActive[i] /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ RoleFrom(i, vote[i], effectiveConfig[i]) \notin {"Leader", "Candidate"}

\* U3f. "restart rebuilds the Engine" (output/modeling-brief.md:262). Encoded: crashed pre-candidate.
SC_U3f == \E i \in Server : preCandidateActive[i] /\ crashed[i]

\* U3g. "the runtime drops responses with no matching pre-candidate" (output/modeling-brief.md:262-263)
SC_U3g == \E m \in messages :
    m.kind = "PreVoteResp" /\ PVReqReady(m.dest) /\ ~PVMatches(m.dest, m)

\* U4a. "tick fires on a Candidate (tick skips only Leaders) -> `pre_elect` keeps the live
\* candidate" (output/modeling-brief.md:269-270)
SC_U4a == \E i \in Server : preCandidateActive[i] /\ candidateActive[i] /\ role[i] = "Candidate"

\* U4b. "the candidacy then wins (`establish_leader` keeps `pre_candidate`)" (output/modeling-brief.md:270-271)
SC_U4b == \E i \in Server : preCandidateActive[i] /\ preStartRole[i] /= "Leader" /\ role[i] = "Leader"

\* U4c. "the stale round's quorum calls `elect()` on the Leader" (output/modeling-brief.md:271-272)
SC_U4c == \E m \in messages :
    QuorumResp(m.dest, m) /\ role[m.dest] = "Leader" /\ preStartRole[m.dest] /= "Leader"

\* Positive control: some pre-candidate exists.
SC_CTRL == \E i \in Server : preCandidateActive[i]

====
