---- MODULE MC_TTrace_1788540738 ----
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
        phase = ("blockStored")
        /\
        coverage = ({"blockStored", "finalized", "responseSaved", "applyStarted", "acceptedUpdate", "appCommitted", "crashed", "handshakeStarted", "mockReplaySelected"})
        /\
        appHeight = (1)
        /\
        responseHeight = (1)
        /\
        counters = ([blocks |-> 1, crashes |-> 1, appRollbacks |-> 0])
        /\
        pendingParam = ("NoParam")
        /\
        lastParamChange = (1)
        /\
        replayMutatesState = (TRUE)
        /\
        blockStoreHeight = (1)
        /\
        updatePresent = (FALSE)
        /\
        validationOutcome = ("none")
        /\
        stateHeight = (0)
        /\
        stateStoreHeight = (0)
        /\
        responseParam = ("p0")
        /\
        persistedParam = ("p0")
        /\
        activeParam = ("p0")
        /\
        persistedLastParamChange = (1)
        /\
        pendingBlockHeight = (1)
    )
----

_init ==
    /\ phase = _TETrace[1].phase
    /\ responseHeight = _TETrace[1].responseHeight
    /\ coverage = _TETrace[1].coverage
    /\ updatePresent = _TETrace[1].updatePresent
    /\ persistedLastParamChange = _TETrace[1].persistedLastParamChange
    /\ validationOutcome = _TETrace[1].validationOutcome
    /\ responseParam = _TETrace[1].responseParam
    /\ pendingParam = _TETrace[1].pendingParam
    /\ counters = _TETrace[1].counters
    /\ persistedParam = _TETrace[1].persistedParam
    /\ replayMutatesState = _TETrace[1].replayMutatesState
    /\ appHeight = _TETrace[1].appHeight
    /\ activeParam = _TETrace[1].activeParam
    /\ blockStoreHeight = _TETrace[1].blockStoreHeight
    /\ stateHeight = _TETrace[1].stateHeight
    /\ lastParamChange = _TETrace[1].lastParamChange
    /\ stateStoreHeight = _TETrace[1].stateStoreHeight
    /\ pendingBlockHeight = _TETrace[1].pendingBlockHeight
----

_next ==
    /\ \E i,j \in DOMAIN _TETrace:
        /\ \/ /\ j = i + 1
              /\ i = TLCGet("level")
        /\ phase  = _TETrace[i].phase
        /\ phase' = _TETrace[j].phase
        /\ responseHeight  = _TETrace[i].responseHeight
        /\ responseHeight' = _TETrace[j].responseHeight
        /\ coverage  = _TETrace[i].coverage
        /\ coverage' = _TETrace[j].coverage
        /\ updatePresent  = _TETrace[i].updatePresent
        /\ updatePresent' = _TETrace[j].updatePresent
        /\ persistedLastParamChange  = _TETrace[i].persistedLastParamChange
        /\ persistedLastParamChange' = _TETrace[j].persistedLastParamChange
        /\ validationOutcome  = _TETrace[i].validationOutcome
        /\ validationOutcome' = _TETrace[j].validationOutcome
        /\ responseParam  = _TETrace[i].responseParam
        /\ responseParam' = _TETrace[j].responseParam
        /\ pendingParam  = _TETrace[i].pendingParam
        /\ pendingParam' = _TETrace[j].pendingParam
        /\ counters  = _TETrace[i].counters
        /\ counters' = _TETrace[j].counters
        /\ persistedParam  = _TETrace[i].persistedParam
        /\ persistedParam' = _TETrace[j].persistedParam
        /\ replayMutatesState  = _TETrace[i].replayMutatesState
        /\ replayMutatesState' = _TETrace[j].replayMutatesState
        /\ appHeight  = _TETrace[i].appHeight
        /\ appHeight' = _TETrace[j].appHeight
        /\ activeParam  = _TETrace[i].activeParam
        /\ activeParam' = _TETrace[j].activeParam
        /\ blockStoreHeight  = _TETrace[i].blockStoreHeight
        /\ blockStoreHeight' = _TETrace[j].blockStoreHeight
        /\ stateHeight  = _TETrace[i].stateHeight
        /\ stateHeight' = _TETrace[j].stateHeight
        /\ lastParamChange  = _TETrace[i].lastParamChange
        /\ lastParamChange' = _TETrace[j].lastParamChange
        /\ stateStoreHeight  = _TETrace[i].stateStoreHeight
        /\ stateStoreHeight' = _TETrace[j].stateStoreHeight
        /\ pendingBlockHeight  = _TETrace[i].pendingBlockHeight
        /\ pendingBlockHeight' = _TETrace[j].pendingBlockHeight

\* Uncomment the ASSUME below to write the states of the error trace
\* to the given file in Json format. Note that you can pass any tuple
\* to `JsonSerialize`. For example, a sub-sequence of _TETrace.
    \* ASSUME
    \*     LET J == INSTANCE Json
    \*         IN J!JsonSerialize("MC_TTrace_1788540738.json", _TETrace)

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
        phase |-> phase
        ,responseHeight |-> responseHeight
        ,coverage |-> coverage
        ,updatePresent |-> updatePresent
        ,persistedLastParamChange |-> persistedLastParamChange
        ,validationOutcome |-> validationOutcome
        ,responseParam |-> responseParam
        ,pendingParam |-> pendingParam
        ,counters |-> counters
        ,persistedParam |-> persistedParam
        ,replayMutatesState |-> replayMutatesState
        ,appHeight |-> appHeight
        ,activeParam |-> activeParam
        ,blockStoreHeight |-> blockStoreHeight
        ,stateHeight |-> stateHeight
        ,lastParamChange |-> lastParamChange
        ,stateStoreHeight |-> stateStoreHeight
        ,pendingBlockHeight |-> pendingBlockHeight
        
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
\*EXTENDS IOUtils, MC, TLC
\*
\*trace == IODeserialize("MC_TTrace_1788540738.bin", TRUE)
\*
\*=============================================================================
\*

---- MODULE MC_TETrace ----
EXTENDS MC, TLC

trace == 
    <<
    ([phase |-> "normal",coverage |-> {},appHeight |-> 0,responseHeight |-> 0,counters |-> [blocks |-> 0, crashes |-> 0, appRollbacks |-> 0],pendingParam |-> "NoParam",lastParamChange |-> 1,replayMutatesState |-> FALSE,blockStoreHeight |-> 0,updatePresent |-> FALSE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "NoParam",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 0]),
    ([phase |-> "blockStored",coverage |-> {"blockStored"},appHeight |-> 0,responseHeight |-> 0,counters |-> [blocks |-> 1, crashes |-> 0, appRollbacks |-> 0],pendingParam |-> "NoParam",lastParamChange |-> 1,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> FALSE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "NoParam",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 1]),
    ([phase |-> "applying",coverage |-> {"blockStored", "applyStarted"},appHeight |-> 0,responseHeight |-> 0,counters |-> [blocks |-> 1, crashes |-> 0, appRollbacks |-> 0],pendingParam |-> "NoParam",lastParamChange |-> 1,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> FALSE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "NoParam",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 1]),
    ([phase |-> "finalized",coverage |-> {"blockStored", "finalized", "applyStarted"},appHeight |-> 0,responseHeight |-> 0,counters |-> [blocks |-> 1, crashes |-> 0, appRollbacks |-> 0],pendingParam |-> "p0",lastParamChange |-> 1,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> TRUE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "NoParam",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 1]),
    ([phase |-> "responseSaved",coverage |-> {"blockStored", "finalized", "responseSaved", "applyStarted"},appHeight |-> 0,responseHeight |-> 1,counters |-> [blocks |-> 1, crashes |-> 0, appRollbacks |-> 0],pendingParam |-> "p0",lastParamChange |-> 1,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> TRUE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "p0",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 1]),
    ([phase |-> "updated",coverage |-> {"blockStored", "finalized", "responseSaved", "applyStarted", "acceptedUpdate"},appHeight |-> 0,responseHeight |-> 1,counters |-> [blocks |-> 1, crashes |-> 0, appRollbacks |-> 0],pendingParam |-> "p0",lastParamChange |-> 2,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> TRUE,validationOutcome |-> "accepted",stateHeight |-> 1,stateStoreHeight |-> 0,responseParam |-> "p0",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 1]),
    ([phase |-> "committed",coverage |-> {"blockStored", "finalized", "responseSaved", "applyStarted", "acceptedUpdate", "appCommitted"},appHeight |-> 1,responseHeight |-> 1,counters |-> [blocks |-> 1, crashes |-> 0, appRollbacks |-> 0],pendingParam |-> "p0",lastParamChange |-> 2,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> TRUE,validationOutcome |-> "accepted",stateHeight |-> 1,stateStoreHeight |-> 0,responseParam |-> "p0",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 1]),
    ([phase |-> "down",coverage |-> {"blockStored", "finalized", "responseSaved", "applyStarted", "acceptedUpdate", "appCommitted", "crashed"},appHeight |-> 1,responseHeight |-> 1,counters |-> [blocks |-> 1, crashes |-> 1, appRollbacks |-> 0],pendingParam |-> "NoParam",lastParamChange |-> 1,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> FALSE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "p0",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 0]),
    ([phase |-> "handshake",coverage |-> {"blockStored", "finalized", "responseSaved", "applyStarted", "acceptedUpdate", "appCommitted", "crashed", "handshakeStarted"},appHeight |-> 1,responseHeight |-> 1,counters |-> [blocks |-> 1, crashes |-> 1, appRollbacks |-> 0],pendingParam |-> "NoParam",lastParamChange |-> 1,replayMutatesState |-> FALSE,blockStoreHeight |-> 1,updatePresent |-> FALSE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "p0",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 0]),
    ([phase |-> "blockStored",coverage |-> {"blockStored", "finalized", "responseSaved", "applyStarted", "acceptedUpdate", "appCommitted", "crashed", "handshakeStarted", "mockReplaySelected"},appHeight |-> 1,responseHeight |-> 1,counters |-> [blocks |-> 1, crashes |-> 1, appRollbacks |-> 0],pendingParam |-> "NoParam",lastParamChange |-> 1,replayMutatesState |-> TRUE,blockStoreHeight |-> 1,updatePresent |-> FALSE,validationOutcome |-> "none",stateHeight |-> 0,stateStoreHeight |-> 0,responseParam |-> "p0",persistedParam |-> "p0",activeParam |-> "p0",persistedLastParamChange |-> 1,pendingBlockHeight |-> 1])
    >>
----


=============================================================================

---- CONFIG MC_TTrace_1788540738 ----
CONSTANTS
    MaxHeight = 1
    MaxBlocks = 1
    MaxCrashes = 1
    MaxAppRollbacks = 0
    Params = { "p0" , "p1" }
    ValidParams = { "p0" , "p1" }
    InitialParam = "p0"
    NoParam = "NoParam"

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
\* Generated on Fri Sep 04 16:52:18 UTC 2026