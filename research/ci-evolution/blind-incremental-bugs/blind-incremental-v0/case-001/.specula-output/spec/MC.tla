------------------------------- MODULE MC -------------------------------
EXTENDS base

B == INSTANCE base

CONSTANTS InitLimit, ElectionLimit, VoteSendLimit, AppendLimit,
          AppendSendLimit, CrashLimit, LoseLimit, MaxMessages

VARIABLE constraintCounters
mcVars == <<vars, constraintCounters>>

MCInit ==
    /\ Init
    /\ constraintCounters = [init |-> 0, election |-> 0,
                              voteSend |-> 0, append |-> 0,
                              appendSend |-> 0, crash |-> 0, lose |-> 0]

MCInitialize(n) ==
    /\ constraintCounters.init < InitLimit
    /\ B!EngineInitialize(n, Cardinality(Nodes))
    /\ constraintCounters' = [constraintCounters EXCEPT !.init = @ + 1]

MCElect(n) ==
    /\ constraintCounters.election < ElectionLimit
    /\ B!EngineElect(n)
    /\ constraintCounters' = [constraintCounters EXCEPT !.election = @ + 1]

MCSendVote(c, v) ==
    /\ constraintCounters.voteSend < VoteSendLimit
    /\ Cardinality(messages) < MaxMessages
    /\ B!SendVoteRequest(c, v)
    /\ constraintCounters' = [constraintCounters EXCEPT !.voteSend = @ + 1]

MCLeaderAppend(n) ==
    /\ constraintCounters.append < AppendLimit
    /\ B!LeaderAppend(n)
    /\ constraintCounters' = [constraintCounters EXCEPT !.append = @ + 1]

MCSendAppend(l, f) ==
    /\ constraintCounters.appendSend < AppendSendLimit
    /\ Cardinality(messages) < MaxMessages
    /\ B!SendAppendEntries(l, f)
    /\ constraintCounters' = [constraintCounters EXCEPT !.appendSend = @ + 1]

MCCrash(n) ==
    /\ constraintCounters.crash < CrashLimit
    /\ B!Crash(n)
    /\ constraintCounters' = [constraintCounters EXCEPT !.crash = @ + 1]

MCLose(m) ==
    /\ constraintCounters.lose < LoseLimit
    /\ B!LoseMessage(m)
    /\ constraintCounters' = [constraintCounters EXCEPT !.lose = @ + 1]

Reactive(a) == /\ a /\ UNCHANGED constraintCounters

MCNext ==
    \/ \E n \in Nodes: MCInitialize(n)
    \/ \E n \in Nodes: MCElect(n)
    \/ \E c, v \in Nodes: MCSendVote(c, v)
    \/ \E m \in messages: Reactive(B!DeliverVoteRequest(m))
    \/ \E m \in messages: Reactive(B!DeliverVoteResponse(m))
    \/ \E n \in Nodes: Reactive(B!BecomeLeader(n))
    \/ \E n \in Nodes: MCLeaderAppend(n)
    \/ \E l, f \in Nodes: MCSendAppend(l, f)
    \/ \E m \in messages: Reactive(B!DeliverAppendEntries(m))
    \/ \E n \in Nodes: Reactive(B!SubmitAccepted(n))
    \/ \E n \in Nodes: Reactive(B!FlushSubmitted(n))
    \/ \E n \in Nodes: Reactive(B!DeliverLocalVoteResponse(n))
    \/ \E n \in Nodes: \E k \in 1..MaxLog: Reactive(B!AdvanceCommit(n, k))
    \/ \E n \in Nodes: MCCrash(n)
    \/ \E n \in Nodes: Reactive(B!Restart(n))
    \/ \E m \in messages: MCLose(m)

MCSpec == MCInit /\ [][MCNext]_mcVars

MCTypeOK == TypeOK /\ constraintCounters \in
    [init : Nat, election : Nat, voteSend : Nat, append : Nat,
     appendSend : Nat, crash : Nat, lose : Nat]

StateConstraint ==
    /\ Cardinality(messages) <= MaxMessages
    /\ \A n \in Nodes: term[n] <= MaxTerm /\ logLen[n] <= MaxLog

=============================================================================
