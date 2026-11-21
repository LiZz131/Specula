---- MODULE T2 ----
EXTENDS Integers, TLC
VARIABLE dummy
\* source: trace: post-state of event 5 (UpdateStateAccepted) in traces/ve_enable_future.ndjson
S == [activeParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 3], appHeight |-> 0, blockStoreHeight |-> 1, lastParamChange |-> 2, pendingAbciPresent |-> TRUE, pendingBlockHeight |-> 1, pendingParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 3], persistedLastParamChange |-> 1, persistedParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 0], phase |-> "updated", replayMutatesState |-> FALSE, responseAbciPresent |-> TRUE, responseHeight |-> 1, responseParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 3], stateHeight |-> 1, stateStoreHeight |-> 0, validationOutcome |-> "accepted", updatePresent |-> TRUE, coverage |-> {}]
New == INSTANCE Update WITH MaxHeight <- 3,
    Others <- {"13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", "oBad"},
    ValidOthers <- {"13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967"},
    VEHeights <- {-1, 0, 1, 2, 3, 4, 5, 7},
    InitialOthers <- {"13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967"},
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
OS == [blockStoreHeight |-> 1, appHeight |-> 0, stateStoreHeight |-> 0, stateHeight |-> 1, activeParam |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/3", persistedParam |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/0", lastParamChange |-> 2, persistedLastParamChange |-> 1, responseHeight |-> 1, responseParam |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/3", phase |-> "updated", replayMutatesState |-> FALSE, pendingBlockHeight |-> 1, pendingParam |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/3", updatePresent |-> TRUE, validationOutcome |-> "accepted", coverage |-> {}]
Old == INSTANCE OldBase WITH MaxHeight <- 3,
    Params <- {"13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/-1", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/0", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/1", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/2", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/3", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/4", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/5", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/7", "oBad/-1", "oBad/0", "oBad/1", "oBad/2", "oBad/3", "oBad/4", "oBad/5", "oBad/7"},
    ValidParams <- {"13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/0", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/1", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/2", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/3", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/4", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/5", "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967/7"},
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
ASSUME PrintT(<<"T2", "new", "EnableFromDisabledNotRejected", New!EnableFromDisabledNotRejected>>)
ASSUME PrintT(<<"T2", "new", "ParameterUpdateReflected", New!ParameterUpdateReflected>>)
ASSUME PrintT(<<"T2", "new", "SuccessfulApplyAdvancesExactlyOne", New!SuccessfulApplyAdvancesExactlyOne>>)
ASSUME PrintT(<<"T2", "new", "VEChangeOnlyToFuture", New!VEChangeOnlyToFuture>>)
ASSUME PrintT(<<"T2", "new", "VEReachedImmutable", New!VEReachedImmutable>>)
ASSUME PrintT(<<"T2", "old", "ParameterUpdateReflected", Old!ParameterUpdateReflected>>)
ASSUME PrintT(<<"T2", "old", "SuccessfulApplyAdvancesExactlyOne", Old!SuccessfulApplyAdvancesExactlyOne>>)
Init == dummy = 0
Next == UNCHANGED dummy
====
