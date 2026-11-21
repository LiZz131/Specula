---- MODULE E2 ----
EXTENDS Integers, TLC
VARIABLE dummy
\* source: constructed: P=0, U=2 > h=1 rejected (old-code behaviour, old 9dd6e50:types/params.go:223-228)
S == [blockStoreHeight |-> 1, appHeight |-> 0, stateStoreHeight |-> 0, stateHeight |-> 0, activeParam |-> [other |-> "o0", veh |-> 0], persistedParam |-> [other |-> "o0", veh |-> 0], lastParamChange |-> 1, persistedLastParamChange |-> 1, responseHeight |-> 1, responseParam |-> [other |-> "o0", veh |-> 2], responseAbciPresent |-> TRUE, phase |-> "rejected", replayMutatesState |-> FALSE, pendingBlockHeight |-> 1, pendingParam |-> [other |-> "o0", veh |-> 2], pendingAbciPresent |-> TRUE, validationOutcome |-> "rejected", updatePresent |-> TRUE, coverage |-> {}]
New == INSTANCE Update WITH MaxHeight <- 3,
    Others <- {"o0", "oBad"},
    ValidOthers <- {"o0"},
    VEHeights <- {-1, 0, 1, 2, 3, 4},
    InitialOthers <- {"o0"},
    InitialVEHs <- {0, 1, 2},
    blockStoreHeight <- S.blockStoreHeight,
    appHeight <- S.appHeight,
    stateStoreHeight <- S.stateStoreHeight,
    stateHeight <- S.stateHeight,
    activeParam <- S.activeParam,
    persistedParam <- S.persistedParam,
    lastParamChange <- S.lastParamChange,
    persistedLastParamChange <- S.persistedLastParamChange,
    responseHeight <- S.responseHeight,
    responseParam <- S.responseParam,
    responseAbciPresent <- S.responseAbciPresent,
    phase <- S.phase,
    replayMutatesState <- S.replayMutatesState,
    pendingBlockHeight <- S.pendingBlockHeight,
    pendingParam <- S.pendingParam,
    pendingAbciPresent <- S.pendingAbciPresent,
    updatePresent <- S.updatePresent,
    validationOutcome <- S.validationOutcome,
    coverage <- S.coverage,
    counters <- [blocks |-> 0, crashes |-> 0, appRollbacks |-> 0],
    MaxBlocks <- 3,
    MaxCrashes <- 0,
    MaxAppRollbacks <- 0
ASSUME PrintT(<<"E2", "new", "EnableFromDisabledNotRejected", New!EnableFromDisabledNotRejected>>)
Init == dummy = 0
Next == UNCHANGED dummy
====
