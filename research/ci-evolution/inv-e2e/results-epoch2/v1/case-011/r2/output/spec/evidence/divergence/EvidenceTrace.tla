--------------------------- MODULE EvidenceTrace ---------------------------
(***************************************************************************
 * Divergence evidence: evaluates the prior (OldBase = previous base.tla)   *
 * and current property definitions with TLC on every state of a replayed   *
 * fresh trace (state_source = trace), plus short edits of those states.    *
 *************************************************************************)
EXTENDS Trace

Old == INSTANCE OldBase

\* Update properties are evaluated through Update.tla itself. Its MC-level
\* observer preVoteBase is the vote from which the trace's PreElect event built
\* its round (pre-state of the first PreElect event).
FirstPreElect == CHOOSE k \in 1..Len(TraceLog) :
                    /\ TraceLog[k].name = "PreElect"
                    /\ \A j \in 1..(k-1) : TraceLog[j].name /= "PreElect"
HasPreElect == \E k \in 1..Len(TraceLog) : TraceLog[k].name = "PreElect"
ProbedVote == IF HasPreElect THEN SnapshotVote(TraceLog[FirstPreElect].pre.vote) ELSE vote[Focus]

FC == [election |-> 0, preElection |-> 0, membership |-> 0, crash |-> 0, drop |-> 0]
U == INSTANCE Update WITH faultCounters <- FC,
                          preVoteBase <- [i \in Server |-> IF i = Focus THEN ProbedVote ELSE vote[i]],
                          MaxElectionCount <- 2, MaxPreElectionCount <- 2,
                          MaxMembershipCount <- 2, MaxCrashCount <- 1,
                          MaxDropCount <- 1, MaxMessageCount <- 5
\* Control: same state, but the round's probed vote equals the current vote
\* (a Leader that itself started the round with Trigger::elect(true)).
UC == INSTANCE Update WITH faultCounters <- FC,
                           preVoteBase <- vote,
                           MaxElectionCount <- 2, MaxPreElectionCount <- 2,
                           MaxMembershipCount <- 2, MaxCrashCount <- 1,
                           MaxDropCount <- 1, MaxMessageCount <- 5
\* Short edit (separating state for PreCandidateTermUnbumped): the local term
\* is bumped to the round's term while the round stays active.
UB == INSTANCE Update WITH faultCounters <- FC,
                           preVoteBase <- vote,
                           vote <- [vote EXCEPT ![Focus] = preCandidateVote[Focus]],
                           MaxElectionCount <- 2, MaxPreElectionCount <- 2,
                           MaxMembershipCount <- 2, MaxCrashCount <- 1,
                           MaxDropCount <- 1, MaxMessageCount <- 5

Kinds == {m.kind : m \in messages}

\* U-5 separating state (short edit of a replayed state with an active round):
\* the round's voters shrink to {"1","2"} and a matching grant from "3" is in flight.
StaleGrant(src) == Message("PreVoteResp", src, Focus, preCandidateVote[Focus], NoLog(src), TRUE, FALSE)
UM(src) == [cfg |-> [preCandidateConfig EXCEPT ![Focus] = <<{"1", "2"}>>],
            msgs |-> messages \cup {StaleGrant(src)}]
UMS == INSTANCE Update WITH faultCounters <- FC, preVoteBase <- vote,
                            preCandidateConfig <- UM("3").cfg, messages <- UM("3").msgs,
                            MaxElectionCount <- 2, MaxPreElectionCount <- 2,
                            MaxMembershipCount <- 2, MaxCrashCount <- 1,
                            MaxDropCount <- 1, MaxMessageCount <- 5
UMC == INSTANCE Update WITH faultCounters <- FC, preVoteBase <- vote,
                            preCandidateConfig <- UM("2").cfg, messages <- UM("2").msgs,
                            MaxElectionCount <- 2, MaxPreElectionCount <- 2,
                            MaxMembershipCount <- 2, MaxCrashCount <- 1,
                            MaxDropCount <- 1, MaxMessageCount <- 5

\* TypeOK weakening control: one extra message of an unknown kind.
BogusMsg == Message("Bogus", "1", "2", DefaultVote("1"), NoLog("1"), FALSE, FALSE)
B == INSTANCE base WITH messages <- messages \cup {BogusMsg}

EvidencePrint ==
    PrintT(<<"EVIDENCE", TraceFile, "cursor", cursor,
             "role", role[Focus], "vote", vote[Focus], "msgKinds", Kinds,
             "preCandidateActive", preCandidateActive[Focus],
             [TypeOK |-> <<Old!TypeOK, TypeOK>>,
              TypeOK_control_bogus_kind |-> <<Old!TypeOK, B!TypeOK>>,
              VoteRequestAfterDurable |-> <<Old!VoteRequestAfterDurable, VoteRequestAfterDurable>>,
              GrantedResponseAfterDurable |-> <<Old!GrantedResponseAfterDurable, GrantedResponseAfterDurable>>,
              DurableVoteNotAhead |-> <<Old!DurableVoteNotAhead, DurableVoteNotAhead>>,
              DurableLogNotAhead |-> <<Old!DurableLogNotAhead, DurableLogNotAhead>>,
              LeaderRoleHasCommittedSelfVote |-> <<Old!LeaderRoleHasCommittedSelfVote, LeaderRoleHasCommittedSelfVote>>,
              CandidateRoleHasPendingSelfVote |-> <<Old!CandidateRoleHasPendingSelfVote, CandidateRoleHasPendingSelfVote>>,
              NoForgedMessageEndpoints |-> <<Old!NoForgedMessageEndpoints, NoForgedMessageEndpoints>>,
              CertifiedLeaderHasFrozenQuorum |-> <<Old!CertifiedLeaderHasFrozenQuorum, CertifiedLeaderHasFrozenQuorum>>,
              LogLE_absent_logs |-> <<Old!LogLE(NoLog("2"), NoLog("1")), LogLE(NoLog("2"), NoLog("1"))>>,
              EstablishedLeaderHasNoInheritedPreVote |-> <<"not-checked", U!EstablishedLeaderHasNoInheritedPreVote>>,
              EstablishedLeaderHasNoInheritedPreVote_control |-> <<"not-checked", UC!EstablishedLeaderHasNoInheritedPreVote>>,
              PreCandidateTermUnbumped |-> <<"not-checked", U!PreCandidateTermUnbumped>>,
              PreCandidateTermUnbumped_bumped_edit |-> <<"not-checked", UB!PreCandidateTermUnbumped>>,
              PreVoteMessagesWellFormed |-> <<"not-checked", U!PreVoteMessagesWellFormed>>,
              PreVoteGrantFromRoundMember |-> <<"not-checked", U!PreVoteGrantFromRoundMember>>,
              PreVoteGrantFromRoundMember_stale_nonmember |-> <<"not-checked", IF preCandidateActive[Focus] THEN UMS!PreVoteGrantFromRoundMember ELSE "n/a">>,
              PreVoteGrantFromRoundMember_control_member |-> <<"not-checked", IF preCandidateActive[Focus] THEN UMC!PreVoteGrantFromRoundMember ELSE "n/a">>]>>)

=============================================================================
