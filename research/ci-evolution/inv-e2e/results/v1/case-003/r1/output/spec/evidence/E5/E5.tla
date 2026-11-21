---- MODULE E5 ----
EXTENDS Integers, TLC
VARIABLE dummy
\* source: constructed: installed record with negative VEH
S == [blockStoreHeight |-> 1, appHeight |-> 1, stateStoreHeight |-> 1, stateHeight |-> 1, activeParam |-> [other |-> "o0", veh |-> -1], persistedParam |-> [other |-> "o0", veh |-> -1], lastParamChange |-> 2, persistedLastParamChange |-> 2, responseHeight |-> 1, responseParam |-> [other |-> "o0", veh |-> 2], responseAbciPresent |-> TRUE, phase |-> "normal", replayMutatesState |-> FALSE, pendingBlockHeight |-> 0, pendingParam |-> [other |-> "NoOther", veh |-> 0], pendingAbciPresent |-> FALSE, validationOutcome |-> "none", updatePresent |-> FALSE, coverage |-> {}]
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
ASSUME PrintT(<<"E5", "new", "InstalledParamsBasicValid", New!InstalledParamsBasicValid>>)
Init == dummy = 0
Next == UNCHANGED dummy
====
