---- MODULE Trace_TTrace_1788590856 ----
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
        syncJustified = ([s0 |-> FALSE, s1 |-> TRUE, s2 |-> TRUE])
        /\
        syncSource = ([s0 |-> "s1", s1 |-> "Nil", s2 |-> "Nil"])
        /\
        role = ([s0 |-> "following", s1 |-> "leading", s2 |-> "following"])
        /\
        applied = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
        /\
        commitCertified = ((0 :> FALSE @@ 1 :> TRUE @@ 2 :> FALSE @@ 3 :> FALSE @@ 4 :> FALSE @@ 5 :> FALSE @@ 6 :> FALSE @@ 7 :> FALSE @@ 1000 :> FALSE))
        /\
        queued = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
        /\
        leaderOf = ([s0 |-> "s1", s1 |-> "s1", s2 |-> "s1"])
        /\
        currentEpoch = ([s0 |-> 0, s1 |-> 1, s2 |-> 1])
        /\
        leadersByEpoch = ((0 :> {} @@ 1 :> {"s1"} @@ 2 :> {} @@ 3 :> {}))
        /\
        durable = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
        /\
        appended = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
        /\
        acceptedEpoch = ([s0 |-> 0, s1 |-> 1, s2 |-> 1])
        /\
        syncMode = ([s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"])
        /\
        usedTxn = ({1})
        /\
        up = ([s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE])
        /\
        phase = ([s0 |-> "discovery", s1 |-> "sync", s2 |-> "broadcast"])
        /\
        committed = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
        /\
        l = (2)
        /\
        acked = ((0 :> {} @@ 1 :> {"s0", "s1", "s2"} @@ 2 :> {} @@ 3 :> {} @@ 4 :> {} @@ 5 :> {} @@ 6 :> {} @@ 7 :> {} @@ 1000 :> {}))
        /\
        rollbackAuthorized = ([s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE])
        /\
        recovered = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
        /\
        proposed = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
        /\
        messages = ({})
        /\
        votes = ([s0 |-> {}, s1 |-> {"s0", "s1", "s2"}, s2 |-> {}])
        /\
        snapshot = ([s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>])
    )
----

_init ==
    /\ phase = _TETrace[1].phase
    /\ leadersByEpoch = _TETrace[1].leadersByEpoch
    /\ durable = _TETrace[1].durable
    /\ syncSource = _TETrace[1].syncSource
    /\ messages = _TETrace[1].messages
    /\ l = _TETrace[1].l
    /\ currentEpoch = _TETrace[1].currentEpoch
    /\ applied = _TETrace[1].applied
    /\ appended = _TETrace[1].appended
    /\ syncJustified = _TETrace[1].syncJustified
    /\ usedTxn = _TETrace[1].usedTxn
    /\ acceptedEpoch = _TETrace[1].acceptedEpoch
    /\ committed = _TETrace[1].committed
    /\ commitCertified = _TETrace[1].commitCertified
    /\ votes = _TETrace[1].votes
    /\ up = _TETrace[1].up
    /\ leaderOf = _TETrace[1].leaderOf
    /\ proposed = _TETrace[1].proposed
    /\ acked = _TETrace[1].acked
    /\ snapshot = _TETrace[1].snapshot
    /\ role = _TETrace[1].role
    /\ rollbackAuthorized = _TETrace[1].rollbackAuthorized
    /\ syncMode = _TETrace[1].syncMode
    /\ recovered = _TETrace[1].recovered
    /\ queued = _TETrace[1].queued
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ phase  = _TETrace[i].phase
        /\ phase' = _TETrace[j].phase
        /\ leadersByEpoch  = _TETrace[i].leadersByEpoch
        /\ leadersByEpoch' = _TETrace[j].leadersByEpoch
        /\ durable  = _TETrace[i].durable
        /\ durable' = _TETrace[j].durable
        /\ syncSource  = _TETrace[i].syncSource
        /\ syncSource' = _TETrace[j].syncSource
        /\ messages  = _TETrace[i].messages
        /\ messages' = _TETrace[j].messages
        /\ l  = _TETrace[i].l
        /\ l' = _TETrace[j].l
        /\ currentEpoch  = _TETrace[i].currentEpoch
        /\ currentEpoch' = _TETrace[j].currentEpoch
        /\ applied  = _TETrace[i].applied
        /\ applied' = _TETrace[j].applied
        /\ appended  = _TETrace[i].appended
        /\ appended' = _TETrace[j].appended
        /\ syncJustified  = _TETrace[i].syncJustified
        /\ syncJustified' = _TETrace[j].syncJustified
        /\ usedTxn  = _TETrace[i].usedTxn
        /\ usedTxn' = _TETrace[j].usedTxn
        /\ acceptedEpoch  = _TETrace[i].acceptedEpoch
        /\ acceptedEpoch' = _TETrace[j].acceptedEpoch
        /\ committed  = _TETrace[i].committed
        /\ committed' = _TETrace[j].committed
        /\ commitCertified  = _TETrace[i].commitCertified
        /\ commitCertified' = _TETrace[j].commitCertified
        /\ votes  = _TETrace[i].votes
        /\ votes' = _TETrace[j].votes
        /\ up  = _TETrace[i].up
        /\ up' = _TETrace[j].up
        /\ leaderOf  = _TETrace[i].leaderOf
        /\ leaderOf' = _TETrace[j].leaderOf
        /\ proposed  = _TETrace[i].proposed
        /\ proposed' = _TETrace[j].proposed
        /\ acked  = _TETrace[i].acked
        /\ acked' = _TETrace[j].acked
        /\ snapshot  = _TETrace[i].snapshot
        /\ snapshot' = _TETrace[j].snapshot
        /\ role  = _TETrace[i].role
        /\ role' = _TETrace[j].role
        /\ rollbackAuthorized  = _TETrace[i].rollbackAuthorized
        /\ rollbackAuthorized' = _TETrace[j].rollbackAuthorized
        /\ syncMode  = _TETrace[i].syncMode
        /\ syncMode' = _TETrace[j].syncMode
        /\ recovered  = _TETrace[i].recovered
        /\ recovered' = _TETrace[j].recovered
        /\ queued  = _TETrace[i].queued
        /\ queued' = _TETrace[j].queued

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("Trace_TTrace_1788590856.json", _TETrace)

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
        phase |-> phase
        ,leadersByEpoch |-> leadersByEpoch
        ,durable |-> durable
        ,syncSource |-> syncSource
        ,messages |-> messages
        ,l |-> l
        ,currentEpoch |-> currentEpoch
        ,applied |-> applied
        ,appended |-> appended
        ,syncJustified |-> syncJustified
        ,usedTxn |-> usedTxn
        ,acceptedEpoch |-> acceptedEpoch
        ,committed |-> committed
        ,commitCertified |-> commitCertified
        ,votes |-> votes
        ,up |-> up
        ,leaderOf |-> leaderOf
        ,proposed |-> proposed
        ,acked |-> acked
        ,snapshot |-> snapshot
        ,role |-> role
        ,rollbackAuthorized |-> rollbackAuthorized
        ,syncMode |-> syncMode
        ,recovered |-> recovered
        ,queued |-> queued
        
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
\*---- MODULE Trace_TETrace ----
\*EXTENDS Trace, IOUtils, TLC
\*
\*trace == IODeserialize("Trace_TTrace_1788590856.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE Trace_TETrace ----
EXTENDS Trace, TLC

trace == 
    <<
    ([syncJustified |-> [s0 |-> FALSE, s1 |-> TRUE, s2 |-> TRUE],syncSource |-> [s0 |-> "s1", s1 |-> "Nil", s2 |-> "Nil"],role |-> [s0 |-> "following", s1 |-> "leading", s2 |-> "following"],applied |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],commitCertified |-> (0 :> FALSE @@ 1 :> TRUE @@ 2 :> FALSE @@ 3 :> FALSE @@ 4 :> FALSE @@ 5 :> FALSE @@ 6 :> FALSE @@ 7 :> FALSE @@ 1000 :> FALSE),queued |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],leaderOf |-> [s0 |-> "s1", s1 |-> "s1", s2 |-> "s1"],currentEpoch |-> [s0 |-> 0, s1 |-> 1, s2 |-> 1],leadersByEpoch |-> (0 :> {} @@ 1 :> {"s1"} @@ 2 :> {} @@ 3 :> {}),durable |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],appended |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],acceptedEpoch |-> [s0 |-> 0, s1 |-> 1, s2 |-> 1],syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],usedTxn |-> {1},up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],phase |-> [s0 |-> "discovery", s1 |-> "sync", s2 |-> "broadcast"],committed |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],l |-> 1,acked |-> (0 :> {} @@ 1 :> {"s0", "s1", "s2"} @@ 2 :> {} @@ 3 :> {} @@ 4 :> {} @@ 5 :> {} @@ 6 :> {} @@ 7 :> {} @@ 1000 :> {}),rollbackAuthorized |-> [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE],recovered |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],proposed |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],messages |-> {},votes |-> [s0 |-> {}, s1 |-> {"s0", "s1", "s2"}, s2 |-> {}],snapshot |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>]]),
    ([syncJustified |-> [s0 |-> FALSE, s1 |-> TRUE, s2 |-> TRUE],syncSource |-> [s0 |-> "s1", s1 |-> "Nil", s2 |-> "Nil"],role |-> [s0 |-> "following", s1 |-> "leading", s2 |-> "following"],applied |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],commitCertified |-> (0 :> FALSE @@ 1 :> TRUE @@ 2 :> FALSE @@ 3 :> FALSE @@ 4 :> FALSE @@ 5 :> FALSE @@ 6 :> FALSE @@ 7 :> FALSE @@ 1000 :> FALSE),queued |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],leaderOf |-> [s0 |-> "s1", s1 |-> "s1", s2 |-> "s1"],currentEpoch |-> [s0 |-> 0, s1 |-> 1, s2 |-> 1],leadersByEpoch |-> (0 :> {} @@ 1 :> {"s1"} @@ 2 :> {} @@ 3 :> {}),durable |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],appended |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],acceptedEpoch |-> [s0 |-> 0, s1 |-> 1, s2 |-> 1],syncMode |-> [s0 |-> "NONE", s1 |-> "NONE", s2 |-> "NONE"],usedTxn |-> {1},up |-> [s0 |-> TRUE, s1 |-> TRUE, s2 |-> TRUE],phase |-> [s0 |-> "discovery", s1 |-> "sync", s2 |-> "broadcast"],committed |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],l |-> 2,acked |-> (0 :> {} @@ 1 :> {"s0", "s1", "s2"} @@ 2 :> {} @@ 3 :> {} @@ 4 :> {} @@ 5 :> {} @@ 6 :> {} @@ 7 :> {} @@ 1000 :> {}),rollbackAuthorized |-> [s0 |-> FALSE, s1 |-> FALSE, s2 |-> FALSE],recovered |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],proposed |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>],messages |-> {},votes |-> [s0 |-> {}, s1 |-> {"s0", "s1", "s2"}, s2 |-> {}],snapshot |-> [s0 |-> <<>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1]>>]])
    >>
----


=============================================================================

---- CONFIG Trace_TTrace_1788590856 ----
CONSTANTS
    Server = { "s0" , "s1" , "s2" }
    Txn = { 0 , 1 , 2 , 3 , 4 , 5 , 6 , 7 , 1000 }
    MaxEpoch = 3
    Nil = "Nil"

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
\* Generated on Sat Sep 05 06:47:36 UTC 2026