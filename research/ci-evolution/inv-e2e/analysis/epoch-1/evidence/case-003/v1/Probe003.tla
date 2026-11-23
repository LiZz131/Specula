------------------------------ MODULE Probe003 ------------------------------
(* Decision probes for case-003 (v1). State predicates only.                *)
EXTENDS Update

BugState == /\ phase = "rejected" /\ updatePresent /\ pendingAbciPresent
            /\ ValidateBasicOK(pendingParam)
            /\ pendingParam.veh = activeParam.veh
            /\ 0 < activeParam.veh /\ activeParam.veh <= pendingBlockHeight
ProbeNoBug == ~BugState
\* Same trigger where the update also changes a non-ABCI field (the realistic
\* shape: the app changes another parameter and echoes Abci unchanged).
ProbeNoBugOtherChanged == ~(BugState /\ pendingParam.other /= activeParam.other)

\* ValidParams before v1 redefined it (base.tla:45): the old model's ValidParams
\* was the ValidateBasic + ValidateUpdate verdict.  Old-meaning PUR validity:
OldValidity == (phase = "updated" /\ updatePresent) =>
                   /\ ValidateBasicOK(pendingParam)
                   /\ ValidateUpdateOK(persistedParam.veh, pendingAbciPresent,
                                       pendingParam.veh, pendingBlockHeight)
OldCodeOK(c, abci, u, h) == \/ ~abci
                            \/ c = u
                            \/ /\ ~(c /= 0 /\ u = 0) /\ u > h /\ c > h
OldCodeValidity == (phase = "updated" /\ updatePresent) =>
                       OldCodeOK(persistedParam.veh, pendingAbciPresent,
                                 pendingParam.veh, pendingBlockHeight)
ProbeReceiverStable == phase = "responseSaved" => activeParam = persistedParam
=============================================================================
