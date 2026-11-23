---- MODULE Probe004 ----
\* Decision probes for the case-004 evidence card. Adds no actions; only state predicates and
\* action properties over variables all three arms share (up, voteTerm, voteNode, voteCommitted,
\* configs, learners, leader), plus the arm's own panic flag.
EXTENDS Update

PVoters(cfg) == UNION cfg
\* A step in which node n starts an election (Engine::elect: vote := (lastSeen+1, n)) while it is
\* not a voter of its effective membership before the step (the TransferLeader branch,
\* raft_core.rs:1190-1202, calls elect() without the is_voter guard of tick / ExternalCommand::Elect).
NonVoterElect(n) ==
    /\ voteNode'[n] = n /\ voteTerm'[n] > voteTerm[n]
    /\ n \notin PVoters(configs[n])
LearnerElect(n) == NonVoterElect(n) /\ n \in learners[n]          \* MC-1: learner transfer target
AbsentElect(n)  == NonVoterElect(n) /\ n \notin learners[n]       \* removed node as transfer target
ProbeNoLearnerElect == [][\A n \in Server : ~LearnerElect(n)]_vars
ProbeNoAbsentElect  == [][\A n \in Server : ~AbsentElect(n)]_vars

\* MC-1 consequence: the RaftCore task panicked (Candidate::grant_by expect, candidate.rs:92-94).
ProbeNoPanic == \A n \in Server : ~corePanic[n]

\* Reachability of a removed node: some live node's effective membership no longer contains n
\* (neither voter nor learner).
ProbeNoRemovedNode ==
    ~\E m, n \in Server : up[m] /\ n \notin PVoters(configs[m]) \cup learners[m]

\* Leader re-election (v0's MC-2 precondition): a node that holds a Leader object starts an
\* election of its own (transfer_leader whose target is the current leader).
LeaderSelfElect(n) == leader[n] /\ voteNode'[n] = n /\ voteTerm'[n] > voteTerm[n]
ProbeNoLeaderSelfElect == [][\A n \in Server : ~LeaderSelfElect(n)]_vars
\* v0's LeaderVoteNotSuperseded, restated on shared variables (v0 Update.tla:157).
ProbeLeaderVoteNotSuperseded == \A n \in Server : (up[n] /\ leader[n]) => voteCommitted[n]
====
