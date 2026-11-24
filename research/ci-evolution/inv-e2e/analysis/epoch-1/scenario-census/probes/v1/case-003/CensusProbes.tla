---- MODULE CensusProbes ----
EXTENDS Update

\* ReachedRow(r) (MC.tla) = decision of ValidateUpdate row r held with Abci present and ValidateBasic OK.

\* U1: "Enable vote extensions from the disabled state (row 7) ... app FinalizeBlock returns Abci{U > h} with P = 0"
\* (output/modeling-brief.md:28-30)
SC_U1 == ReachedRow(7)

\* U1b: "is the new acceptance installed with lastParamChange = h+1 and persisted" (output/modeling-brief.md:34-35)
SC_U1b == ReachedSavedEnable

\* U2a: "Re-sent unchanged enable height after it is reached (row 6) ... with P = U > 0, P <= h"
\* (output/modeling-brief.md:40-45)
SC_U2a == ReachedRow(6) /\ pendingParam.veh = persistedParam.veh /\ persistedParam.veh > 0

\* U2b: "does restart replay re-reject it (permanent halt)?" / "AbortRejectedApply (panic) -> crash/recovery ->
\* SelectRealReplay or SelectMockReplay -> same rejection" (output/modeling-brief.md:45-47,54-55)
SC_U2b == VERejectionHeld /\ replayMutatesState /\ pendingParam.veh = activeParam.veh
          /\ "rejectedAbort" \in coverage

\* U3: "Cancel a not-yet-reached enable height (row 5) P > h, U = 0" (output/modeling-brief.md:58-59)
SC_U3 == ReachedRow(5)

\* U4a: "Reached enable height is frozen (rows 4, 8) P > 0, P <= h, U != P must be rejected" -- disable (row 4)
\* (output/modeling-brief.md:63-64)
SC_U4a == ReachedRow(4)
\* U4b: same scenario, move (row 8)
SC_U4b == ReachedRow(8)

\* U5a: "Only future enable heights are accepted (rows 6, 7, 9)" -- move to a future height accepted (row 9, changed)
\* (output/modeling-brief.md:68-71, trace ve_move_future)
SC_U5a == ReachedRow(9) /\ pendingParam.veh /= persistedParam.veh
\* U5b: same scenario -- a change to a non-future height (row 6 with U != P), e.g. ve_enable_current
SC_U5b == ReachedRow(6) /\ pendingParam.veh /= persistedParam.veh

\* U6a: "a VE change accepted at h, app committed, crash before SaveState -> mock replay re-validates the saved
\* response with the same (P, h)" (output/modeling-brief.md:74-77)
SC_U6a == ReachedMockReplayOfVEChange /\ "crashed" \in coverage /\ "appCommitted" \in coverage

\* U6b: "a VE change rejected at h -> real replay re-rejects" (output/modeling-brief.md:77-78)
SC_U6b == VERejectionHeld /\ replayMutatesState /\ "realReplaySelected" \in coverage

\* U7: "Block 1 enables at h_e = 2 (row 7); block 2 at h = 2 forwards the unchanged set (row 6)"
\* (output/modeling-brief.md:84-86)
SC_U7 == ReachedRow(6) /\ pendingParam.veh = persistedParam.veh /\ persistedLastParamChange > 1

\* positive control
SC_CTRL == "acceptedUpdate" \in coverage
====
