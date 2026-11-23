------------------------------ MODULE Probe003 ------------------------------
(* Decision probes for case-003 (v2). State predicates only.                *)
EXTENDS Update

BugState == /\ phase = "rejected" /\ updatePresent
            /\ pendingParam.present /\ pendingParam.abciPresent
            /\ ValidateBasic(ApplyUpdate(activeParam, pendingParam))
            /\ pendingParam.abci = activeParam.ve
            /\ 0 < activeParam.ve /\ activeParam.ve <= pendingBlockHeight
ProbeNoBug == ~BugState

OldValidity == (phase = "updated" /\ updatePresent) =>
                   ValidateUpdateOK(persistedParam.ve, pendingParam, pendingBlockHeight)
OldCodeOK(c, u, h) == \/ ~u.abciPresent
                      \/ c = u.abci
                      \/ /\ ~(c /= 0 /\ u.abci = 0) /\ u.abci > h /\ c > h
OldCodeValidity == (phase = "updated" /\ updatePresent) =>
                       OldCodeOK(persistedParam.ve, pendingParam, pendingBlockHeight)
ProbeReceiverStable == phase = "responseSaved" => activeParam = persistedParam
=============================================================================
