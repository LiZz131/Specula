---- MODULE MC_TTrace_1788542910 ----
EXTENDS Sequences, TLCExt, MC, Toolbox, Naturals, TLC

_expression ==
    LET MC_TEExpression == INSTANCE MC_TEExpression
    IN MC_TEExpression!expression
----

_trace ==
    LET MC_TETrace == INSTANCE MC_TETrace
    IN MC_TETrace!trace
----

_inv ==
    ~(
        TLCGet("level") = Len(_TETrace)
        /\
        leader = (<<FALSE, FALSE, FALSE>>)
        /\
        configs = (<<{{1, 2}}, {{1, 2}}, {{1, 2}}>>)
        /\
        lastSeenTerm = (<<2, 0, 0>>)
        /\
        role = (<<"Follower", "Follower", "Learner">>)
        /\
        acceptedIndex = (<<0, 0, 0>>)
        /\
        staleCount = (0)
        /\
        durableCommit = (<<0, 0, 0>>)
        /\
        effectiveIndex = (<<0, 0, 0>>)
        /\
        pendingVoteSave = (<<FALSE, FALSE, FALSE>>)
        /\
        voteNode = (<<1, 0, 0>>)
        /\
        membershipCount = (0)
        /\
        leaderConfigs = (<<{{1, 2}}, {{1, 2}}, {{1, 2}}>>)
        /\
        flushedIndex = (<<0, 0, 0>>)
        /\
        candidate = (<<FALSE, FALSE, FALSE>>)
        /\
        committedMembershipIndex = (<<0, 0, 0>>)
        /\
        ackCount = (1)
        /\
        candidateTerm = (<<2, 0, 0>>)
        /\
        crashCount = (1)
        /\
        appendCount = (0)
        /\
        durableVoteTerm = (<<2, 0, 0>>)
        /\
        submittedIndex = (<<0, 0, 0>>)
        /\
        up = (<<TRUE, TRUE, TRUE>>)
        /\
        logs = (<<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>)
        /\
        durableVoteCommitted = (<<FALSE, FALSE, FALSE>>)
        /\
        commands = (<<{}, {}, {}>>)
        /\
        lastSeenCommitted = (<<FALSE, FALSE, FALSE>>)
        /\
        granters = (<<{}, {}, {}>>)
        /\
        voteCommitted = (<<FALSE, FALSE, FALSE>>)
        /\
        durableVoteNode = (<<1, 0, 0>>)
        /\
        match = (<<<<0, 1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>)
        /\
        lastSeenNode = (<<1, 0, 0>>)
        /\
        voteTerm = (<<2, 0, 0>>)
        /\
        leaderGrants = (<<{}, {}, {}>>)
        /\
        staleResponseSeen = (FALSE)
        /\
        learners = (<<{3}, {3}, {3}>>)
        /\
        electionCount = (2)
        /\
        durableLogs = (<<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>)
        /\
        committedConfigs = (<<{{1, 2}}, {{1, 2}}, {{1, 2}}>>)
        /\
        candidateConfigs = (<<{{1, 2}}, {{1, 2}}, {{1, 2}}>>)
        /\
        appliedIndex = (<<0, 0, 0>>)
        /\
        commitIndex = (<<0, 0, 0>>)
        /\
        candidateNode = (<<1, 0, 0>>)
        /\
        pendingVoteSend = (<<FALSE, FALSE, FALSE>>)
    )
----

_init ==
    /\ candidateConfigs = _TETrace[1].candidateConfigs
    /\ committedConfigs = _TETrace[1].committedConfigs
    /\ leader = _TETrace[1].leader
    /\ learners = _TETrace[1].learners
    /\ staleResponseSeen = _TETrace[1].staleResponseSeen
    /\ match = _TETrace[1].match
    /\ membershipCount = _TETrace[1].membershipCount
    /\ ackCount = _TETrace[1].ackCount
    /\ submittedIndex = _TETrace[1].submittedIndex
    /\ candidateTerm = _TETrace[1].candidateTerm
    /\ voteCommitted = _TETrace[1].voteCommitted
    /\ electionCount = _TETrace[1].electionCount
    /\ durableCommit = _TETrace[1].durableCommit
    /\ crashCount = _TETrace[1].crashCount
    /\ candidate = _TETrace[1].candidate
    /\ durableVoteCommitted = _TETrace[1].durableVoteCommitted
    /\ leaderConfigs = _TETrace[1].leaderConfigs
    /\ voteTerm = _TETrace[1].voteTerm
    /\ candidateNode = _TETrace[1].candidateNode
    /\ flushedIndex = _TETrace[1].flushedIndex
    /\ lastSeenTerm = _TETrace[1].lastSeenTerm
    /\ granters = _TETrace[1].granters
    /\ pendingVoteSave = _TETrace[1].pendingVoteSave
    /\ voteNode = _TETrace[1].voteNode
    /\ durableVoteTerm = _TETrace[1].durableVoteTerm
    /\ committedMembershipIndex = _TETrace[1].committedMembershipIndex
    /\ appliedIndex = _TETrace[1].appliedIndex
    /\ staleCount = _TETrace[1].staleCount
    /\ commitIndex = _TETrace[1].commitIndex
    /\ configs = _TETrace[1].configs
    /\ lastSeenNode = _TETrace[1].lastSeenNode
    /\ lastSeenCommitted = _TETrace[1].lastSeenCommitted
    /\ commands = _TETrace[1].commands
    /\ logs = _TETrace[1].logs
    /\ up = _TETrace[1].up
    /\ acceptedIndex = _TETrace[1].acceptedIndex
    /\ effectiveIndex = _TETrace[1].effectiveIndex
    /\ role = _TETrace[1].role
    /\ durableVoteNode = _TETrace[1].durableVoteNode
    /\ leaderGrants = _TETrace[1].leaderGrants
    /\ appendCount = _TETrace[1].appendCount
    /\ durableLogs = _TETrace[1].durableLogs
    /\ pendingVoteSend = _TETrace[1].pendingVoteSend
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ candidateConfigs  = _TETrace[i].candidateConfigs
        /\ candidateConfigs' = _TETrace[j].candidateConfigs
        /\ committedConfigs  = _TETrace[i].committedConfigs
        /\ committedConfigs' = _TETrace[j].committedConfigs
        /\ leader  = _TETrace[i].leader
        /\ leader' = _TETrace[j].leader
        /\ learners  = _TETrace[i].learners
        /\ learners' = _TETrace[j].learners
        /\ staleResponseSeen  = _TETrace[i].staleResponseSeen
        /\ staleResponseSeen' = _TETrace[j].staleResponseSeen
        /\ match  = _TETrace[i].match
        /\ match' = _TETrace[j].match
        /\ membershipCount  = _TETrace[i].membershipCount
        /\ membershipCount' = _TETrace[j].membershipCount
        /\ ackCount  = _TETrace[i].ackCount
        /\ ackCount' = _TETrace[j].ackCount
        /\ submittedIndex  = _TETrace[i].submittedIndex
        /\ submittedIndex' = _TETrace[j].submittedIndex
        /\ candidateTerm  = _TETrace[i].candidateTerm
        /\ candidateTerm' = _TETrace[j].candidateTerm
        /\ voteCommitted  = _TETrace[i].voteCommitted
        /\ voteCommitted' = _TETrace[j].voteCommitted
        /\ electionCount  = _TETrace[i].electionCount
        /\ electionCount' = _TETrace[j].electionCount
        /\ durableCommit  = _TETrace[i].durableCommit
        /\ durableCommit' = _TETrace[j].durableCommit
        /\ crashCount  = _TETrace[i].crashCount
        /\ crashCount' = _TETrace[j].crashCount
        /\ candidate  = _TETrace[i].candidate
        /\ candidate' = _TETrace[j].candidate
        /\ durableVoteCommitted  = _TETrace[i].durableVoteCommitted
        /\ durableVoteCommitted' = _TETrace[j].durableVoteCommitted
        /\ leaderConfigs  = _TETrace[i].leaderConfigs
        /\ leaderConfigs' = _TETrace[j].leaderConfigs
        /\ voteTerm  = _TETrace[i].voteTerm
        /\ voteTerm' = _TETrace[j].voteTerm
        /\ candidateNode  = _TETrace[i].candidateNode
        /\ candidateNode' = _TETrace[j].candidateNode
        /\ flushedIndex  = _TETrace[i].flushedIndex
        /\ flushedIndex' = _TETrace[j].flushedIndex
        /\ lastSeenTerm  = _TETrace[i].lastSeenTerm
        /\ lastSeenTerm' = _TETrace[j].lastSeenTerm
        /\ granters  = _TETrace[i].granters
        /\ granters' = _TETrace[j].granters
        /\ pendingVoteSave  = _TETrace[i].pendingVoteSave
        /\ pendingVoteSave' = _TETrace[j].pendingVoteSave
        /\ voteNode  = _TETrace[i].voteNode
        /\ voteNode' = _TETrace[j].voteNode
        /\ durableVoteTerm  = _TETrace[i].durableVoteTerm
        /\ durableVoteTerm' = _TETrace[j].durableVoteTerm
        /\ committedMembershipIndex  = _TETrace[i].committedMembershipIndex
        /\ committedMembershipIndex' = _TETrace[j].committedMembershipIndex
        /\ appliedIndex  = _TETrace[i].appliedIndex
        /\ appliedIndex' = _TETrace[j].appliedIndex
        /\ staleCount  = _TETrace[i].staleCount
        /\ staleCount' = _TETrace[j].staleCount
        /\ commitIndex  = _TETrace[i].commitIndex
        /\ commitIndex' = _TETrace[j].commitIndex
        /\ configs  = _TETrace[i].configs
        /\ configs' = _TETrace[j].configs
        /\ lastSeenNode  = _TETrace[i].lastSeenNode
        /\ lastSeenNode' = _TETrace[j].lastSeenNode
        /\ lastSeenCommitted  = _TETrace[i].lastSeenCommitted
        /\ lastSeenCommitted' = _TETrace[j].lastSeenCommitted
        /\ commands  = _TETrace[i].commands
        /\ commands' = _TETrace[j].commands
        /\ logs  = _TETrace[i].logs
        /\ logs' = _TETrace[j].logs
        /\ up  = _TETrace[i].up
        /\ up' = _TETrace[j].up
        /\ acceptedIndex  = _TETrace[i].acceptedIndex
        /\ acceptedIndex' = _TETrace[j].acceptedIndex
        /\ effectiveIndex  = _TETrace[i].effectiveIndex
        /\ effectiveIndex' = _TETrace[j].effectiveIndex
        /\ role  = _TETrace[i].role
        /\ role' = _TETrace[j].role
        /\ durableVoteNode  = _TETrace[i].durableVoteNode
        /\ durableVoteNode' = _TETrace[j].durableVoteNode
        /\ leaderGrants  = _TETrace[i].leaderGrants
        /\ leaderGrants' = _TETrace[j].leaderGrants
        /\ appendCount  = _TETrace[i].appendCount
        /\ appendCount' = _TETrace[j].appendCount
        /\ durableLogs  = _TETrace[i].durableLogs
        /\ durableLogs' = _TETrace[j].durableLogs
        /\ pendingVoteSend  = _TETrace[i].pendingVoteSend
        /\ pendingVoteSend' = _TETrace[j].pendingVoteSend

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("MC_TTrace_1788542910.json", _TETrace)

=============================================================================

 Note that you can extract this module `MC_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `MC_TEExpression.tla` file takes precedence 
  over the module `MC_TEExpression` below).

---- MODULE MC_TEExpression ----
EXTENDS Sequences, TLCExt, MC, Toolbox, Naturals, TLC

expression == 
    [
        \* To hide variables of the `MC` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        candidateConfigs |-> candidateConfigs
        ,committedConfigs |-> committedConfigs
        ,leader |-> leader
        ,learners |-> learners
        ,staleResponseSeen |-> staleResponseSeen
        ,match |-> match
        ,membershipCount |-> membershipCount
        ,ackCount |-> ackCount
        ,submittedIndex |-> submittedIndex
        ,candidateTerm |-> candidateTerm
        ,voteCommitted |-> voteCommitted
        ,electionCount |-> electionCount
        ,durableCommit |-> durableCommit
        ,crashCount |-> crashCount
        ,candidate |-> candidate
        ,durableVoteCommitted |-> durableVoteCommitted
        ,leaderConfigs |-> leaderConfigs
        ,voteTerm |-> voteTerm
        ,candidateNode |-> candidateNode
        ,flushedIndex |-> flushedIndex
        ,lastSeenTerm |-> lastSeenTerm
        ,granters |-> granters
        ,pendingVoteSave |-> pendingVoteSave
        ,voteNode |-> voteNode
        ,durableVoteTerm |-> durableVoteTerm
        ,committedMembershipIndex |-> committedMembershipIndex
        ,appliedIndex |-> appliedIndex
        ,staleCount |-> staleCount
        ,commitIndex |-> commitIndex
        ,configs |-> configs
        ,lastSeenNode |-> lastSeenNode
        ,lastSeenCommitted |-> lastSeenCommitted
        ,commands |-> commands
        ,logs |-> logs
        ,up |-> up
        ,acceptedIndex |-> acceptedIndex
        ,effectiveIndex |-> effectiveIndex
        ,role |-> role
        ,durableVoteNode |-> durableVoteNode
        ,leaderGrants |-> leaderGrants
        ,appendCount |-> appendCount
        ,durableLogs |-> durableLogs
        ,pendingVoteSend |-> pendingVoteSend
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_candidateConfigsUnchanged |-> candidateConfigs = candidateConfigs'
        
        \* Format the `candidateConfigs` variable as Json value.
        \* ,_candidateConfigsJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(candidateConfigs)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_candidateConfigsModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].candidateConfigs # _TETrace[s-1].candidateConfigs
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE MC_TETrace ----
\*EXTENDS IOUtils, MC, TLC
\*
\*trace == IODeserialize("MC_TTrace_1788542910.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE MC_TETrace ----
EXTENDS MC, TLC

trace == 
    <<
    ([leader |-> <<FALSE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<0, 0, 0>>,role |-> <<"Follower", "Follower", "Learner">>,acceptedIndex |-> <<0, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<FALSE, FALSE, FALSE>>,voteNode |-> <<0, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<FALSE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 0,candidateTerm |-> <<0, 0, 0>>,crashCount |-> 0,appendCount |-> 0,durableVoteTerm |-> <<0, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{}, {}, {}>>,lastSeenCommitted |-> <<FALSE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<FALSE, FALSE, FALSE>>,durableVoteNode |-> <<0, 0, 0>>,match |-> <<<<0, -1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<0, 0, 0>>,voteTerm |-> <<0, 0, 0>>,leaderGrants |-> <<{}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 0,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<0, 0, 0>>,pendingVoteSend |-> <<FALSE, FALSE, FALSE>>]),
    ([leader |-> <<FALSE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<1, 0, 0>>,role |-> <<"Candidate", "Follower", "Learner">>,acceptedIndex |-> <<0, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<TRUE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<TRUE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 0,candidateTerm |-> <<1, 0, 0>>,crashCount |-> 0,appendCount |-> 0,durableVoteTerm |-> <<0, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{"SaveVote", "SendVote"}, {}, {}>>,lastSeenCommitted |-> <<FALSE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<FALSE, FALSE, FALSE>>,durableVoteNode |-> <<0, 0, 0>>,match |-> <<<<0, -1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<1, 0, 0>>,leaderGrants |-> <<{}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 1,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<TRUE, FALSE, FALSE>>]),
    ([leader |-> <<FALSE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<2, 0, 0>>,role |-> <<"Candidate", "Follower", "Learner">>,acceptedIndex |-> <<0, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<TRUE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<TRUE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 0,candidateTerm |-> <<2, 0, 0>>,crashCount |-> 0,appendCount |-> 0,durableVoteTerm |-> <<0, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{"SaveVote", "SendVote"}, {}, {}>>,lastSeenCommitted |-> <<FALSE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<FALSE, FALSE, FALSE>>,durableVoteNode |-> <<0, 0, 0>>,match |-> <<<<0, -1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<2, 0, 0>>,leaderGrants |-> <<{}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 2,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<TRUE, FALSE, FALSE>>]),
    ([leader |-> <<FALSE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<2, 0, 0>>,role |-> <<"Candidate", "Follower", "Learner">>,acceptedIndex |-> <<0, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<FALSE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<TRUE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 0,candidateTerm |-> <<2, 0, 0>>,crashCount |-> 0,appendCount |-> 0,durableVoteTerm |-> <<2, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{}, {}, {}>>,lastSeenCommitted |-> <<FALSE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<FALSE, FALSE, FALSE>>,durableVoteNode |-> <<1, 0, 0>>,match |-> <<<<0, -1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<2, 0, 0>>,leaderGrants |-> <<{}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 2,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<TRUE, FALSE, FALSE>>]),
    ([leader |-> <<FALSE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<2, 0, 0>>,role |-> <<"Candidate", "Follower", "Learner">>,acceptedIndex |-> <<0, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<FALSE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<TRUE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 0,candidateTerm |-> <<2, 0, 0>>,crashCount |-> 0,appendCount |-> 0,durableVoteTerm |-> <<2, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{}, {}, {}>>,lastSeenCommitted |-> <<FALSE, FALSE, FALSE>>,granters |-> <<{1}, {}, {}>>,voteCommitted |-> <<FALSE, FALSE, FALSE>>,durableVoteNode |-> <<1, 0, 0>>,match |-> <<<<0, -1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<2, 0, 0>>,leaderGrants |-> <<{}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 2,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<TRUE, FALSE, FALSE>>]),
    ([leader |-> <<TRUE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<2, 0, 0>>,role |-> <<"Leader", "Follower", "Learner">>,acceptedIndex |-> <<1, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<TRUE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<FALSE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 0,candidateTerm |-> <<2, 0, 0>>,crashCount |-> 0,appendCount |-> 0,durableVoteTerm |-> <<2, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"], [learners |-> {3}, cfg |-> {{1, 2}}, term |-> 2, node |-> 1, kind |-> "blank"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{"SaveVote", "AppendInputEntries", "Replicate", "RebuildReplicationStreams"}, {}, {}>>,lastSeenCommitted |-> <<TRUE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<TRUE, FALSE, FALSE>>,durableVoteNode |-> <<1, 0, 0>>,match |-> <<<<0, -1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<2, 0, 0>>,leaderGrants |-> <<{1, 2}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 2,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<TRUE, FALSE, FALSE>>]),
    ([leader |-> <<TRUE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<2, 0, 0>>,role |-> <<"Leader", "Follower", "Learner">>,acceptedIndex |-> <<1, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<TRUE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<FALSE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 1,candidateTerm |-> <<2, 0, 0>>,crashCount |-> 0,appendCount |-> 0,durableVoteTerm |-> <<2, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"], [learners |-> {3}, cfg |-> {{1, 2}}, term |-> 2, node |-> 1, kind |-> "blank"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{}, {}, {}>>,lastSeenCommitted |-> <<TRUE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<TRUE, FALSE, FALSE>>,durableVoteNode |-> <<1, 0, 0>>,match |-> <<<<0, 1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<2, 0, 0>>,leaderGrants |-> <<{1, 2}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 2,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<TRUE, FALSE, FALSE>>]),
    ([leader |-> <<FALSE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<2, 0, 0>>,role |-> <<"Learner", "Follower", "Learner">>,acceptedIndex |-> <<1, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<FALSE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<FALSE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 1,candidateTerm |-> <<2, 0, 0>>,crashCount |-> 1,appendCount |-> 0,durableVoteTerm |-> <<2, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<FALSE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"], [learners |-> {3}, cfg |-> {{1, 2}}, term |-> 2, node |-> 1, kind |-> "blank"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{}, {}, {}>>,lastSeenCommitted |-> <<TRUE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<TRUE, FALSE, FALSE>>,durableVoteNode |-> <<1, 0, 0>>,match |-> <<<<0, 1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<2, 0, 0>>,leaderGrants |-> <<{1, 2}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 2,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<FALSE, FALSE, FALSE>>]),
    ([leader |-> <<FALSE, FALSE, FALSE>>,configs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,lastSeenTerm |-> <<2, 0, 0>>,role |-> <<"Follower", "Follower", "Learner">>,acceptedIndex |-> <<0, 0, 0>>,staleCount |-> 0,durableCommit |-> <<0, 0, 0>>,effectiveIndex |-> <<0, 0, 0>>,pendingVoteSave |-> <<FALSE, FALSE, FALSE>>,voteNode |-> <<1, 0, 0>>,membershipCount |-> 0,leaderConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,flushedIndex |-> <<0, 0, 0>>,candidate |-> <<FALSE, FALSE, FALSE>>,committedMembershipIndex |-> <<0, 0, 0>>,ackCount |-> 1,candidateTerm |-> <<2, 0, 0>>,crashCount |-> 1,appendCount |-> 0,durableVoteTerm |-> <<2, 0, 0>>,submittedIndex |-> <<0, 0, 0>>,up |-> <<TRUE, TRUE, TRUE>>,logs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,durableVoteCommitted |-> <<FALSE, FALSE, FALSE>>,commands |-> <<{}, {}, {}>>,lastSeenCommitted |-> <<FALSE, FALSE, FALSE>>,granters |-> <<{}, {}, {}>>,voteCommitted |-> <<FALSE, FALSE, FALSE>>,durableVoteNode |-> <<1, 0, 0>>,match |-> <<<<0, 1, -1>>, <<-1, 0, -1>>, <<-1, -1, 0>>>>,lastSeenNode |-> <<1, 0, 0>>,voteTerm |-> <<2, 0, 0>>,leaderGrants |-> <<{}, {}, {}>>,staleResponseSeen |-> FALSE,learners |-> <<{3}, {3}, {3}>>,electionCount |-> 2,durableLogs |-> <<<<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>, <<[learners |-> {3}, cfg |-> {{1, 2}}, term |-> 0, node |-> 0, kind |-> "uniform"]>>>>,committedConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,candidateConfigs |-> <<{{1, 2}}, {{1, 2}}, {{1, 2}}>>,appliedIndex |-> <<0, 0, 0>>,commitIndex |-> <<0, 0, 0>>,candidateNode |-> <<1, 0, 0>>,pendingVoteSend |-> <<FALSE, FALSE, FALSE>>])
    >>
----


=============================================================================

---- CONFIG MC_TTrace_1788542910 ----
CONSTANTS
    Server = { 1 , 2 , 3 }
    NoNode = 0
    InitialVoters = { 1 , 2 }
    MaxTerm = 2
    MaxIndex = 3
    ElectionLimit = 2
    AppendLimit = 2
    MembershipLimit = 2
    AckLimit = 3
    CrashLimit = 1
    StaleLimit = 1

INVARIANT
    _inv

CHECK_DEADLOCK
    \* CHECK_DEADLOCK off because of PROPERTY or INVARIANT above.
    FALSE

INIT
    _init

NEXT
    _next

CONSTANT
    _TETrace <- _trace

ALIAS
    _expression
=============================================================================
\* Generated on Fri Sep 04 17:28:55 UTC 2026