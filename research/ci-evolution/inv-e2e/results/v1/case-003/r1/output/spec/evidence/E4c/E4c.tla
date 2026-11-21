---- MODULE E4c ----
EXTENDS Integers, TLC
VARIABLE dummy
\* source: constructed control: accepted enable to a future height (P=0 -> 2, h=1, row 7)
S == [blockStoreHeight |-> 1, appHeight |-> 0, stateStoreHeight |-> 0, stateHeight |-> 1, activeParam |-> [other |-> "o0", veh |-> 2], persistedParam |-> [other |-> "o0", veh |-> 0], lastParamChange |-> 2, persistedLastParamChange |-> 1, responseHeight |-> 1, responseParam |-> [other |-> "o0", veh |-> 2], responseAbciPresent |-> TRUE, phase |-> "updated", replayMutatesState |-> FALSE, pendingBlockHeight |-> 1, pendingParam |-> [other |-> "o0", veh |-> 2], pendingAbciPresent |-> TRUE, validationOutcome |-> "accepted", updatePresent |-> TRUE, coverage |-> {}]
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
\* representation-only mapping: [other |-> o, veh |-> v] -> "o/v"
OS == [blockStoreHeight |-> 1, appHeight |-> 0, stateStoreHeight |-> 0, stateHeight |-> 1, activeParam |-> "o0/2", persistedParam |-> "o0/0", lastParamChange |-> 2, persistedLastParamChange |-> 1, responseHeight |-> 1, responseParam |-> "o0/2", phase |-> "updated", replayMutatesState |-> FALSE, pendingBlockHeight |-> 1, pendingParam |-> "o0/2", updatePresent |-> TRUE, validationOutcome |-> "accepted", coverage |-> {}]
Old == INSTANCE OldBase WITH MaxHeight <- 3,
    Params <- {"o0/-1", "o0/0", "o0/1", "o0/2", "o0/3", "o0/4", "oBad/-1", "oBad/0", "oBad/1", "oBad/2", "oBad/3", "oBad/4"},
    ValidParams <- {"o0/0", "o0/1", "o0/2", "o0/3", "o0/4"},
    InitialParam <- "o0/0",
    NoParam <- "NoParam",
    blockStoreHeight <- OS.blockStoreHeight,
    appHeight <- OS.appHeight,
    stateStoreHeight <- OS.stateStoreHeight,
    stateHeight <- OS.stateHeight,
    activeParam <- OS.activeParam,
    persistedParam <- OS.persistedParam,
    lastParamChange <- OS.lastParamChange,
    persistedLastParamChange <- OS.persistedLastParamChange,
    responseHeight <- OS.responseHeight,
    responseParam <- OS.responseParam,
    phase <- OS.phase,
    replayMutatesState <- OS.replayMutatesState,
    pendingBlockHeight <- OS.pendingBlockHeight,
    pendingParam <- OS.pendingParam,
    updatePresent <- OS.updatePresent,
    validationOutcome <- OS.validationOutcome,
    coverage <- OS.coverage
ASSUME PrintT(<<"E4c", "new", "VEChangeOnlyToFuture", New!VEChangeOnlyToFuture>>)
ASSUME PrintT(<<"E4c", "new", "VEReachedImmutable", New!VEReachedImmutable>>)
ASSUME PrintT(<<"E4c", "new", "ParameterUpdateReflected", New!ParameterUpdateReflected>>)
ASSUME PrintT(<<"E4c", "new", "SuccessfulApplyAdvancesExactlyOne", New!SuccessfulApplyAdvancesExactlyOne>>)
ASSUME PrintT(<<"E4c", "old", "ParameterUpdateReflected", Old!ParameterUpdateReflected>>)
ASSUME PrintT(<<"E4c", "old", "SuccessfulApplyAdvancesExactlyOne", Old!SuccessfulApplyAdvancesExactlyOne>>)
Init == dummy = 0
Next == UNCHANGED dummy
====
