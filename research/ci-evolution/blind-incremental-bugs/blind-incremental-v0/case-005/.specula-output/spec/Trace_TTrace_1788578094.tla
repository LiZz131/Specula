---- MODULE Trace_TTrace_1788578094 ----
EXTENDS Trace, Sequences, TLCExt, Toolbox, Naturals, TLC

_expression ==
    LET Trace_TEExpression == INSTANCE Trace_TEExpression
    IN Trace_TEExpression!expression
----

_trace ==
    LET Trace_TETrace == INSTANCE Trace_TETrace
    IN Trace_TETrace!trace
----

_inv ==
    ~(
        TLCGet("level") = Len(_TETrace)
        /\
        snapshotZxid = ([s0 |-> 0, s1 |-> 0, s2 |-> 0])
        /\
        role = ([s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"])
        /\
        globalCommitted = ({})
        /\
        queuedLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        committedLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        leaderOf = ([s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"])
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
        appliedLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        lastAction = ("ReceiveEpochSupport")
        /\
        acceptedEpoch = ([s0 |-> 0, s1 |-> 0, s2 |-> 1])
        /\
        ackers = ((101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}))
        /\
        syncMode = ([s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"])
        /\
        broadcastReady = ({})
        /\
        volatileLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        up = ([s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE])
        /\
        epochSupport = ([s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s1", "s2"}])
        /\
        durableCurrent = ([s0 |-> 0, s1 |-> 0, s2 |-> 0])
        /\
        epochAcks = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
        /\
        l = (12)
        /\
        upToDate = ({})
        /\
        supportAtAccepted = ([s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}])
        /\
        proposedBy = ((101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"))
        /\
        durableLog = ([s0 |-> {}, s1 |-> {}, s2 |-> {}])
    )
----

_init ==
    /\ broadcastReady = _TETrace[1].broadcastReady
    /\ epochAcks = _TETrace[1].epochAcks
    /\ globalCommitted = _TETrace[1].globalCommitted
    /\ durableLog = _TETrace[1].durableLog
    /\ syncTarget = _TETrace[1].syncTarget
    /\ newLeaderAcks = _TETrace[1].newLeaderAcks
    /\ l = _TETrace[1].l
    /\ upToDate = _TETrace[1].upToDate
    /\ appliedLog = _TETrace[1].appliedLog
    /\ proposedBy = _TETrace[1].proposedBy
    /\ currentEpoch = _TETrace[1].currentEpoch
    /\ lastAction = _TETrace[1].lastAction
    /\ durableAccepted = _TETrace[1].durableAccepted
    /\ volatileLog = _TETrace[1].volatileLog
    /\ supportAtAccepted = _TETrace[1].supportAtAccepted
    /\ acceptedEpoch = _TETrace[1].acceptedEpoch
    /\ ackers = _TETrace[1].ackers
    /\ committedLog = _TETrace[1].committedLog
    /\ snapshotLog = _TETrace[1].snapshotLog
    /\ up = _TETrace[1].up
    /\ durableCurrent = _TETrace[1].durableCurrent
    /\ leaderOf = _TETrace[1].leaderOf
    /\ epochSupport = _TETrace[1].epochSupport
    /\ role = _TETrace[1].role
    /\ syncMode = _TETrace[1].syncMode
    /\ queuedLog = _TETrace[1].queuedLog
    /\ snapshotZxid = _TETrace[1].snapshotZxid
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ broadcastReady  = _TETrace[i].broadcastReady
        /\ broadcastReady' = _TETrace[j].broadcastReady
        /\ epochAcks  = _TETrace[i].epochAcks
        /\ epochAcks' = _TETrace[j].epochAcks
        /\ globalCommitted  = _TETrace[i].globalCommitted
        /\ globalCommitted' = _TETrace[j].globalCommitted
        /\ durableLog  = _TETrace[i].durableLog
        /\ durableLog' = _TETrace[j].durableLog
        /\ syncTarget  = _TETrace[i].syncTarget
        /\ syncTarget' = _TETrace[j].syncTarget
        /\ newLeaderAcks  = _TETrace[i].newLeaderAcks
        /\ newLeaderAcks' = _TETrace[j].newLeaderAcks
        /\ l  = _TETrace[i].l
        /\ l' = _TETrace[j].l
        /\ upToDate  = _TETrace[i].upToDate
        /\ upToDate' = _TETrace[j].upToDate
        /\ appliedLog  = _TETrace[i].appliedLog
        /\ appliedLog' = _TETrace[j].appliedLog
        /\ proposedBy  = _TETrace[i].proposedBy
        /\ proposedBy' = _TETrace[j].proposedBy
        /\ currentEpoch  = _TETrace[i].currentEpoch
        /\ currentEpoch' = _TETrace[j].currentEpoch
        /\ lastAction  = _TETrace[i].lastAction
        /\ lastAction' = _TETrace[j].lastAction
        /\ durableAccepted  = _TETrace[i].durableAccepted
        /\ durableAccepted' = _TETrace[j].durableAccepted
        /\ volatileLog  = _TETrace[i].volatileLog
        /\ volatileLog' = _TETrace[j].volatileLog
        /\ supportAtAccepted  = _TETrace[i].supportAtAccepted
        /\ supportAtAccepted' = _TETrace[j].supportAtAccepted
        /\ acceptedEpoch  = _TETrace[i].acceptedEpoch
        /\ acceptedEpoch' = _TETrace[j].acceptedEpoch
        /\ ackers  = _TETrace[i].ackers
        /\ ackers' = _TETrace[j].ackers
        /\ committedLog  = _TETrace[i].committedLog
        /\ committedLog' = _TETrace[j].committedLog
        /\ snapshotLog  = _TETrace[i].snapshotLog
        /\ snapshotLog' = _TETrace[j].snapshotLog
        /\ up  = _TETrace[i].up
        /\ up' = _TETrace[j].up
        /\ durableCurrent  = _TETrace[i].durableCurrent
        /\ durableCurrent' = _TETrace[j].durableCurrent
        /\ leaderOf  = _TETrace[i].leaderOf
        /\ leaderOf' = _TETrace[j].leaderOf
        /\ epochSupport  = _TETrace[i].epochSupport
        /\ epochSupport' = _TETrace[j].epochSupport
        /\ role  = _TETrace[i].role
        /\ role' = _TETrace[j].role
        /\ syncMode  = _TETrace[i].syncMode
        /\ syncMode' = _TETrace[j].syncMode
        /\ queuedLog  = _TETrace[i].queuedLog
        /\ queuedLog' = _TETrace[j].queuedLog
        /\ snapshotZxid  = _TETrace[i].snapshotZxid
        /\ snapshotZxid' = _TETrace[j].snapshotZxid

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("Trace_TTrace_1788578094.json", _TETrace)

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
        broadcastReady |-> broadcastReady
        ,epochAcks |-> epochAcks
        ,globalCommitted |-> globalCommitted
        ,durableLog |-> durableLog
        ,syncTarget |-> syncTarget
        ,newLeaderAcks |-> newLeaderAcks
        ,l |-> l
        ,upToDate |-> upToDate
        ,appliedLog |-> appliedLog
        ,proposedBy |-> proposedBy
        ,currentEpoch |-> currentEpoch
        ,lastAction |-> lastAction
        ,durableAccepted |-> durableAccepted
        ,volatileLog |-> volatileLog
        ,supportAtAccepted |-> supportAtAccepted
        ,acceptedEpoch |-> acceptedEpoch
        ,ackers |-> ackers
        ,committedLog |-> committedLog
        ,snapshotLog |-> snapshotLog
        ,up |-> up
        ,durableCurrent |-> durableCurrent
        ,leaderOf |-> leaderOf
        ,epochSupport |-> epochSupport
        ,role |-> role
        ,syncMode |-> syncMode
        ,queuedLog |-> queuedLog
        ,snapshotZxid |-> snapshotZxid
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_broadcastReadyUnchanged |-> broadcastReady = broadcastReady'
        
        \* Format the `broadcastReady` variable as Json value.
        \* ,_broadcastReadyJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(broadcastReady)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_broadcastReadyModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].broadcastReady # _TETrace[s-1].broadcastReady
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
\*trace == IODeserialize("Trace_TTrace_1788578094.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE Trace_TETrace ----
EXTENDS Trace, TLC

trace == 
    <<
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "DOWN", s1 |-> "DOWN", s2 |-> "DOWN"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "Init",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 1,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "DOWN", s1 |-> "DOWN", s2 |-> "LOOKING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "StartServer",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> FALSE, s1 |-> FALSE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 2,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "DOWN", s1 |-> "LOOKING", s2 |-> "LOOKING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "StartServer",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> FALSE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 3,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "LOOKING", s1 |-> "LOOKING", s2 |-> "LOOKING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "none", s1 |-> "none", s2 |-> "none"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "StartServer",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 4,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "LOOKING", s2 |-> "LOOKING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "none", s2 |-> "none"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ElectionDecision",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 5,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LOOKING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "none"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ElectionDecision",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 6,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ElectionDecision",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 7,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ReceiveEpochSupport",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 8,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ReceiveEpochSupport",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 9,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "LeaderAcceptedEpochMemory",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 10,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "PersistAcceptedEpoch",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 11,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]]),
    ([snapshotZxid |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],role |-> [s0 |-> "FOLLOWING", s1 |-> "FOLLOWING", s2 |-> "LEADING"],globalCommitted |-> {},queuedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],committedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],leaderOf |-> [s0 |-> "s2", s1 |-> "s2", s2 |-> "s2"],newLeaderAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],currentEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],durableAccepted |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],syncTarget |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],snapshotLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],appliedLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],lastAction |-> "ReceiveEpochSupport",acceptedEpoch |-> [s0 |-> 0, s1 |-> 0, s2 |-> 1],ackers |-> (101 :> {} @@ 102 :> {} @@ 103 :> {} @@ 104 :> {} @@ 105 :> {} @@ 106 :> {} @@ 107 :> {} @@ 201 :> {} @@ 202 :> {} @@ 203 :> {}),syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],broadcastReady |-> {},volatileLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],epochSupport |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s0", "s1", "s2"}],durableCurrent |-> [s0 |-> 0, s1 |-> 0, s2 |-> 0],epochAcks |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}],l |-> 12,upToDate |-> {},supportAtAccepted |-> [s0 |-> {}, s1 |-> {}, s2 |-> {"s1", "s2"}],proposedBy |-> (101 :> "none" @@ 102 :> "none" @@ 103 :> "none" @@ 104 :> "none" @@ 105 :> "none" @@ 106 :> "none" @@ 107 :> "none" @@ 201 :> "none" @@ 202 :> "none" @@ 203 :> "none"),durableLog |-> [s0 |-> {}, s1 |-> {}, s2 |-> {}]])
    >>
----


=============================================================================

---- CONFIG Trace_TTrace_1788578094 ----
CONSTANTS
    Server = { "s0" , "s1" , "s2" }
    Voters = { "s0" , "s1" , "s2" }
    Observers = { }
    Txn <- TraceTxn
    MaxEpoch = 2
    NoNode = "none"
    NoTxn = 0

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
\* Generated on Sat Sep 05 03:14:58 UTC 2026