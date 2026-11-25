---------------------------- MODULE E_TypeOK_ctl ----------------------------
(* Control for the TypeOK weakening: the current TypeOK (actual definition, *)
(* via INSTANCE base) still rejects a message of an unknown kind, and       *)
(* accepts the same state with a PreVoteReq instead.                        *)
EXTENDS TLC, Naturals, FiniteSets, Sequences
S == {"1", "2", "3"}
V(i) == [term |-> 0, node |-> i, committed |-> FALSE]
L(i) == [present |-> FALSE, term |-> 0, node |-> i, index |-> 0]
Msg(k) == [kind |-> k, source |-> "1", dest |-> "2", vote |-> [term |-> 1, node |-> "1", committed |-> FALSE],
           lastLog |-> L("1"), granted |-> FALSE, transfer |-> FALSE, round |-> 1]
NoM == [kind |-> "None", source |-> "1", dest |-> "1", vote |-> V("1"), lastLog |-> L("1"),
        granted |-> FALSE, transfer |-> FALSE, round |-> 0]
St(msgs) == INSTANCE base WITH Server <- S, NodeOrder <- <<"1", "2", "3">>, MaxTerm <- 2,
    MaxLogIndex <- 4, InitialConfig <- S, PreVoteNodes <- S,
    role <- [i \in S |-> "Follower"], vote <- [i \in S |-> V(i)], durableVote <- [i \in S |-> V(i)],
    votePersistPending <- [i \in S |-> FALSE], replyPending <- [i \in S |-> FALSE],
    replyMessage <- [i \in S |-> NoM], sendVotePending <- [i \in S |-> FALSE],
    leaseValid <- [i \in S |-> FALSE], candidateActive <- [i \in S |-> FALSE],
    candidateVote <- [i \in S |-> V(i)], candidateConfig <- [i \in S |-> <<S>>],
    grants <- [i \in S |-> {}], sentVoteReq <- [i \in S |-> {}], leaderActive <- [i \in S |-> FALSE],
    leaderVote <- [i \in S |-> V(i)], leaderCertified <- [i \in S |-> FALSE],
    leaderConfig <- [i \in S |-> <<S>>], leaderGrants <- [i \in S |-> {}],
    lastLog <- [i \in S |-> L(i)], durableLastLog <- [i \in S |-> L(i)],
    logFlushPending <- [i \in S |-> FALSE], committedConfig <- [i \in S |-> <<S>>],
    committedConfigIndex <- [i \in S |-> 0], effectiveConfig <- [i \in S |-> <<S>>],
    effectiveConfigIndex <- [i \in S |-> 0], durableConfig <- [i \in S |-> <<S>>],
    durableConfigIndex <- [i \in S |-> 0], messages <- msgs, crashed <- [i \in S |-> FALSE],
    seenGreaterLog <- [i \in S |-> FALSE], preCandidateActive <- [i \in S |-> i = "1"],
    preCandidateVote <- [i \in S |-> IF i = "1" THEN [term |-> 1, node |-> "1", committed |-> FALSE] ELSE V(i)],
    preCandidateConfig <- [i \in S |-> <<S>>], preCandidateLastLog <- [i \in S |-> L(i)],
    preGrants <- [i \in S |-> IF i = "1" THEN {"1"} ELSE {}], sendPreVotePending <- [i \in S |-> FALSE],
    preRound <- [i \in S |-> IF i = "1" THEN 1 ELSE 0], preByTimer <- [i \in S |-> i = "1"]
StMC(pr) == INSTANCE MC WITH Server <- S, NodeOrder <- <<"1", "2", "3">>, MaxTerm <- 2,
    MaxLogIndex <- 4, InitialConfig <- S, PreVoteNodes <- S,
    role <- [i \in S |-> "Follower"], vote <- [i \in S |-> V(i)], durableVote <- [i \in S |-> V(i)],
    votePersistPending <- [i \in S |-> FALSE], replyPending <- [i \in S |-> FALSE],
    replyMessage <- [i \in S |-> NoM], sendVotePending <- [i \in S |-> FALSE],
    leaseValid <- [i \in S |-> FALSE], candidateActive <- [i \in S |-> FALSE],
    candidateVote <- [i \in S |-> V(i)], candidateConfig <- [i \in S |-> <<S>>],
    grants <- [i \in S |-> {}], sentVoteReq <- [i \in S |-> {}], leaderActive <- [i \in S |-> FALSE],
    leaderVote <- [i \in S |-> V(i)], leaderCertified <- [i \in S |-> FALSE],
    leaderConfig <- [i \in S |-> <<S>>], leaderGrants <- [i \in S |-> {}],
    lastLog <- [i \in S |-> L(i)], durableLastLog <- [i \in S |-> L(i)],
    logFlushPending <- [i \in S |-> FALSE], committedConfig <- [i \in S |-> <<S>>],
    committedConfigIndex <- [i \in S |-> 0], effectiveConfig <- [i \in S |-> <<S>>],
    effectiveConfigIndex <- [i \in S |-> 0], durableConfig <- [i \in S |-> <<S>>],
    durableConfigIndex <- [i \in S |-> 0], messages <- {}, crashed <- [i \in S |-> FALSE],
    seenGreaterLog <- [i \in S |-> FALSE], preCandidateActive <- [i \in S |-> i = "1"],
    preCandidateVote <- [i \in S |-> IF i = "1" THEN [term |-> 1, node |-> "1", committed |-> FALSE] ELSE V(i)],
    preCandidateConfig <- [i \in S |-> <<S>>], preCandidateLastLog <- [i \in S |-> L(i)],
    preGrants <- [i \in S |-> IF i = "1" THEN {"1"} ELSE {}], sendPreVotePending <- [i \in S |-> FALSE],
    preRound <- pr, preByTimer <- [i \in S |-> i = "1"],
    faultCounters <- [election |-> 1, membership |-> 0, crash |-> 0, drop |-> 0],
    MaxElectionCount <- 2, MaxMembershipCount <- 2, MaxCrashCount <- 1, MaxDropCount <- 1,
    MaxMessageCount <- 5
ASSUME PrintT(<<"E-TypeOK-ctl: TypeOK(PreVoteReq state)", St({Msg("PreVoteReq")})!TypeOK,
                "TypeOK(Bogus-kind state)", St({Msg("Bogus")})!TypeOK>>)
ASSUME PrintT(<<"E-MCTypeOK: MCTypeOK(preRound=1)", StMC([i \in S |-> IF i = "1" THEN 1 ELSE 0])!MCTypeOK,
                "MCTypeOK(preRound=3 > MaxElectionCount)", StMC([i \in S |-> IF i = "1" THEN 3 ELSE 0])!MCTypeOK>>)
=============================================================================
