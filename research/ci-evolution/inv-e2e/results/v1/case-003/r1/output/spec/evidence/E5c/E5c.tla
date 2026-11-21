---- MODULE E5c ----
EXTENDS Integers, TLC
VARIABLE dummy
\* source: constructed control: installed record with VEH 2
S == [blockStoreHeight |-> 1, appHeight |-> 1, stateStoreHeight |-> 1, stateHeight |-> 1, activeParam |-> [other |-> "o0", veh |-> 2], persistedParam |-> [other |-> "o0", veh |-> 2], lastParamChange |-> 2, persistedLastParamChange |-> 2, responseHeight |-> 1, responseParam |-> [other |-> "o0", veh |-> 2], responseAbciPresent |-> TRUE, phase |-> "normal", replayMutatesState |-> FALSE, pendingBlockHeight |-> 0, pendingParam |-> [other |-> "NoOther", veh |-> 0], pendingAbciPresent |-> FALSE, validationOutcome |-> "none", updatePresent |-> FALSE, coverage |-> {}]
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
OS == [blockStoreHeight |-> 1, appHeight |-> 1, stateStoreHeight |-> 1, stateHeight |-> 1, activeParam |-> "o0/2", persistedParam |-> "o0/2", lastParamChange |-> 2, persistedLastParamChange |-> 2, responseHeight |-> 1, responseParam |-> "o0/2", phase |-> "normal", replayMutatesState |-> FALSE, pendingBlockHeight |-> 0, pendingParam |-> "NoParam", updatePresent |-> FALSE, validationOutcome |-> "none", coverage |-> {}]
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
ASSUME PrintT(<<"E5c", "new", "InstalledParamsBasicValid", New!InstalledParamsBasicValid>>)
ASSUME PrintT(<<"E5c", "new", "NormalPhaseIsSynchronized", New!NormalPhaseIsSynchronized>>)
ASSUME PrintT(<<"E5c", "old", "NormalPhaseIsSynchronized", Old!NormalPhaseIsSynchronized>>)
Init == dummy = 0
Next == UNCHANGED dummy
====
