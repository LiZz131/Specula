---------------------------- MODULE EvidenceConstructed ----------------------------
(***************************************************************************
 * Constructed (or trace-edited) separating/control transitions S0 -> S1.  *
 * The current definitions from UpdateProps/base and the prior OldBase     *
 * definitions are evaluated by TLC on the single transition; values are   *
 * printed with PrintT and the run checks nothing else.                    *
 *************************************************************************)
EXTENDS UpdateProps

Old == INSTANCE OldBase

CONSTANT Case

Dflt ==
    [role |-> [i \in Server |-> "Follower"],
     vote |-> [i \in Server |-> DefaultVote(i)],
     durableVote |-> [i \in Server |-> DefaultVote(i)],
     votePersistPending |-> [i \in Server |-> FALSE],
     replyPending |-> [i \in Server |-> FALSE],
     replyMessage |-> [i \in Server |-> NoMessage],
     sendVotePending |-> [i \in Server |-> FALSE],
     leaseValid |-> [i \in Server |-> FALSE],
     candidateActive |-> [i \in Server |-> FALSE],
     candidateVote |-> [i \in Server |-> DefaultVote(i)],
     candidateConfig |-> [i \in Server |-> <<InitialConfig>>],
     grants |-> [i \in Server |-> {}],
     sentVoteReq |-> [i \in Server |-> {}],
     leaderActive |-> [i \in Server |-> FALSE],
     leaderVote |-> [i \in Server |-> DefaultVote(i)],
     leaderCertified |-> [i \in Server |-> FALSE],
     leaderConfig |-> [i \in Server |-> <<InitialConfig>>],
     leaderGrants |-> [i \in Server |-> {}],
     lastLog |-> [i \in Server |-> NoLog(i)],
     durableLastLog |-> [i \in Server |-> NoLog(i)],
     logFlushPending |-> [i \in Server |-> FALSE],
     committedConfig |-> [i \in Server |-> <<InitialConfig>>],
     committedConfigIndex |-> [i \in Server |-> 0],
     effectiveConfig |-> [i \in Server |-> <<InitialConfig>>],
     effectiveConfigIndex |-> [i \in Server |-> 0],
     durableConfig |-> [i \in Server |-> <<InitialConfig>>],
     durableConfigIndex |-> [i \in Server |-> 0],
     messages |-> {},
     crashed |-> [i \in Server |-> FALSE],
     seenGreaterLog |-> [i \in Server |-> FALSE],
     preCandidateActive |-> [i \in Server |-> FALSE],
     preCandidateVote |-> [i \in Server |-> DefaultVote(i)],
     preCandidateConfig |-> [i \in Server |-> <<InitialConfig>>],
     preGrants |-> [i \in Server |-> {}],
     preCandidateByTimer |-> [i \in Server |-> FALSE],
     preRound |-> [i \in Server |-> 0]]

P1 == Vote(2, "1", FALSE)            \* probe of node 1 whose vote is (1, "2", committed)
V12c == Vote(1, "2", TRUE)
L1 == Log(1, "1", 1)
Cfg == <<{"1", "2", "3"}>>
\* Node 1: follower of the expired leader (1,"2"), Pre-Vote round 2 for probe P1 active,
\* grants {"1"} (shape of trace prevote_round_reuses_probe before its event 4).
Round2 ==
    [Dflt EXCEPT !.vote = [@ EXCEPT !["1"] = V12c],
                 !.durableVote = [@ EXCEPT !["1"] = V12c],
                 !.lastLog = [@ EXCEPT !["1"] = L1],
                 !.durableLastLog = [@ EXCEPT !["1"] = L1],
                 !.preCandidateActive = [@ EXCEPT !["1"] = TRUE],
                 !.preCandidateVote = [@ EXCEPT !["1"] = P1],
                 !.preCandidateConfig = [@ EXCEPT !["1"] = Cfg],
                 !.preGrants = [@ EXCEPT !["1"] = {"1"}],
                 !.preCandidateByTimer = [@ EXCEPT !["1"] = TRUE],
                 !.preRound = [@ EXCEPT !["1"] = 2]]
GrantR(r) == PreVoteMessage("PreVoteResp", "2", "1", P1, NoLog("2"), TRUE, r)
GrantFrom(j, r) == PreVoteMessage("PreVoteResp", j, "1", P1, NoLog(j), TRUE, r)

S0 ==
    CASE Case = "StaleSep"   -> [Round2 EXCEPT !.messages = {GrantR(1)}]
      [] Case = "StaleCtl"   -> [Round2 EXCEPT !.messages = {GrantR(2)}]
      [] Case = "PanicSep"   -> [Round2 EXCEPT !.preCandidateConfig = [@ EXCEPT !["1"] = <<{"1", "2"}>>],
                                               !.messages = {GrantFrom("3", 1)}]
      [] Case = "PanicCtl"   -> Round2
      [] Case = "ProbeSep"   -> [Round2 EXCEPT !.messages = {GrantR(2)}]
      [] Case = "ProbeStateSep" -> [Round2 EXCEPT !.preCandidateVote = [@ EXCEPT !["1"] = Vote(3, "1", FALSE)]]
      [] Case = "PersistSep" -> Round2
      [] Case = "TypeCtl"    -> [Round2 EXCEPT !.messages = {PreVoteMessage("Bogus", "2", "1", P1, NoLog("2"), TRUE, 1)}]
      [] OTHER -> Dflt

\* Elect effects of the quorum branch, applied to node 1 (vote (2,"1"), Candidate, durable save pending).
Elected(s, nv) ==
    [s EXCEPT !.vote = [@ EXCEPT !["1"] = nv],
              !.role = [@ EXCEPT !["1"] = "Candidate"],
              !.candidateActive = [@ EXCEPT !["1"] = TRUE],
              !.candidateVote = [@ EXCEPT !["1"] = nv],
              !.candidateConfig = [@ EXCEPT !["1"] = Cfg],
              !.votePersistPending = [@ EXCEPT !["1"] = TRUE],
              !.sendVotePending = [@ EXCEPT !["1"] = TRUE],
              !.preCandidateActive = [@ EXCEPT !["1"] = FALSE],
              !.preCandidateVote = [@ EXCEPT !["1"] = DefaultVote("1")],
              !.preCandidateConfig = [@ EXCEPT !["1"] = <<InitialConfig>>],
              !.preGrants = [@ EXCEPT !["1"] = {}],
              !.preCandidateByTimer = [@ EXCEPT !["1"] = FALSE],
              !.messages = {}]

S1 ==
    CASE Case = "StaleSep"   -> Elected(S0, P1)
      [] Case = "StaleCtl"   -> Elected(S0, P1)
      [] Case = "PanicSep"   -> [S0 EXCEPT !.crashed = [@ EXCEPT !["1"] = TRUE], !.messages = {}]
      [] Case = "PanicCtl"   -> [S0 EXCEPT !.crashed = [@ EXCEPT !["1"] = TRUE]]
      [] Case = "ProbeSep"   -> Elected(S0, Vote(3, "1", FALSE))
      [] Case = "ProbeStateSep" -> S0
      [] Case = "PersistSep" -> [S0 EXCEPT !.vote = [@ EXCEPT !["1"] = P1],
                                           !.preRound = [@ EXCEPT !["1"] = 3]]
      [] Case = "TypeCtl"    -> S0
      [] OTHER -> S0

EvInit ==
    /\ role = S0.role
    /\ vote = S0.vote
    /\ durableVote = S0.durableVote
    /\ votePersistPending = S0.votePersistPending
    /\ replyPending = S0.replyPending
    /\ replyMessage = S0.replyMessage
    /\ sendVotePending = S0.sendVotePending
    /\ leaseValid = S0.leaseValid
    /\ candidateActive = S0.candidateActive
    /\ candidateVote = S0.candidateVote
    /\ candidateConfig = S0.candidateConfig
    /\ grants = S0.grants
    /\ sentVoteReq = S0.sentVoteReq
    /\ leaderActive = S0.leaderActive
    /\ leaderVote = S0.leaderVote
    /\ leaderCertified = S0.leaderCertified
    /\ leaderConfig = S0.leaderConfig
    /\ leaderGrants = S0.leaderGrants
    /\ lastLog = S0.lastLog
    /\ durableLastLog = S0.durableLastLog
    /\ logFlushPending = S0.logFlushPending
    /\ committedConfig = S0.committedConfig
    /\ committedConfigIndex = S0.committedConfigIndex
    /\ effectiveConfig = S0.effectiveConfig
    /\ effectiveConfigIndex = S0.effectiveConfigIndex
    /\ durableConfig = S0.durableConfig
    /\ durableConfigIndex = S0.durableConfigIndex
    /\ messages = S0.messages
    /\ crashed = S0.crashed
    /\ seenGreaterLog = S0.seenGreaterLog
    /\ preCandidateActive = S0.preCandidateActive
    /\ preCandidateVote = S0.preCandidateVote
    /\ preCandidateConfig = S0.preCandidateConfig
    /\ preGrants = S0.preGrants
    /\ preCandidateByTimer = S0.preCandidateByTimer
    /\ preRound = S0.preRound

EvNext ==
    /\ role' = S1.role
    /\ vote' = S1.vote
    /\ durableVote' = S1.durableVote
    /\ votePersistPending' = S1.votePersistPending
    /\ replyPending' = S1.replyPending
    /\ replyMessage' = S1.replyMessage
    /\ sendVotePending' = S1.sendVotePending
    /\ leaseValid' = S1.leaseValid
    /\ candidateActive' = S1.candidateActive
    /\ candidateVote' = S1.candidateVote
    /\ candidateConfig' = S1.candidateConfig
    /\ grants' = S1.grants
    /\ sentVoteReq' = S1.sentVoteReq
    /\ leaderActive' = S1.leaderActive
    /\ leaderVote' = S1.leaderVote
    /\ leaderCertified' = S1.leaderCertified
    /\ leaderConfig' = S1.leaderConfig
    /\ leaderGrants' = S1.leaderGrants
    /\ lastLog' = S1.lastLog
    /\ durableLastLog' = S1.durableLastLog
    /\ logFlushPending' = S1.logFlushPending
    /\ committedConfig' = S1.committedConfig
    /\ committedConfigIndex' = S1.committedConfigIndex
    /\ effectiveConfig' = S1.effectiveConfig
    /\ effectiveConfigIndex' = S1.effectiveConfigIndex
    /\ durableConfig' = S1.durableConfig
    /\ durableConfigIndex' = S1.durableConfigIndex
    /\ messages' = S1.messages
    /\ crashed' = S1.crashed
    /\ seenGreaterLog' = S1.seenGreaterLog
    /\ preCandidateActive' = S1.preCandidateActive
    /\ preCandidateVote' = S1.preCandidateVote
    /\ preCandidateConfig' = S1.preCandidateConfig
    /\ preGrants' = S1.preGrants
    /\ preCandidateByTimer' = S1.preCandidateByTimer
    /\ preRound' = S1.preRound

EvSpec == EvInit /\ [][EvNext]_vars

Report ==
    PrintT(<<"CONSTRUCTED", Case,
             [ TypeOK_new |-> TypeOK, TypeOK_old |-> Old!TypeOK,
               PreCandidateProbeIsNextTerm |-> PreCandidateProbeIsNextTerm ]>>)
StepReport ==
    PrintT(<<"CONSTRUCTED-STEP", Case,
             [ quorum_elect_step |-> {i \in Server : PreVoteQuorumElectStep(i)},
               counted |-> {<<p[1], p[2].source, p[2].round>> : p \in {q \in Server \X messages : CountedPreVoteGrant(q[1], q[2])}},
               TimerPreVoteElectsOnlyNonLeaderStep |-> TimerPreVoteElectsOnlyNonLeaderStep,
               StalePreVoteResponseIgnoredStep |-> StalePreVoteResponseIgnoredStep,
               PreVoteResponseNeverPanicsStep |-> PreVoteResponseNeverPanicsStep,
               PreVoteProbeMatchesElectionStep |-> PreVoteProbeMatchesElectionStep,
               PreVoteRoundPersistsNothingStep |-> PreVoteRoundPersistsNothingStep ]>>)
ReportInv == Report
ReportStep == [][StepReport]_vars
=============================================================================
