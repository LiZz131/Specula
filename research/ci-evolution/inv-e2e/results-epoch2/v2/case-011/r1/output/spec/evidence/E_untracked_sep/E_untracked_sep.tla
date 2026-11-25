---- MODULE E_untracked_sep ----
EXTENDS Update
\* Old (V0) definitions over the same-named variables.
V0 == INSTANCE OldBase
EInit ==
    /\ role = [i \in Server |-> "Follower"]
    /\ vote = [i \in Server |-> DefaultVote(i)]
    /\ durableVote = [i \in Server |-> DefaultVote(i)]
    /\ votePersistPending = [i \in Server |-> FALSE]
    /\ replyPending = [i \in Server |-> FALSE]
    /\ replyMessage = [i \in Server |-> NoMessage]
    /\ sendVotePending = [i \in Server |-> FALSE]
    /\ leaseValid = [i \in Server |-> FALSE]
    /\ candidateActive = [i \in Server |-> FALSE]
    /\ candidateVote = [i \in Server |-> DefaultVote(i)]
    /\ candidateConfig = [i \in Server |-> <<InitialConfig>>]
    /\ grants = [i \in Server |-> {}]
    /\ sentVoteReq = [i \in Server |-> {}]
    /\ leaderActive = [i \in Server |-> FALSE]
    /\ leaderVote = [i \in Server |-> DefaultVote(i)]
    /\ leaderCertified = [i \in Server |-> FALSE]
    /\ leaderConfig = [i \in Server |-> <<InitialConfig>>]
    /\ leaderGrants = [i \in Server |-> {}]
    /\ lastLog = [i \in Server |-> NoLog(i)]
    /\ durableLastLog = [i \in Server |-> NoLog(i)]
    /\ logFlushPending = [i \in Server |-> FALSE]
    /\ committedConfig = (("1" :> <<{"1","2"}>>)) @@ [i \in Server |-> <<InitialConfig>>]
    /\ committedConfigIndex = [i \in Server |-> 0]
    /\ effectiveConfig = (("1" :> <<{"1","2"}>>)) @@ [i \in Server |-> <<InitialConfig>>]
    /\ effectiveConfigIndex = [i \in Server |-> 0]
    /\ durableConfig = [i \in Server |-> <<InitialConfig>>]
    /\ durableConfigIndex = [i \in Server |-> 0]
    /\ messages = {[kind |-> "PreVoteResp", source |-> "3", dest |-> "1", vote |-> [term |-> 0, node |-> "3", committed |-> FALSE], lastLog |-> [present |-> FALSE, term |-> 0, node |-> "3", index |-> 0], granted |-> TRUE, transfer |-> FALSE, reqVote |-> [term |-> 1, node |-> "1", committed |-> FALSE]]}
    /\ crashed = [i \in Server |-> FALSE]
    /\ seenGreaterLog = [i \in Server |-> FALSE]
    /\ preCandidateActive = (("1" :> TRUE)) @@ [i \in Server |-> FALSE]
    /\ preCandidateVote = (("1" :> [term |-> 1, node |-> "1", committed |-> FALSE])) @@ [i \in Server |-> DefaultVote(i)]
    /\ preCandidateConfig = (("1" :> <<{"1","2"}>>)) @@ [i \in Server |-> <<InitialConfig>>]
    /\ preGrants = (("1" :> {"1"})) @@ [i \in Server |-> {}]
    /\ preRoundFromLeader = [i \in Server |-> FALSE]
    /\ faultCounters = [election |-> 0, membership |-> 0, crash |-> 0, drop |-> 0, preVote |-> 0]
ENext ==
    /\ \E m \in messages : Old!DeliverPreVoteResponse(m) /\ UNCHANGED faultCounters
ESpec == EInit /\ [][ENext]_mcVars
\* Prints old and new verdicts of the state properties in every state.
ReportState == /\ PrintT(<<"E_untracked_sep", "state", TLCGet("level"), "old", <<"TypeOK", V0!TypeOK, "VoteRequestAfterDurable", V0!VoteRequestAfterDurable, "GrantedResponseAfterDurable", V0!GrantedResponseAfterDurable, "LeaderRoleHasCommittedSelfVote", V0!LeaderRoleHasCommittedSelfVote, "CandidateRoleHasPendingSelfVote", V0!CandidateRoleHasPendingSelfVote, "CertifiedLeaderHasFrozenQuorum", V0!CertifiedLeaderHasFrozenQuorum, "NoForgedMessageEndpoints", V0!NoForgedMessageEndpoints, "DurableVoteNotAhead", V0!DurableVoteNotAhead>>>>)
               /\ PrintT(<<"E_untracked_sep", "state", TLCGet("level"), "new", <<"LeaderObjectVoteNotBehind", LeaderObjectVoteNotBehind, "TypeOK", TypeOK, "VoteRequestAfterDurable", VoteRequestAfterDurable, "GrantedResponseAfterDurable", GrantedResponseAfterDurable, "LeaderRoleHasCommittedSelfVote", LeaderRoleHasCommittedSelfVote, "CandidateRoleHasPendingSelfVote", CandidateRoleHasPendingSelfVote, "CertifiedLeaderHasFrozenQuorum", CertifiedLeaderHasFrozenQuorum, "NoForgedMessageEndpoints", NoForgedMessageEndpoints, "DurableVoteNotAhead", DurableVoteNotAhead>>>>)
\* Prints the new verdicts of the update step predicates on every transition.
ReportStep == [][PrintT(<<"E_untracked_sep", "step", <<"PreVoteRoundNotOutlivedByOwnLeadershipStep", PreVoteRoundNotOutlivedByOwnLeadershipStep, "PreVoteElectionByVoterStep", PreVoteElectionByVoterStep, "PreVoteElectionAtProbedVoteStep", PreVoteElectionAtProbedVoteStep, "PreVoteRequestIsPureStep", PreVoteRequestIsPureStep, "PreVoteStartIsPureStep", PreVoteStartIsPureStep, "PreVoteGrantFromTrackedVoterStep", PreVoteGrantFromTrackedVoterStep>>>>)]_mcVars
====
