---- MODULE Trace_TTrace_1788578374 ----
EXTENDS Trace, Sequences, TLCExt, Toolbox, Naturals, TLC

_expression ==
    LET Trace_TEExpression == INSTANCE Trace_TEExpression
    IN Trace_TEExpression!expression
----

_trace ==
    LET Trace_TETrace == INSTANCE Trace_TETrace
    IN Trace_TETrace!trace
----

_prop ==
    ~<>[](
        snapshotZxid = ([s0 |-> 0, s1 |-> 0, s2 |-> 0])
        /\
        role = ([s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"])
        /\
        globalCommitted = ({})
        /\
        queuedLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        leaderOf = ([s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"])
        /\
        committedLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        newLeaderAcks = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        currentEpoch = ([s0 |-> 0, s1 |-> 0, s2 |-> 0])
        /\
        durableAccepted = ([s0 |-> 0, s1 |-> 0, s2 |-> 1])
        /\
        syncTarget = ([s0 |-> 0, s1 |-> 0, s2 |-> 0])
        /\
        snapshotLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        lastAction = ("ReceiveEpochSupport")
        /\
        acceptedEpoch = ([s0 |-> 0, s1 |-> 0, s2 |-> 1])
        /\
        appliedLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        ackers = (<<{}, {}, {}, {}, {}, {}, {}>>)
        /\
        syncMode = ([s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"])
        /\
        volatileLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        up = ([s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE])
        /\
        broadcastReady = ({})
        /\
        epochSupport = ([s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s1", "s2"}])
        /\
        durableCurrent = ([s0 |-> 0, s1 |-> 0, s2 |-> 0])
        /\
        l = (12)
        /\
        epochAcks = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        upToDate = ({})
        /\
        supportAtAccepted = ([s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}])
        /\
        proposedBy = (<<"none", "none", "none", "none", "none", "none", "none">>)
        /\
        durableLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
    )
----

_init ==
    /\ durableAccepted = _TETrace[1].durableAccepted
    /\ epochSupport = _TETrace[1].epochSupport
    /\ syncMode = _TETrace[1].syncMode
    /\ globalCommitted = _TETrace[1].globalCommitted
    /\ syncTarget = _TETrace[1].syncTarget
    /\ l = _TETrace[1].l
    /\ proposedBy = _TETrace[1].proposedBy
    /\ lastAction = _TETrace[1].lastAction
    /\ durableLog = _TETrace[1].durableLog
    /\ acceptedEpoch = _TETrace[1].acceptedEpoch
    /\ role = _TETrace[1].role
    /\ snapshotZxid = _TETrace[1].snapshotZxid
    /\ currentEpoch = _TETrace[1].currentEpoch
    /\ upToDate = _TETrace[1].upToDate
    /\ ackers = _TETrace[1].ackers
    /\ epochAcks = _TETrace[1].epochAcks
    /\ newLeaderAcks = _TETrace[1].newLeaderAcks
    /\ snapshotLog = _TETrace[1].snapshotLog
    /\ queuedLog = _TETrace[1].queuedLog
    /\ durableCurrent = _TETrace[1].durableCurrent
    /\ volatileLog = _TETrace[1].volatileLog
    /\ up = _TETrace[1].up
    /\ appliedLog = _TETrace[1].appliedLog
    /\ leaderOf = _TETrace[1].leaderOf
    /\ broadcastReady = _TETrace[1].broadcastReady
    /\ committedLog = _TETrace[1].committedLog
    /\ supportAtAccepted = _TETrace[1].supportAtAccepted
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ durableAccepted  = _TETrace[i].durableAccepted
        /\ durableAccepted' = _TETrace[j].durableAccepted
        /\ epochSupport  = _TETrace[i].epochSupport
        /\ epochSupport' = _TETrace[j].epochSupport
        /\ syncMode  = _TETrace[i].syncMode
        /\ syncMode' = _TETrace[j].syncMode
        /\ globalCommitted  = _TETrace[i].globalCommitted
        /\ globalCommitted' = _TETrace[j].globalCommitted
        /\ syncTarget  = _TETrace[i].syncTarget
        /\ syncTarget' = _TETrace[j].syncTarget
        /\ l  = _TETrace[i].l
        /\ l' = _TETrace[j].l
        /\ proposedBy  = _TETrace[i].proposedBy
        /\ proposedBy' = _TETrace[j].proposedBy
        /\ lastAction  = _TETrace[i].lastAction
        /\ lastAction' = _TETrace[j].lastAction
        /\ durableLog  = _TETrace[i].durableLog
        /\ durableLog' = _TETrace[j].durableLog
        /\ acceptedEpoch  = _TETrace[i].acceptedEpoch
        /\ acceptedEpoch' = _TETrace[j].acceptedEpoch
        /\ role  = _TETrace[i].role
        /\ role' = _TETrace[j].role
        /\ snapshotZxid  = _TETrace[i].snapshotZxid
        /\ snapshotZxid' = _TETrace[j].snapshotZxid
        /\ currentEpoch  = _TETrace[i].currentEpoch
        /\ currentEpoch' = _TETrace[j].currentEpoch
        /\ upToDate  = _TETrace[i].upToDate
        /\ upToDate' = _TETrace[j].upToDate
        /\ ackers  = _TETrace[i].ackers
        /\ ackers' = _TETrace[j].ackers
        /\ epochAcks  = _TETrace[i].epochAcks
        /\ epochAcks' = _TETrace[j].epochAcks
        /\ newLeaderAcks  = _TETrace[i].newLeaderAcks
        /\ newLeaderAcks' = _TETrace[j].newLeaderAcks
        /\ snapshotLog  = _TETrace[i].snapshotLog
        /\ snapshotLog' = _TETrace[j].snapshotLog
        /\ queuedLog  = _TETrace[i].queuedLog
        /\ queuedLog' = _TETrace[j].queuedLog
        /\ durableCurrent  = _TETrace[i].durableCurrent
        /\ durableCurrent' = _TETrace[j].durableCurrent
        /\ volatileLog  = _TETrace[i].volatileLog
        /\ volatileLog' = _TETrace[j].volatileLog
        /\ up  = _TETrace[i].up
        /\ up' = _TETrace[j].up
        /\ appliedLog  = _TETrace[i].appliedLog
        /\ appliedLog' = _TETrace[j].appliedLog
        /\ leaderOf  = _TETrace[i].leaderOf
        /\ leaderOf' = _TETrace[j].leaderOf
        /\ broadcastReady  = _TETrace[i].broadcastReady
        /\ broadcastReady' = _TETrace[j].broadcastReady
        /\ committedLog  = _TETrace[i].committedLog
        /\ committedLog' = _TETrace[j].committedLog
        /\ supportAtAccepted  = _TETrace[i].supportAtAccepted
        /\ supportAtAccepted' = _TETrace[j].supportAtAccepted

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("Trace_TTrace_1788578374.json", _TETrace)

=============================================================================

 Note that you can extract this module `Trace_TEExpression`
  to a dedicated file to reuse `expression` (the module in the 
  dedicated `Trace_TEExpression.tla` file takes precedence 
  over the module `Trace_TEExpression` below).

---- MODULE Trace_TEExpression ----
EXTENDS Trace, Sequences, TLCExt, Toolbox, Naturals, TLC

expression == 
    [
        \* To hide variables of the `Trace` spec from the error trace,
        \* remove the variables below.  The trace will be written in the order
        \* of the fields of this record.
        durableAccepted |-> durableAccepted
        ,epochSupport |-> epochSupport
        ,syncMode |-> syncMode
        ,globalCommitted |-> globalCommitted
        ,syncTarget |-> syncTarget
        ,l |-> l
        ,proposedBy |-> proposedBy
        ,lastAction |-> lastAction
        ,durableLog |-> durableLog
        ,acceptedEpoch |-> acceptedEpoch
        ,role |-> role
        ,snapshotZxid |-> snapshotZxid
        ,currentEpoch |-> currentEpoch
        ,upToDate |-> upToDate
        ,ackers |-> ackers
        ,epochAcks |-> epochAcks
        ,newLeaderAcks |-> newLeaderAcks
        ,snapshotLog |-> snapshotLog
        ,queuedLog |-> queuedLog
        ,durableCurrent |-> durableCurrent
        ,volatileLog |-> volatileLog
        ,up |-> up
        ,appliedLog |-> appliedLog
        ,leaderOf |-> leaderOf
        ,broadcastReady |-> broadcastReady
        ,committedLog |-> committedLog
        ,supportAtAccepted |-> supportAtAccepted
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_durableAcceptedUnchanged |-> durableAccepted = durableAccepted'
        
        \* Format the `durableAccepted` variable as Json value.
        \* ,_durableAcceptedJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(durableAccepted)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_durableAcceptedModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].durableAccepted # _TETrace[s-1].durableAccepted
        \*             THEN 1 + F[s-1] ELSE F[s-1]
        \*     IN F[_TEPosition - 1]
    ]

=============================================================================



Parsing and semantic processing can take forever if the trace below is long.
 In this case, it is advised to uncomment the module below to deserialize the
 trace from a generated binary file.

\*
\*---- MODULE Trace_TETrace ----
\*EXTENDS Trace, IOUtils, TLC
\*
\*trace == IODeserialize("Trace_TTrace_1788578374.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE Trace_TETrace ----
EXTENDS Trace, TLC

trace == 
    <<
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "DOWN", s1 |-> "DOWN", s2 |-> "DOWN"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "Init",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 1,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "DOWN", s1 |-> "LOOKING", s2 |-> "DOWN"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "StartServer",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> FALSE, s1 |-> TRUE, s2 |-> FALSE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 2,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "LOOKING", s1 |-> "LOOKING", s2 |-> "DOWN"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "StartServer",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> FALSE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 3,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "LOOKING", s1 |-> "LOOKING", s2 |-> "LOOKING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "StartServer",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 4,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "LOOKING", s2 |-> "LOOKING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "none", s2 |-> "none"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ElectionDecision",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 5,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "LOOKING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "none", s2 |-> "s2"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ElectionDecision",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 6,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ElectionDecision",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 7,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ReceiveEpochSupport",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 8,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ReceiveEpochSupport",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 9,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "LeaderAcceptedEpochMemory",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 10,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "PersistAcceptedEpoch",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 11,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ReceiveEpochSupport",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],ackers |-> <<{}, {}, {}, {}, {}, {}, {}>>,syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],broadcastReady |-> {},epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s1", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],l |-> 12,epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s2"}],proposedBy |-> <<"none", "none", "none", "none", "none", "none", "none">>,durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]])
    >>
----


=============================================================================

---- CONFIG Trace_TTrace_1788578374 ----
CONSTANTS
    Server = { "s0" , "s1" , "s2" }
    Voters = { "s0" , "s1" , "s2" }
    Observers = { }
    Txn <- TraceTxn
    TxnEpoch <- TraceTxnEpoch
    MaxEpoch = 2
    NoNode = "none"
    NoTxn = 0

PROPERTY
    _prop

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
\* Generated on Sat Sep 05 03:19:41 UTC 2026