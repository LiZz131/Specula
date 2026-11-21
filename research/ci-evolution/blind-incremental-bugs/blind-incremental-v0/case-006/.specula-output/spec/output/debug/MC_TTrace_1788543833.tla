---- MODULE MC_TTrace_1788543833 ----
EXTENDS Sequences, TLCExt, MC, Toolbox, Naturals, TLC, MC_TEConstants

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
        leader = ((s1 :> s1 @@ s2 :> Nil @@ s3 :> s1))
        /\
        role = ((s1 :> Leader @@ s2 :> Follower @@ s3 :> Follower))
        /\
        scenarioSeen = ([proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> TRUE, leader |-> TRUE, readyRead |-> FALSE, election |-> TRUE, append |-> TRUE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE])
        /\
        alive = ((s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE))
        /\
        readQueue = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        durableCommit = ((s1 :> 0 @@ s2 :> 0 @@ s3 :> 0))
        /\
        nextIndex = ((s1 :> (s1 :> 2 @@ s2 :> 2 @@ s3 :> 2) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)))
        /\
        faultCounters = ([campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 4, quorumCheck |-> 0, crash |-> 0, lose |-> 0])
        /\
        votesGranted = ((s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}))
        /\
        term = ((s1 :> 1 @@ s2 :> 1 @@ s3 :> 1))
        /\
        vote = ((s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil))
        /\
        logs = ((s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<[term |-> 1, value |-> Nil]>>))
        /\
        recentActive = ((s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> TRUE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)))
        /\
        publishedReads = (<<>>)
        /\
        producedReads = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        readyOutstanding = ((s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE))
        /\
        durableTerm = ((s1 :> 1 @@ s2 :> 1 @@ s3 :> 1))
        /\
        commitHistory = ({[index |-> 1, entry |-> [term |-> 1, value |-> Nil], commitTerm |-> 1]})
        /\
        leaderHistory = ({[term |-> 1, node |-> s1]})
        /\
        durableLogs = ((s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<[term |-> 1, value |-> Nil]>>))
        /\
        matchIndex = ((s1 :> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 1) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)))
        /\
        messages = ({[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil]})
        /\
        durableVote = ((s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil))
        /\
        pendingReads = ((s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])))
        /\
        appliedIndex = ((s1 :> 0 @@ s2 :> 0 @@ s3 :> 0))
        /\
        commitIndex = ((s1 :> 1 @@ s2 :> 0 @@ s3 :> 0))
    )
----

_init ==
    /\ durableCommit = _TETrace[1].durableCommit
    /\ leader = _TETrace[1].leader
    /\ vote = _TETrace[1].vote
    /\ durableVote = _TETrace[1].durableVote
    /\ logs = _TETrace[1].logs
    /\ durableLogs = _TETrace[1].durableLogs
    /\ readQueue = _TETrace[1].readQueue
    /\ pendingReads = _TETrace[1].pendingReads
    /\ recentActive = _TETrace[1].recentActive
    /\ role = _TETrace[1].role
    /\ commitHistory = _TETrace[1].commitHistory
    /\ publishedReads = _TETrace[1].publishedReads
    /\ nextIndex = _TETrace[1].nextIndex
    /\ scenarioSeen = _TETrace[1].scenarioSeen
    /\ producedReads = _TETrace[1].producedReads
    /\ matchIndex = _TETrace[1].matchIndex
    /\ leaderHistory = _TETrace[1].leaderHistory
    /\ readyOutstanding = _TETrace[1].readyOutstanding
    /\ appliedIndex = _TETrace[1].appliedIndex
    /\ commitIndex = _TETrace[1].commitIndex
    /\ term = _TETrace[1].term
    /\ durableTerm = _TETrace[1].durableTerm
    /\ faultCounters = _TETrace[1].faultCounters
    /\ messages = _TETrace[1].messages
    /\ votesGranted = _TETrace[1].votesGranted
    /\ alive = _TETrace[1].alive
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ durableCommit  = _TETrace[i].durableCommit
        /\ durableCommit' = _TETrace[j].durableCommit
        /\ leader  = _TETrace[i].leader
        /\ leader' = _TETrace[j].leader
        /\ vote  = _TETrace[i].vote
        /\ vote' = _TETrace[j].vote
        /\ durableVote  = _TETrace[i].durableVote
        /\ durableVote' = _TETrace[j].durableVote
        /\ logs  = _TETrace[i].logs
        /\ logs' = _TETrace[j].logs
        /\ durableLogs  = _TETrace[i].durableLogs
        /\ durableLogs' = _TETrace[j].durableLogs
        /\ readQueue  = _TETrace[i].readQueue
        /\ readQueue' = _TETrace[j].readQueue
        /\ pendingReads  = _TETrace[i].pendingReads
        /\ pendingReads' = _TETrace[j].pendingReads
        /\ recentActive  = _TETrace[i].recentActive
        /\ recentActive' = _TETrace[j].recentActive
        /\ role  = _TETrace[i].role
        /\ role' = _TETrace[j].role
        /\ commitHistory  = _TETrace[i].commitHistory
        /\ commitHistory' = _TETrace[j].commitHistory
        /\ publishedReads  = _TETrace[i].publishedReads
        /\ publishedReads' = _TETrace[j].publishedReads
        /\ nextIndex  = _TETrace[i].nextIndex
        /\ nextIndex' = _TETrace[j].nextIndex
        /\ scenarioSeen  = _TETrace[i].scenarioSeen
        /\ scenarioSeen' = _TETrace[j].scenarioSeen
        /\ producedReads  = _TETrace[i].producedReads
        /\ producedReads' = _TETrace[j].producedReads
        /\ matchIndex  = _TETrace[i].matchIndex
        /\ matchIndex' = _TETrace[j].matchIndex
        /\ leaderHistory  = _TETrace[i].leaderHistory
        /\ leaderHistory' = _TETrace[j].leaderHistory
        /\ readyOutstanding  = _TETrace[i].readyOutstanding
        /\ readyOutstanding' = _TETrace[j].readyOutstanding
        /\ appliedIndex  = _TETrace[i].appliedIndex
        /\ appliedIndex' = _TETrace[j].appliedIndex
        /\ commitIndex  = _TETrace[i].commitIndex
        /\ commitIndex' = _TETrace[j].commitIndex
        /\ term  = _TETrace[i].term
        /\ term' = _TETrace[j].term
        /\ durableTerm  = _TETrace[i].durableTerm
        /\ durableTerm' = _TETrace[j].durableTerm
        /\ faultCounters  = _TETrace[i].faultCounters
        /\ faultCounters' = _TETrace[j].faultCounters
        /\ messages  = _TETrace[i].messages
        /\ messages' = _TETrace[j].messages
        /\ votesGranted  = _TETrace[i].votesGranted
        /\ votesGranted' = _TETrace[j].votesGranted
        /\ alive  = _TETrace[i].alive
        /\ alive' = _TETrace[j].alive

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("MC_TTrace_1788543833.json", _TETrace)

=============================================================================

 Note that you can extract this module `MC_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `MC_TEExpression.tla` file takes precedence 
  over the module `MC_TEExpression` below).

---- MODULE MC_TEExpression ----
EXTENDS Sequences, TLCExt, MC, Toolbox, Naturals, TLC, MC_TEConstants

expression == 
    [
        \* To hide variables of the `MC` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        durableCommit |-> durableCommit
        ,leader |-> leader
        ,vote |-> vote
        ,durableVote |-> durableVote
        ,logs |-> logs
        ,durableLogs |-> durableLogs
        ,readQueue |-> readQueue
        ,pendingReads |-> pendingReads
        ,recentActive |-> recentActive
        ,role |-> role
        ,commitHistory |-> commitHistory
        ,publishedReads |-> publishedReads
        ,nextIndex |-> nextIndex
        ,scenarioSeen |-> scenarioSeen
        ,producedReads |-> producedReads
        ,matchIndex |-> matchIndex
        ,leaderHistory |-> leaderHistory
        ,readyOutstanding |-> readyOutstanding
        ,appliedIndex |-> appliedIndex
        ,commitIndex |-> commitIndex
        ,term |-> term
        ,durableTerm |-> durableTerm
        ,faultCounters |-> faultCounters
        ,messages |-> messages
        ,votesGranted |-> votesGranted
        ,alive |-> alive
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_durableCommitUnchanged |-> durableCommit = durableCommit'
        
        \* Format the `durableCommit` variable as Json value.
        \* ,_durableCommitJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(durableCommit)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_durableCommitModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].durableCommit # _TETrace[s-1].durableCommit
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE MC_TETrace ----
\*EXTENDS IOUtils, MC, TLC, MC_TEConstants
\*
\*trace == IODeserialize("MC_TTrace_1788543833.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE MC_TETrace ----
EXTENDS MC, TLC, MC_TEConstants

trace == 
    <<
    ([leader |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Follower @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> FALSE, readyRead |-> FALSE, election |-> FALSE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 0, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 0, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),vote |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),logs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),durableTerm |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {},durableVote |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Candidate @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> FALSE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 0, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> Nil),logs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),durableTerm |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Candidate @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> FALSE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 1, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> Nil),logs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> FALSE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Candidate @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> FALSE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 1, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> FALSE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgVoteResp, from |-> s2, reject |-> FALSE, to |-> s1, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Candidate @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> FALSE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 2, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgVoteResp, from |-> s2, reject |-> FALSE, to |-> s1, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Candidate @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> FALSE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 2, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> Nil @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Candidate @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> FALSE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 2, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Leader @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> TRUE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 2 @@ s2 :> 2 @@ s3 :> 2) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 2, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> FALSE @@ s2 :> TRUE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {[term |-> 1, node |-> s1]},durableLogs |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> Nil),role |-> (s1 :> Leader @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> TRUE, readyRead |-> FALSE, election |-> TRUE, append |-> FALSE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 2 @@ s2 :> 2 @@ s3 :> 2) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 3, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {[term |-> 1, node |-> s1]},durableLogs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> s1),role |-> (s1 :> Leader @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> TRUE, readyRead |-> FALSE, election |-> TRUE, append |-> TRUE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 2 @@ s2 :> 2 @@ s3 :> 2) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 3, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<[term |-> 1, value |-> Nil]>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> FALSE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 0),commitHistory |-> {},leaderHistory |-> {[term |-> 1, node |-> s1]},durableLogs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<>>),matchIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgAppResp, from |-> s3, reject |-> FALSE, to |-> s1, commit |-> 0, index |-> 1, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> s1),role |-> (s1 :> Leader @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> FALSE, leader |-> TRUE, readyRead |-> FALSE, election |-> TRUE, append |-> TRUE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 2 @@ s2 :> 2 @@ s3 :> 2) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 4, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<[term |-> 1, value |-> Nil]>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),commitHistory |-> {},leaderHistory |-> {[term |-> 1, node |-> s1]},durableLogs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<[term |-> 1, value |-> Nil]>>),matchIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgAppResp, from |-> s3, reject |-> FALSE, to |-> s1, commit |-> 0, index |-> 1, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)]),
    ([leader |-> (s1 :> s1 @@ s2 :> Nil @@ s3 :> s1),role |-> (s1 :> Leader @@ s2 :> Follower @@ s3 :> Follower),scenarioSeen |-> [proposal |-> FALSE, heartbeat |-> FALSE, quorumCheck |-> FALSE, crash |-> FALSE, commit |-> TRUE, leader |-> TRUE, readyRead |-> FALSE, election |-> TRUE, append |-> TRUE, readRequest |-> FALSE, readQuorum |-> FALSE, loss |-> FALSE, restart |-> FALSE],alive |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),readQueue |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),durableCommit |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),nextIndex |-> (s1 :> (s1 :> 2 @@ s2 :> 2 @@ s3 :> 2) @@ s2 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1) @@ s3 :> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1)),faultCounters |-> [campaign |-> 1, proposal |-> 0, heartbeat |-> 0, read |-> 0, ready |-> 4, quorumCheck |-> 0, crash |-> 0, lose |-> 0],votesGranted |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),term |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),vote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),logs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<[term |-> 1, value |-> Nil]>>),recentActive |-> (s1 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> TRUE) @@ s2 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE) @@ s3 :> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)),publishedReads |-> <<>>,producedReads |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),readyOutstanding |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),durableTerm |-> (s1 :> 1 @@ s2 :> 1 @@ s3 :> 1),commitHistory |-> {[index |-> 1, entry |-> [term |-> 1, value |-> Nil], commitTerm |-> 1]},leaderHistory |-> {[term |-> 1, node |-> s1]},durableLogs |-> (s1 :> <<[term |-> 1, value |-> Nil]>> @@ s2 :> <<>> @@ s3 :> <<[term |-> 1, value |-> Nil]>>),matchIndex |-> (s1 :> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 1) @@ s2 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0) @@ s3 :> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0)),messages |-> {[term |-> 1, mtype |-> MsgVote, from |-> s1, reject |-> FALSE, to |-> s3, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 0, value |-> Nil, ctx |-> Nil], [term |-> 1, mtype |-> MsgApp, from |-> s1, reject |-> FALSE, to |-> s2, commit |-> 0, index |-> 0, logTerm |-> 0, entryTerm |-> 1, value |-> Nil, ctx |-> Nil]},durableVote |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> Nil),pendingReads |-> (s1 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s2 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}]) @@ s3 :> (ctx1 :> [index |-> 0, active |-> FALSE, requester |-> Nil, acks |-> {}])),appliedIndex |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitIndex |-> (s1 :> 1 @@ s2 :> 0 @@ s3 :> 0)])
    >>
----


=============================================================================

---- MODULE MC_TEConstants ----
EXTENDS MC

CONSTANTS s1, s2, s3, v1, ctx1

=============================================================================

---- CONFIG MC_TTrace_1788543833 ----
CONSTANTS
    Server = { s1 , s2 , s3 }
    Values = { v1 }
    ReadContexts = { ctx1 }
    Nil = Nil
    MaxTerm = 2
    MaxLogLen = 3
    Follower = Follower
    Candidate = Candidate
    Leader = Leader
    MsgVote = MsgVote
    MsgVoteResp = MsgVoteResp
    MsgApp = MsgApp
    MsgAppResp = MsgAppResp
    MsgHeartbeat = MsgHeartbeat
    MsgHeartbeatResp = MsgHeartbeatResp
    MsgReadIndex = MsgReadIndex
    MsgReadIndexResp = MsgReadIndexResp
    MaxCampaignLimit = 2
    MaxProposalLimit = 2
    MaxHeartbeatLimit = 1
    MaxReadLimit = 0
    MaxReadyLimit = 5
    MaxQuorumCheckLimit = 0
    MaxCrashLimit = 1
    MaxLoseLimit = 2
    MaxMsgBufferLimit = 7
    ctx1 = ctx1
    s2 = s2
    MsgApp = MsgApp
    MsgVoteResp = MsgVoteResp
    MsgHeartbeatResp = MsgHeartbeatResp
    Candidate = Candidate
    Nil = Nil
    s1 = s1
    MsgHeartbeat = MsgHeartbeat
    Leader = Leader
    Follower = Follower
    v1 = v1
    s3 = s3
    MsgAppResp = MsgAppResp
    MsgVote = MsgVote
    MsgReadIndex = MsgReadIndex
    MsgReadIndexResp = MsgReadIndexResp

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
\* Generated on Fri Sep 04 17:44:00 UTC 2026