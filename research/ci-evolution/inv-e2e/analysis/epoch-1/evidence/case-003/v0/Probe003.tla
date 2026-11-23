------------------------------ MODULE Probe003 ------------------------------
(* Decision probes for case-003 (v0). State predicates only.                *)
EXTENDS Update

\* Bug trigger: a basic-valid update that re-sends the current, already reached
\* vote-extension enable height (0 < E <= h) has been rejected.
BugState == /\ phase = "rejected" /\ updatePresent
            /\ pendingParam.abci /= NoAbci
            /\ ValidateBasicOK(ApplyParamUpdate(activeParam, pendingParam))
            /\ pendingParam.abci = activeParam.veh
            /\ 0 < activeParam.veh /\ activeParam.veh <= pendingBlockHeight
ProbeNoBug == ~BugState

\* PUR before v0 rewrote it, translated into v0's representation: the accepted
\* update also passes ValidateUpdate (with the receiver = the pre-update params,
\* which equal persistedParam while phase = "updated", see ProbeReceiverStable).
OldValidity == (phase = "updated" /\ updatePresent) =>
                   ValidateUpdateOK(persistedParam, pendingParam, pendingBlockHeight)
\* Same, with the OLD-tree ValidateUpdate (types/params.go:208-230 of old-tree).
OldCodeOK(c, u, h) == \/ u = NoAbci
                      \/ c = u
                      \/ /\ ~(c /= 0 /\ u = 0) /\ u > h /\ c > h
OldCodeValidity == (phase = "updated" /\ updatePresent) =>
                       OldCodeOK(persistedParam.veh, pendingParam.abci, pendingBlockHeight)
ProbeReceiverStable == phase = "responseSaved" => activeParam = persistedParam
=============================================================================
