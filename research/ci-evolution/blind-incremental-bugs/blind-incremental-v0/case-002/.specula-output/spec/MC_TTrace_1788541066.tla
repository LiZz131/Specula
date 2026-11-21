---- MODULE MC_TTrace_1788541066 ----
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
        syncJustified = ((s1 :> FALSE @@ s2 :> TRUE))
        /\
        syncSource = ((s1 :> Nil @@ s2 :> s1))
        /\
        role = ((s1 :> "leading" @@ s2 :> "following"))
        /\
        applied = ((s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>))
        /\
        commitCertified = ((t1 :> TRUE))
        /\
        queued = ((s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>))
        /\
        leaderOf = ((s1 :> s1 @@ s2 :> s1))
        /\
        currentEpoch = ((s1 :> 1 @@ s2 :> 1))
        /\
        seen = ({"durable", "election", "sync", "broadcast", "DIFF", "commit", "leader", "mutation", "apply"})
        /\
        leadersByEpoch = ((0 :> {} @@ 1 :> {s1}))
        /\
        durable = ((s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>))
        /\
        appended = ((s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>))
        /\
        acceptedEpoch = ((s1 :> 1 @@ s2 :> 1))
        /\
        syncMode = ((s1 :> "NONE" @@ s2 :> "DIFF"))
        /\
        usedTxn = ({t1})
        /\
        up = ((s1 :> TRUE @@ s2 :> TRUE))
        /\
        phase = ((s1 :> "broadcast" @@ s2 :> "broadcast"))
        /\
        committed = ((s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>))
        /\
        counters = ([crash |-> 0, drop |-> 0, snapshot |-> 0])
        /\
        acked = ((t1 :> {s1, s2}))
        /\
        rollbackAuthorized = ((s1 :> FALSE @@ s2 :> FALSE))
        /\
        recovered = ((s1 :> <<>> @@ s2 :> <<>>))
        /\
        proposed = ((s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>))
        /\
        messages = ({[id |-> t1, epoch |-> 1, kind |-> "commit", from |-> s1, to |-> s2]})
        /\
        votes = ((s1 :> {s1, s2} @@ s2 :> {}))
        /\
        snapshot = ((s1 :> <<>> @@ s2 :> <<>>))
    )
----

_init ==
    /\ rollbackAuthorized = _TETrace[1].rollbackAuthorized
    /\ recovered = _TETrace[1].recovered
    /\ votes = _TETrace[1].votes
    /\ leadersByEpoch = _TETrace[1].leadersByEpoch
    /\ syncMode = _TETrace[1].syncMode
    /\ commitCertified = _TETrace[1].commitCertified
    /\ syncSource = _TETrace[1].syncSource
    /\ applied = _TETrace[1].applied
    /\ durable = _TETrace[1].durable
    /\ acked = _TETrace[1].acked
    /\ usedTxn = _TETrace[1].usedTxn
    /\ appended = _TETrace[1].appended
    /\ acceptedEpoch = _TETrace[1].acceptedEpoch
    /\ role = _TETrace[1].role
    /\ seen = _TETrace[1].seen
    /\ syncJustified = _TETrace[1].syncJustified
    /\ phase = _TETrace[1].phase
    /\ snapshot = _TETrace[1].snapshot
    /\ currentEpoch = _TETrace[1].currentEpoch
    /\ queued = _TETrace[1].queued
    /\ proposed = _TETrace[1].proposed
    /\ committed = _TETrace[1].committed
    /\ counters = _TETrace[1].counters
    /\ up = _TETrace[1].up
    /\ messages = _TETrace[1].messages
    /\ leaderOf = _TETrace[1].leaderOf
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ rollbackAuthorized  = _TETrace[i].rollbackAuthorized
        /\ rollbackAuthorized' = _TETrace[j].rollbackAuthorized
        /\ recovered  = _TETrace[i].recovered
        /\ recovered' = _TETrace[j].recovered
        /\ votes  = _TETrace[i].votes
        /\ votes' = _TETrace[j].votes
        /\ leadersByEpoch  = _TETrace[i].leadersByEpoch
        /\ leadersByEpoch' = _TETrace[j].leadersByEpoch
        /\ syncMode  = _TETrace[i].syncMode
        /\ syncMode' = _TETrace[j].syncMode
        /\ commitCertified  = _TETrace[i].commitCertified
        /\ commitCertified' = _TETrace[j].commitCertified
        /\ syncSource  = _TETrace[i].syncSource
        /\ syncSource' = _TETrace[j].syncSource
        /\ applied  = _TETrace[i].applied
        /\ applied' = _TETrace[j].applied
        /\ durable  = _TETrace[i].durable
        /\ durable' = _TETrace[j].durable
        /\ acked  = _TETrace[i].acked
        /\ acked' = _TETrace[j].acked
        /\ usedTxn  = _TETrace[i].usedTxn
        /\ usedTxn' = _TETrace[j].usedTxn
        /\ appended  = _TETrace[i].appended
        /\ appended' = _TETrace[j].appended
        /\ acceptedEpoch  = _TETrace[i].acceptedEpoch
        /\ acceptedEpoch' = _TETrace[j].acceptedEpoch
        /\ role  = _TETrace[i].role
        /\ role' = _TETrace[j].role
        /\ seen  = _TETrace[i].seen
        /\ seen' = _TETrace[j].seen
        /\ syncJustified  = _TETrace[i].syncJustified
        /\ syncJustified' = _TETrace[j].syncJustified
        /\ phase  = _TETrace[i].phase
        /\ phase' = _TETrace[j].phase
        /\ snapshot  = _TETrace[i].snapshot
        /\ snapshot' = _TETrace[j].snapshot
        /\ currentEpoch  = _TETrace[i].currentEpoch
        /\ currentEpoch' = _TETrace[j].currentEpoch
        /\ queued  = _TETrace[i].queued
        /\ queued' = _TETrace[j].queued
        /\ proposed  = _TETrace[i].proposed
        /\ proposed' = _TETrace[j].proposed
        /\ committed  = _TETrace[i].committed
        /\ committed' = _TETrace[j].committed
        /\ counters  = _TETrace[i].counters
        /\ counters' = _TETrace[j].counters
        /\ up  = _TETrace[i].up
        /\ up' = _TETrace[j].up
        /\ messages  = _TETrace[i].messages
        /\ messages' = _TETrace[j].messages
        /\ leaderOf  = _TETrace[i].leaderOf
        /\ leaderOf' = _TETrace[j].leaderOf

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("MC_TTrace_1788541066.json", _TETrace)

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
        rollbackAuthorized |-> rollbackAuthorized
        ,recovered |-> recovered
        ,votes |-> votes
        ,leadersByEpoch |-> leadersByEpoch
        ,syncMode |-> syncMode
        ,commitCertified |-> commitCertified
        ,syncSource |-> syncSource
        ,applied |-> applied
        ,durable |-> durable
        ,acked |-> acked
        ,usedTxn |-> usedTxn
        ,appended |-> appended
        ,acceptedEpoch |-> acceptedEpoch
        ,role |-> role
        ,seen |-> seen
        ,syncJustified |-> syncJustified
        ,phase |-> phase
        ,snapshot |-> snapshot
        ,currentEpoch |-> currentEpoch
        ,queued |-> queued
        ,proposed |-> proposed
        ,committed |-> committed
        ,counters |-> counters
        ,up |-> up
        ,messages |-> messages
        ,leaderOf |-> leaderOf
        
        \* Put additional constant-, state-, and action-level expressions here:
        \* ,_stateNumber |-> _TEPosition
        \* ,_rollbackAuthorizedUnchanged |-> rollbackAuthorized = rollbackAuthorized'
        
        \* Format the `rollbackAuthorized` variable as Json value.
        \* ,_rollbackAuthorizedJson |->
        \*     LET J == INSTANCE Json
        \*     IN J!ToJson(rollbackAuthorized)
        
        \* Lastly, you may build expressions over arbitrary sets of states by
        \* leveraging the _TETrace operator.  For example, this is how to
        \* count the number of times a spec variable changed up to the current
        \* state in the trace.
        \* ,_rollbackAuthorizedModCount |->
        \*     LET F[s \in DOMAIN _TETrace] ==
        \*         IF s = 1 THEN 0
        \*         ELSE IF _TETrace[s].rollbackAuthorized # _TETrace[s-1].rollbackAuthorized
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
\*trace == IODeserialize("MC_TTrace_1788541066.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE MC_TETrace ----
EXTENDS MC, TLC, MC_TEConstants

trace == 
    <<
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> Nil),role |-> (s1 :> "looking" @@ s2 :> "looking"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> Nil @@ s2 :> Nil),currentEpoch |-> (s1 :> 0 @@ s2 :> 0),seen |-> {},leadersByEpoch |-> (0 :> {} @@ 1 :> {}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 0 @@ s2 :> 0),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "election" @@ s2 :> "election"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> Nil),role |-> (s1 :> "looking" @@ s2 :> "looking"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> Nil @@ s2 :> Nil),currentEpoch |-> (s1 :> 0 @@ s2 :> 0),seen |-> {"election"},leadersByEpoch |-> (0 :> {} @@ 1 :> {}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 0 @@ s2 :> 0),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "election" @@ s2 :> "election"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> Nil),role |-> (s1 :> "looking" @@ s2 :> "looking"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> Nil @@ s2 :> Nil),currentEpoch |-> (s1 :> 0 @@ s2 :> 0),seen |-> {"election"},leadersByEpoch |-> (0 :> {} @@ 1 :> {}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 0 @@ s2 :> 0),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "election" @@ s2 :> "election"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> Nil),role |-> (s1 :> "leading" @@ s2 :> "looking"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> Nil),currentEpoch |-> (s1 :> 0 @@ s2 :> 0),seen |-> {"election", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 0),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "discovery" @@ s2 :> "election"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> Nil),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 0 @@ s2 :> 0),seen |-> {"election", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 0),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "discovery" @@ s2 :> "discovery"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> Nil),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 0 @@ s2 :> 0),seen |-> {"election", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "discovery" @@ s2 :> "discovery"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> Nil),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 0),seen |-> {"election", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "sync" @@ s2 :> "discovery"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 0),seen |-> {"election", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "NONE"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "sync" @@ s2 :> "sync"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> FALSE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 0),seen |-> {"election", "sync", "DIFF", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "sync" @@ s2 :> "sync"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 0),seen |-> {"election", "sync", "DIFF", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "sync" @@ s2 :> "sync"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> TRUE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"election", "sync", "DIFF", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "sync" @@ s2 :> "sync"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"election", "sync", "DIFF", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "sync" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"election", "sync", "broadcast", "DIFF", "leader"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<>> @@ s2 :> <<>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"election", "sync", "broadcast", "DIFF", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>),messages |-> {[id |-> t1, epoch |-> 1, kind |-> "proposal", from |-> s1, to |-> s2]},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"election", "sync", "broadcast", "DIFF", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"election", "sync", "broadcast", "DIFF", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"election", "sync", "broadcast", "DIFF", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<>> @@ s2 :> <<>>),appended |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"durable", "election", "sync", "broadcast", "DIFF", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>),appended |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {s1}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"durable", "election", "sync", "broadcast", "DIFF", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),appended |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {s1}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {[id |-> t1, epoch |-> 1, kind |-> "ack", from |-> s2, to |-> s1]},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> FALSE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"durable", "election", "sync", "broadcast", "DIFF", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),appended |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {s1, s2}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<>> @@ s2 :> <<>>),commitCertified |-> (t1 :> TRUE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"durable", "election", "sync", "broadcast", "DIFF", "commit", "leader", "mutation"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),appended |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {s1, s2}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {[id |-> t1, epoch |-> 1, kind |-> "commit", from |-> s1, to |-> s2]},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)]),
    ([syncJustified |-> (s1 :> FALSE @@ s2 :> TRUE),syncSource |-> (s1 :> Nil @@ s2 :> s1),role |-> (s1 :> "leading" @@ s2 :> "following"),applied |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>),commitCertified |-> (t1 :> TRUE),queued |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),leaderOf |-> (s1 :> s1 @@ s2 :> s1),currentEpoch |-> (s1 :> 1 @@ s2 :> 1),seen |-> {"durable", "election", "sync", "broadcast", "DIFF", "commit", "leader", "mutation", "apply"},leadersByEpoch |-> (0 :> {} @@ 1 :> {s1}),durable |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),appended |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),acceptedEpoch |-> (s1 :> 1 @@ s2 :> 1),syncMode |-> (s1 :> "NONE" @@ s2 :> "DIFF"),usedTxn |-> {t1},up |-> (s1 :> TRUE @@ s2 :> TRUE),phase |-> (s1 :> "broadcast" @@ s2 :> "broadcast"),committed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<>>),counters |-> [crash |-> 0, drop |-> 0, snapshot |-> 0],acked |-> (t1 :> {s1, s2}),rollbackAuthorized |-> (s1 :> FALSE @@ s2 :> FALSE),recovered |-> (s1 :> <<>> @@ s2 :> <<>>),proposed |-> (s1 :> <<[id |-> t1, epoch |-> 1]>> @@ s2 :> <<[id |-> t1, epoch |-> 1]>>),messages |-> {[id |-> t1, epoch |-> 1, kind |-> "commit", from |-> s1, to |-> s2]},votes |-> (s1 :> {s1, s2} @@ s2 :> {}),snapshot |-> (s1 :> <<>> @@ s2 :> <<>>)])
    >>
----


=============================================================================

---- MODULE MC_TEConstants ----
EXTENDS MC

CONSTANTS s1, s2, t1

=============================================================================

---- CONFIG MC_TTrace_1788541066 ----
CONSTANTS
    Server = { s1 , s2 }
    Txn = { t1 }
    MaxEpoch = 1
    Nil = Nil
    MaxCrash = 0
    MaxDrop = 0
    MaxSnapshot = 0
    s1 = s1
    s2 = s2
    Nil = Nil
    t1 = t1

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
\* Generated on Fri Sep 04 16:57:48 UTC 2026