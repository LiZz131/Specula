---- MODULE Probe_v1c003_S03 ----
\* Dismissal (modeling-brief.md:136): "Row 2 (`U < 0`) is unreachable from `updateState`
\* because `nextParams.ValidateBasic()` runs first (`execution.go:617-620`). No consequence."
\* Canary: a saved response is about to be validated, passes ValidateBasic, and
\* ValidateUpdate decides it by row 2.
EXTENDS Update
Canary == /\ phase = "responseSaved" /\ updatePresent
          /\ ValidateBasicOK(pendingParam)
          /\ ValidateUpdateRow(activeParam.veh, pendingAbciPresent,
                               pendingParam.veh, pendingBlockHeight) = 2
NotCanary == ~Canary
====
