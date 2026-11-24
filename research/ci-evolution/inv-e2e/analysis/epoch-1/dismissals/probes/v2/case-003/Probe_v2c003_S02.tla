---- MODULE Probe_v2c003_S02 ----
\* Dismissal (modeling-brief.md:200): "Row 2 (`must be positive`) is unreachable from
\* `updateState` because `ValidateBasic` rejects a negative candidate first"
\* Canary: a saved response about to be validated passes ValidateBasic and ValidateUpdate
\* decides it by row 2.
EXTENDS Update
Canary == /\ phase = "responseSaved" /\ updatePresent
          /\ ValidateBasic(NextParams)
          /\ ValidateUpdateRow(activeParam.ve, pendingParam, pendingBlockHeight) = 2
NotCanary == ~Canary
====
