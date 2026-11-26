------------------------------- MODULE MC -------------------------------
(* Model-checking wrapper for the updated reference (base.tla).  Fault     *)
(* injection is counter-bounded: process crashes and role abandonment      *)
(* (timeouts, lost quorum, connection loss) of a non-looking server.       *)
(* Normal protocol actions are unbounded; epochs are bounded by MaxEpoch  *)
(* and transactions by Txn.                                                *)
EXTENDS base

CONSTANTS MaxCrash, MaxAbandon
ASSUME /\ MaxCrash \in Nat /\ MaxAbandon \in Nat

VARIABLES counters, seen
mcVars == <<counters, seen>>
mcAllVars == <<allVars, mcVars>>

SeenNames == {"leader", "established", "DIFF", "TRUNC", "SNAP",
              "nlLogged", "ackBeforeNlAck", "nlAck", "broadcast", "uptodate",
              "commit", "apply", "crash", "restart", "abandon", "npe",
              "misread", "reelect", "commitAfterNl", "followerBroadcast",
              "unmatched"}

MCInit ==
    /\ Init
    /\ counters = [crash |-> 0, abandon |-> 0]
    /\ seen = {}

Mark(S) == seen' = seen \cup S

MCBeginElection(s) ==
    /\ IF role[s] = "looking"
       THEN /\ votes[s] /= {s}       \* new FLE round; a repeat would stutter
            /\ UNCHANGED counters
            /\ BeginElection(s)
            /\ UNCHANGED seen
       ELSE /\ counters.abandon < MaxAbandon
            /\ BeginElection(s)
            /\ counters' = [counters EXCEPT !.abandon = @ + 1]
            /\ Mark({"abandon"})
MCCastVote(v, c) == CastVote(v, c) /\ UNCHANGED mcVars
MCElectLeader(c) == ElectLeader(c) /\ Mark({"leader"}) /\ UNCHANGED counters
MCElectFollow(s, c) == ElectFollow(s, c) /\ UNCHANGED mcVars
MCLeaderProposeEpoch(l) == LeaderProposeEpoch(l) /\ UNCHANGED mcVars
MCAcceptEpoch(s) == AcceptEpoch(s) /\ UNCHANGED mcVars
MCFinishDiscovery(l) ==
    /\ FinishDiscovery(l)
    /\ Mark(IF leaderEpoch[l] >= 2 THEN {"established", "reelect"} ELSE {"established"})
    /\ UNCHANGED counters
MCEnterSyncPhase(s) == EnterSyncPhase(s) /\ UNCHANGED mcVars
MCLeaderSyncFollower(l, s, m) ==
    /\ LeaderSyncFollower(l, s, m) /\ Mark({m}) /\ UNCHANGED counters
MCLeaderSendNewLeader(l, s) == LeaderSendNewLeader(l, s) /\ UNCHANGED mcVars
MCLeaderReadNewLeaderAck(l, s) ==
    /\ LeaderReadNewLeaderAck(l, s)
    /\ Mark(IF Head(fq[s]).kind = "NLACK" THEN {"nlAck"} ELSE {"misread"})
    /\ UNCHANGED counters
MCLeaderBroadcast(l) == LeaderBroadcast(l) /\ Mark({"broadcast"}) /\ UNCHANGED counters
MCLeaderSendUpToDate(l, s) == LeaderSendUpToDate(l, s) /\ UNCHANGED mcVars
MCLeaderProcessAck(l, s) == LeaderProcessAck(l, s) /\ UNCHANGED mcVars
MCLearnerReadMode(s) == LearnerReadMode(s) /\ UNCHANGED mcVars
MCLearnerSyncProposal(s) == LearnerSyncProposal(s) /\ UNCHANGED mcVars
MCLearnerSyncCommit(s) ==
    /\ LearnerSyncCommit(s)
    /\ Mark((IF pendingNC[s] = <<>> THEN {"npe"} ELSE {}) \cup
            (IF lstage[s] = "post" THEN {"commitAfterNl"} ELSE {}))
    /\ UNCHANGED counters
MCLearnerNewLeader(s) ==
    /\ LearnerNewLeader(s)
    /\ Mark(IF pendingNC[s] /= <<>> THEN {"nlLogged"} ELSE {})
    /\ UNCHANGED counters
MCLearnerAckNewLeader(s) ==
    /\ LearnerAckNewLeader(s)
    /\ Mark(IF \E k \in 1..Len(fq[s]) : fq[s][k].kind = "ACK"
            THEN {"ackBeforeNlAck"} ELSE {})
    /\ UNCHANGED counters
MCLearnerUpToDate(s) ==
    /\ LearnerUpToDate(s)
    /\ Mark({"uptodate"} \cup (IF unmatchedCommit'[s] THEN {"unmatched"} ELSE {}))
    /\ UNCHANGED counters
MCEnterBroadcast(s) == EnterBroadcast(s) /\ Mark({"followerBroadcast"}) /\ UNCHANGED counters
MCPropose(l, t) == Propose(l, t) /\ UNCHANGED mcVars
MCReceiveProposal(s) == ReceiveProposal(s) /\ UNCHANGED mcVars
MCAppendOne(s) == AppendOne(s) /\ UNCHANGED mcVars
MCFsyncOne(s) == FsyncOne(s) /\ UNCHANGED mcVars
MCCommit(l) == Commit(l) /\ Mark({"commit"}) /\ UNCHANGED counters
MCReceiveCommit(s) ==
    /\ ReceiveCommit(s)
    /\ Mark(IF unmatchedCommit'[s] THEN {"unmatched"} ELSE {})
    /\ UNCHANGED counters
MCApplyOne(s) == ApplyOne(s) /\ Mark({"apply"}) /\ UNCHANGED counters
MCCrash(s) ==
    /\ counters.crash < MaxCrash
    /\ Crash(s)
    /\ counters' = [counters EXCEPT !.crash = @ + 1]
    /\ Mark({"crash"})
MCRestart(s) == Restart(s) /\ Mark({"restart"}) /\ UNCHANGED counters

MCNext ==
    \/ \E s \in Server : MCBeginElection(s)
    \/ \E v, c \in Server : MCCastVote(v, c)
    \/ \E c \in Server : MCElectLeader(c)
    \/ \E s, c \in Server : MCElectFollow(s, c)
    \/ \E l \in Server : MCLeaderProposeEpoch(l)
    \/ \E s \in Server : MCAcceptEpoch(s)
    \/ \E l \in Server : MCFinishDiscovery(l)
    \/ \E s \in Server : MCEnterSyncPhase(s)
    \/ \E l, s \in Server, m \in {"DIFF", "TRUNC", "SNAP"} : MCLeaderSyncFollower(l, s, m)
    \/ \E l, s \in Server : MCLeaderSendNewLeader(l, s)
    \/ \E l, s \in Server : MCLeaderReadNewLeaderAck(l, s)
    \/ \E l \in Server : MCLeaderBroadcast(l)
    \/ \E l, s \in Server : MCLeaderSendUpToDate(l, s)
    \/ \E l, s \in Server : MCLeaderProcessAck(l, s)
    \/ \E s \in Server : MCLearnerReadMode(s)
    \/ \E s \in Server : MCLearnerSyncProposal(s)
    \/ \E s \in Server : MCLearnerSyncCommit(s)
    \/ \E s \in Server : MCLearnerNewLeader(s)
    \/ \E s \in Server : MCLearnerAckNewLeader(s)
    \/ \E s \in Server : MCLearnerUpToDate(s)
    \/ \E s \in Server : MCEnterBroadcast(s)
    \/ \E l \in Server, t \in Txn : MCPropose(l, t)
    \/ \E s \in Server : MCReceiveProposal(s)
    \/ \E s \in Server : MCAppendOne(s)
    \/ \E s \in Server : MCFsyncOne(s)
    \/ \E l \in Server : MCCommit(l)
    \/ \E s \in Server : MCReceiveCommit(s)
    \/ \E s \in Server : MCApplyOne(s)
    \/ \E s \in Server : MCCrash(s)
    \/ \E s \in Server : MCRestart(s)

MCSpec == MCInit /\ [][MCNext]_mcAllVars

\* Server and Txn model values are interchangeable in the finite models.
ModelSymmetry == Permutations(Server) \cup Permutations(Txn)

MCTypeOK ==
    /\ counters \in [crash : 0..MaxCrash, abandon : 0..MaxAbandon]
    /\ seen \subseteq SeenNames

\* Reachability canaries (negated goals; a violation is a witness).
NotLeaderReached == "leader" \notin seen
NotBroadcastReached == "broadcast" \notin seen
NotSyncReached == ({"DIFF", "TRUNC", "SNAP"} \cap seen) = {}
NotDiffReached == "DIFF" \notin seen
NotTruncReached == "TRUNC" \notin seen
NotSnapReached == "SNAP" \notin seen
NotMutationReached == "apply" \notin seen
NotRecoveryReached == ~({"crash", "restart"} \subseteq seen)
NotReelectReached == "reelect" \notin seen
NotNlLoggedReached == "nlLogged" \notin seen
NotFollowerBroadcastReached == "followerBroadcast" \notin seen
NotCommitAfterNlReached == "commitAfterNl" \notin seen
NotAckBeforeNlAckReached == "ackBeforeNlAck" \notin seen

=============================================================================
