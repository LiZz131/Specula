---- MODULE T2old ----
EXTENDS Integers, TLC
VARIABLE dummy
\* source: old-code control trace: post-state of event 5 (UpdateStateRejected) in traces/controls-old-code/ve_enable_future.ndjson (baseline 9dd6e50)
S == [activeParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 0], appHeight |-> 0, blockStoreHeight |-> 1, lastParamChange |-> 1, pendingAbciPresent |-> TRUE, pendingBlockHeight |-> 1, pendingParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 3], persistedLastParamChange |-> 1, persistedParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 0], phase |-> "rejected", replayMutatesState |-> FALSE, responseAbciPresent |-> TRUE, responseHeight |-> 1, responseParam |-> [other |-> "13116fe37a77a8415d6267bfba8e92fb370ee112eeec29a9aef4fe471cc68967", veh |-> 3], stateHeight |-> 0, stateStoreHeight |-> 0, validationOutcome |-> "rejected", updatePresent |-> TRUE, coverage |-> {}]
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
ASSUME PrintT(<<"T2old", "new", "EnableFromDisabledNotRejected", New!EnableFromDisabledNotRejected>>)
Init == dummy = 0
Next == UNCHANGED dummy
====
