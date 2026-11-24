---- MODULE CensusProbes ----
EXTENDS MC
\* Census precondition probes for v2/case-003 (state predicates only; no actions).

\* Pre-update enable height seen by updateState: in phase "rejected" activeParam is unchanged
\* (UpdateStateRejected); in phase "updated" persistedParam still holds the pre-block params.
CP_E == IF phase = "rejected" THEN activeParam.ve ELSE persistedParam.ve
\* Copy of UpdateProps!SpecPermittedVEChange (copied to avoid a name clash when run on Update).
CP_Permitted(E, u, h) ==
    \/ ~u.abciPresent
    \/ /\ u.abci >= 0 /\ ~VEEnabled(E, h) /\ (u.abci = 0 \/ u.abci > h)

\* S1 "FinalizeBlock may return a complete or partial consensus-parameter update; the candidate is ...
\* checked by ValidateBasic and ValidateUpdate, and installed only if both checks succeed."
\* (output/modeling-brief.md:19) -> (a) an update carrying an enable height is accepted/installed
SC_S1a == phase = "updated" /\ updatePresent /\ pendingParam.abciPresent
\* (b) a candidate is rejected (not installed)
SC_S1b == phase = "rejected"

\* S4 "every accepted transition must keep the enabled/disabled status of already-decided heights
\* unchanged" (output/modeling-brief.md:82) -> an accepted enable-height change after heights are stored
SC_S4a == phase = "updated" /\ pendingParam.abciPresent /\ activeParam.ve /= persistedParam.ve
          /\ Len(veHist) > 0
\* S4 "protocol-permitted transitions must not be rejected (a rejection halts the chain)"
\* (output/modeling-brief.md:82) -> an enable-height update passes ValidateBasic and is rejected by the table
SC_S4b == phase = "rejected" /\ pendingParam.abciPresent /\ ValidateBasic(ApplyUpdate(activeParam, pendingParam))

\* S5 "after a crash, mock replay (app committed) or real replay (app not committed) re-runs updateState
\* on the saved/re-executed update with the persisted params" (output/modeling-brief.md:98)
SC_S5a == replayMutatesState /\ phase \in {"updated", "rejected"} /\ pendingParam.abciPresent
          /\ appHeight = pendingBlockHeight
SC_S5b == replayMutatesState /\ phase \in {"updated", "rejected"} /\ pendingParam.abciPresent
          /\ appHeight < pendingBlockHeight
\* S5 "a rejected update is re-executed and rejected again on every restart" (output/modeling-brief.md:98)
SC_S5c == "rejectedAbort" \in coverage /\ replayMutatesState /\ phase = "rejected"

\* VEHistoryStable intent "whether vote extensions are required at that height is the same under the
\* parameters that were in effect at that height ... and under the node's current ... parameters"
\* (output/spec/UpdateProps.tla:16) -> a stored height whose params differ from the current ones
SC_P_VHS == \E m \in DOMAIN veHist : veHist[m] /= activeParam.ve

\* VEEnableMonotone intent "once a height requires vote extensions every later stored height requires
\* them too" (output/spec/UpdateProps.tla:36)
SC_P_VEM == \E m1, m2 \in DOMAIN veHist : m1 < m2 /\ VEEnabled(veHist[m1], m1)

\* StartupLastCommitConsistent intent "When the node is in normal operation after a stored block, if the
\* current parameters say that block required vote extensions" (output/spec/UpdateProps.tla:50)
SC_P_SLCC == phase = "normal" /\ stateHeight > 0 /\ stateHeight \in DOMAIN veHist
             /\ VEEnabled(activeParam.ve, stateHeight)

\* AcceptedVEUpdateRespectsRules intent "An accepted parameter update ... never changes an enable height
\* that has already been reached at the current block" (output/spec/UpdateProps.tla:64)
\* (an accepted non-nil update at a block where the current enable height is already reached; Abci presence
\* is not required by the wording, and an Abci-present change at a reached height is rejected by design)
SC_P_AVR == phase \in {"updated", "committed"} /\ updatePresent
            /\ VEEnabled(persistedParam.ve, pendingBlockHeight)

\* PermittedVEUpdateNotRejected intent "A parameter update whose non-ABCI part is valid and whose
\* enable-height change is permitted by the protocol (... cancelled or set to a height after the current
\* block)" (output/spec/UpdateProps.tla:94) -> such a changing update reaches validation
SC_P_PVNR == phase \in {"updated", "rejected"} /\ pendingParam.abciPresent /\ pendingParam.abci /= CP_E
             /\ ValidateBasic(ApplyUpdate(IF phase = "rejected" THEN activeParam ELSE persistedParam, pendingParam))
             /\ CP_Permitted(CP_E, pendingParam, pendingBlockHeight)

\* UnchangedVEUpdateNotRejected "clause before-reached: ... unchanged value with E > h"
\* (output/spec/UpdateProps.tla:127)
SC_P_UVNRa == phase \in {"updated", "rejected"} /\ pendingParam.abciPresent /\ pendingParam.abci = CP_E
              /\ CP_E > pendingBlockHeight
\* "clause after-reached: unknown — unchanged value with 0 < E <= h" (output/spec/UpdateProps.tla:128)
SC_P_UVNRb == phase \in {"updated", "rejected"} /\ pendingParam.abciPresent /\ pendingParam.abci = CP_E
              /\ 0 < CP_E /\ CP_E <= pendingBlockHeight

\* Positive control: a block was stored.
SC_CTRL == Len(veHist) > 0
====
