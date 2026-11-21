---- MODULE MC_TTrace_1788549234 ----
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
        role = ((s1 :> "LEADING" @@ s2 :> "LOOKING" @@ s3 :> "LOOKING"))
        /\
        applied = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        prepared = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        globalCommitted = (<<>>)
        /\
        pending = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        leaderOf = ((s1 :> s1 @@ s2 :> NoServer @@ s3 :> NoServer))
        /\
        newLeaderAcks = ((s1 :> {} @@ s2 :> {} @@ s3 :> {}))
        /\
        currentEpoch = ((s1 :> 0 @@ s2 :> 0 @@ s3 :> 0))
        /\
        seen = ({"Init", "CastVote", "FinishElection"})
        /\
        running = ((s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE))
        /\
        durable = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        acceptedEpoch = ((s1 :> 0 @@ s2 :> 0 @@ s3 :> 0))
        /\
        electionRound = (0)
        /\
        syncQueued = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        snapshotImage = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        syncMode = ((s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE"))
        /\
        snapshotPublished = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        phase = ((s1 :> "ELECTION" @@ s2 :> "ELECTION" @@ s3 :> "ELECTION"))
        /\
        nextTxn = (1)
        /\
        votedFor = ((s1 :> s1 @@ s2 :> s1 @@ s3 :> NoServer))
        /\
        committed = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        recoveryVisible = ((s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>))
        /\
        counters = ([rounds |-> 0, crashes |-> 0, snapshots |-> 0])
        /\
        acks = (<<{}>>)
        /\
        durabilityEvidence = (<<{}>>)
        /\
        electionVotes = ((s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}))
        /\
        epochAcks = ((s1 :> {} @@ s2 :> {} @@ s3 :> {}))
        /\
        snapshotBusy = ((s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE))
        /\
        epochProposal = ((s1 :> 0 @@ s2 :> 0 @@ s3 :> 0))
        /\
        commitWitness = (<<{}>>)
        /\
        lastTransition = ("FinishElection")
        /\
        syncComplete = ((s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE))
        /\
        newLeaderReady = ((s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE))
    )
----

_init ==
    /\ phase = _TETrace[1].phase
    /\ epochAcks = _TETrace[1].epochAcks
    /\ newLeaderReady = _TETrace[1].newLeaderReady
    /\ durable = _TETrace[1].durable
    /\ globalCommitted = _TETrace[1].globalCommitted
    /\ running = _TETrace[1].running
    /\ newLeaderAcks = _TETrace[1].newLeaderAcks
    /\ commitWitness = _TETrace[1].commitWitness
    /\ electionVotes = _TETrace[1].electionVotes
    /\ acks = _TETrace[1].acks
    /\ counters = _TETrace[1].counters
    /\ currentEpoch = _TETrace[1].currentEpoch
    /\ durabilityEvidence = _TETrace[1].durabilityEvidence
    /\ syncComplete = _TETrace[1].syncComplete
    /\ applied = _TETrace[1].applied
    /\ electionRound = _TETrace[1].electionRound
    /\ pending = _TETrace[1].pending
    /\ snapshotBusy = _TETrace[1].snapshotBusy
    /\ syncQueued = _TETrace[1].syncQueued
    /\ snapshotImage = _TETrace[1].snapshotImage
    /\ acceptedEpoch = _TETrace[1].acceptedEpoch
    /\ epochProposal = _TETrace[1].epochProposal
    /\ committed = _TETrace[1].committed
    /\ leaderOf = _TETrace[1].leaderOf
    /\ recoveryVisible = _TETrace[1].recoveryVisible
    /\ role = _TETrace[1].role
    /\ lastTransition = _TETrace[1].lastTransition
    /\ syncMode = _TETrace[1].syncMode
    /\ snapshotPublished = _TETrace[1].snapshotPublished
    /\ votedFor = _TETrace[1].votedFor
    /\ nextTxn = _TETrace[1].nextTxn
    /\ prepared = _TETrace[1].prepared
    /\ seen = _TETrace[1].seen
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ phase  = _TETrace[i].phase
        /\ phase' = _TETrace[j].phase
        /\ epochAcks  = _TETrace[i].epochAcks
        /\ epochAcks' = _TETrace[j].epochAcks
        /\ newLeaderReady  = _TETrace[i].newLeaderReady
        /\ newLeaderReady' = _TETrace[j].newLeaderReady
        /\ durable  = _TETrace[i].durable
        /\ durable' = _TETrace[j].durable
        /\ globalCommitted  = _TETrace[i].globalCommitted
        /\ globalCommitted' = _TETrace[j].globalCommitted
        /\ running  = _TETrace[i].running
        /\ running' = _TETrace[j].running
        /\ newLeaderAcks  = _TETrace[i].newLeaderAcks
        /\ newLeaderAcks' = _TETrace[j].newLeaderAcks
        /\ commitWitness  = _TETrace[i].commitWitness
        /\ commitWitness' = _TETrace[j].commitWitness
        /\ electionVotes  = _TETrace[i].electionVotes
        /\ electionVotes' = _TETrace[j].electionVotes
        /\ acks  = _TETrace[i].acks
        /\ acks' = _TETrace[j].acks
        /\ counters  = _TETrace[i].counters
        /\ counters' = _TETrace[j].counters
        /\ currentEpoch  = _TETrace[i].currentEpoch
        /\ currentEpoch' = _TETrace[j].currentEpoch
        /\ durabilityEvidence  = _TETrace[i].durabilityEvidence
        /\ durabilityEvidence' = _TETrace[j].durabilityEvidence
        /\ syncComplete  = _TETrace[i].syncComplete
        /\ syncComplete' = _TETrace[j].syncComplete
        /\ applied  = _TETrace[i].applied
        /\ applied' = _TETrace[j].applied
        /\ electionRound  = _TETrace[i].electionRound
        /\ electionRound' = _TETrace[j].electionRound
        /\ pending  = _TETrace[i].pending
        /\ pending' = _TETrace[j].pending
        /\ snapshotBusy  = _TETrace[i].snapshotBusy
        /\ snapshotBusy' = _TETrace[j].snapshotBusy
        /\ syncQueued  = _TETrace[i].syncQueued
        /\ syncQueued' = _TETrace[j].syncQueued
        /\ snapshotImage  = _TETrace[i].snapshotImage
        /\ snapshotImage' = _TETrace[j].snapshotImage
        /\ acceptedEpoch  = _TETrace[i].acceptedEpoch
        /\ acceptedEpoch' = _TETrace[j].acceptedEpoch
        /\ epochProposal  = _TETrace[i].epochProposal
        /\ epochProposal' = _TETrace[j].epochProposal
        /\ committed  = _TETrace[i].committed
        /\ committed' = _TETrace[j].committed
        /\ leaderOf  = _TETrace[i].leaderOf
        /\ leaderOf' = _TETrace[j].leaderOf
        /\ recoveryVisible  = _TETrace[i].recoveryVisible
        /\ recoveryVisible' = _TETrace[j].recoveryVisible
        /\ role  = _TETrace[i].role
        /\ role' = _TETrace[j].role
        /\ lastTransition  = _TETrace[i].lastTransition
        /\ lastTransition' = _TETrace[j].lastTransition
        /\ syncMode  = _TETrace[i].syncMode
        /\ syncMode' = _TETrace[j].syncMode
        /\ snapshotPublished  = _TETrace[i].snapshotPublished
        /\ snapshotPublished' = _TETrace[j].snapshotPublished
        /\ votedFor  = _TETrace[i].votedFor
        /\ votedFor' = _TETrace[j].votedFor
        /\ nextTxn  = _TETrace[i].nextTxn
        /\ nextTxn' = _TETrace[j].nextTxn
        /\ prepared  = _TETrace[i].prepared
        /\ prepared' = _TETrace[j].prepared
        /\ seen  = _TETrace[i].seen
        /\ seen' = _TETrace[j].seen

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("MC_TTrace_1788549234.json", _TETrace)

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
        phase |-> phase
        ,epochAcks |-> epochAcks
        ,newLeaderReady |-> newLeaderReady
        ,durable |-> durable
        ,globalCommitted |-> globalCommitted
        ,running |-> running
        ,newLeaderAcks |-> newLeaderAcks
        ,commitWitness |-> commitWitness
        ,electionVotes |-> electionVotes
        ,acks |-> acks
        ,counters |-> counters
        ,currentEpoch |-> currentEpoch
        ,durabilityEvidence |-> durabilityEvidence
        ,syncComplete |-> syncComplete
        ,applied |-> applied
        ,electionRound |-> electionRound
        ,pending |-> pending
        ,snapshotBusy |-> snapshotBusy
        ,syncQueued |-> syncQueued
        ,snapshotImage |-> snapshotImage
        ,acceptedEpoch |-> acceptedEpoch
        ,epochProposal |-> epochProposal
        ,committed |-> committed
        ,leaderOf |-> leaderOf
        ,recoveryVisible |-> recoveryVisible
        ,role |-> role
        ,lastTransition |-> lastTransition
        ,syncMode |-> syncMode
        ,snapshotPublished |-> snapshotPublished
        ,votedFor |-> votedFor
        ,nextTxn |-> nextTxn
        ,prepared |-> prepared
        ,seen |-> seen
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_phaseUnchanged |-> phase = phase'
        
        \* Format the `phase` variable as Json value.
        \* ,_phaseJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(phase)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_phaseModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].phase # _TETrace[s-1].phase
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
\*trace == IODeserialize("MC_TTrace_1788549234.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE MC_TETrace ----
EXTENDS MC, TLC, MC_TEConstants

trace == 
    <<
    ([role |-> (s1 :> "LOOKING" @@ s2 :> "LOOKING" @@ s3 :> "LOOKING"),applied |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),prepared |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),globalCommitted |-> <<>>,pending |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),leaderOf |-> (s1 :> NoServer @@ s2 :> NoServer @@ s3 :> NoServer),newLeaderAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),currentEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),seen |-> {"Init"},running |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),durable |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),acceptedEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),electionRound |-> 0,syncQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),snapshotImage |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE"),snapshotPublished |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),phase |-> (s1 :> "ELECTION" @@ s2 :> "ELECTION" @@ s3 :> "ELECTION"),nextTxn |-> 1,votedFor |-> (s1 :> NoServer @@ s2 :> NoServer @@ s3 :> NoServer),committed |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recoveryVisible |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),counters |-> [rounds |-> 0, crashes |-> 0, snapshots |-> 0],acks |-> <<{}>>,durabilityEvidence |-> <<{}>>,electionVotes |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),epochAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),snapshotBusy |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),epochProposal |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitWitness |-> <<{}>>,lastTransition |-> "Init",syncComplete |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),newLeaderReady |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)]),
    ([role |-> (s1 :> "LOOKING" @@ s2 :> "LOOKING" @@ s3 :> "LOOKING"),applied |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),prepared |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),globalCommitted |-> <<>>,pending |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),leaderOf |-> (s1 :> NoServer @@ s2 :> NoServer @@ s3 :> NoServer),newLeaderAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),currentEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),seen |-> {"Init", "CastVote"},running |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),durable |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),acceptedEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),electionRound |-> 0,syncQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),snapshotImage |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE"),snapshotPublished |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),phase |-> (s1 :> "ELECTION" @@ s2 :> "ELECTION" @@ s3 :> "ELECTION"),nextTxn |-> 1,votedFor |-> (s1 :> s1 @@ s2 :> NoServer @@ s3 :> NoServer),committed |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recoveryVisible |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),counters |-> [rounds |-> 0, crashes |-> 0, snapshots |-> 0],acks |-> <<{}>>,durabilityEvidence |-> <<{}>>,electionVotes |-> (s1 :> {s1} @@ s2 :> {} @@ s3 :> {}),epochAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),snapshotBusy |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),epochProposal |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitWitness |-> <<{}>>,lastTransition |-> "CastVote",syncComplete |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),newLeaderReady |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)]),
    ([role |-> (s1 :> "LOOKING" @@ s2 :> "LOOKING" @@ s3 :> "LOOKING"),applied |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),prepared |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),globalCommitted |-> <<>>,pending |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),leaderOf |-> (s1 :> NoServer @@ s2 :> NoServer @@ s3 :> NoServer),newLeaderAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),currentEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),seen |-> {"Init", "CastVote"},running |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),durable |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),acceptedEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),electionRound |-> 0,syncQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),snapshotImage |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE"),snapshotPublished |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),phase |-> (s1 :> "ELECTION" @@ s2 :> "ELECTION" @@ s3 :> "ELECTION"),nextTxn |-> 1,votedFor |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> NoServer),committed |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recoveryVisible |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),counters |-> [rounds |-> 0, crashes |-> 0, snapshots |-> 0],acks |-> <<{}>>,durabilityEvidence |-> <<{}>>,electionVotes |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),epochAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),snapshotBusy |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),epochProposal |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitWitness |-> <<{}>>,lastTransition |-> "CastVote",syncComplete |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),newLeaderReady |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)]),
    ([role |-> (s1 :> "LEADING" @@ s2 :> "LOOKING" @@ s3 :> "LOOKING"),applied |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),prepared |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),globalCommitted |-> <<>>,pending |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> NoServer @@ s3 :> NoServer),newLeaderAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),currentEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),seen |-> {"Init", "CastVote", "FinishElection"},running |-> (s1 :> TRUE @@ s2 :> TRUE @@ s3 :> TRUE),durable |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),acceptedEpoch |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),electionRound |-> 0,syncQueued |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),snapshotImage |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE" @@ s3 :> "NONE"),snapshotPublished |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),phase |-> (s1 :> "ELECTION" @@ s2 :> "ELECTION" @@ s3 :> "ELECTION"),nextTxn |-> 1,votedFor |-> (s1 :> s1 @@ s2 :> s1 @@ s3 :> NoServer),committed |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),recoveryVisible |-> (s1 :> <<>> @@ s2 :> <<>> @@ s3 :> <<>>),counters |-> [rounds |-> 0, crashes |-> 0, snapshots |-> 0],acks |-> <<{}>>,durabilityEvidence |-> <<{}>>,electionVotes |-> (s1 :> {s1, s2} @@ s2 :> {} @@ s3 :> {}),epochAcks |-> (s1 :> {} @@ s2 :> {} @@ s3 :> {}),snapshotBusy |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),epochProposal |-> (s1 :> 0 @@ s2 :> 0 @@ s3 :> 0),commitWitness |-> <<{}>>,lastTransition |-> "FinishElection",syncComplete |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE),newLeaderReady |-> (s1 :> FALSE @@ s2 :> FALSE @@ s3 :> FALSE)])
    >>
----


=============================================================================

---- MODULE MC_TEConstants ----
EXTENDS MC

CONSTANTS s1, s2, s3

=============================================================================

---- CONFIG MC_TTrace_1788549234 ----
CONSTANTS
    Server = { s1 , s2 , s3 }
    MaxEpoch = 2
    MaxTxn = 1
    NoServer = NoServer
    s1 = s1
    s2 = s2
    NoServer = NoServer
    s3 = s3

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
\* Generated on Fri Sep 04 19:13:54 UTC 2026