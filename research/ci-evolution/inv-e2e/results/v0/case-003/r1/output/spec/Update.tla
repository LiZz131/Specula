------------------------------- MODULE Update -------------------------------
(***************************************************************************
Update-focused checking lens over the V1 reference (base.tla/MC.tla).

Source delta (old -> new): types/params.go:208-261, ConsensusParams.
ValidateUpdate.  With c = current ABCI.VoteExtensionsEnableHeight, u = the
proposed one (Abci sub-record present) and h = header.Height
(internal/state/execution.go:622), the new rule accepts iff
    u >= 0 /\ ~VEEnabled(c, h) /\ ~VEEnabled(u, h)
whereas the old rule accepted iff u = c \/ (u > h /\ c > h).  The changed
classes are (spec/output/validate-update-projection.log):
  * c = 0, u > h          : old reject -> new accept  (first enablement)
  * c > h, u = 0          : old reject -> new accept  (cancel a future height)
  * u = c, VEEnabled(c,h) : old accept -> new REJECT  (unchanged re-send)

This module does not redefine behavior: every Action is an MC wrapper of a
reference Action.  It selects the changed Actions and the unchanged
producers/consumers/fault/recovery Actions that interact with them, defines
an explicit rely (EnvUpdate) for the omitted context, and states the
update-specific properties.
***************************************************************************)
EXTENDS MC

-----------------------------------------------------------------------------
(* Affected Actions: the acceptance predicate changed.                      *)
\* reference: base!UpdateStateAccepted, base!UpdateStateRejected,
\*            base!ValidateUpdateOK
\* code: types/params.go:219-261 via internal/state/execution.go:611-631
AffectedActions ==
    \/ MCUpdateStateAccepted
    \/ \E s \in RejectStages : MCUpdateStateRejected(s)

(* Interaction Actions: unchanged Actions that produce the validated input,  *)
(* persist/consume its result, or re-run it across crash/recovery.          *)
InteractionActions ==
    \/ MCSaveBlock                                  \* consensus/state.go:1781-1790
    \/ MCApplyBlockStart                            \* execution.go:211-216
    \/ \E p \in UpdateOrNone : MCFinalizeBlock(p)   \* producer: execution.go:219-234
    \/ MCSaveFinalizeBlockResponse                  \* durable input of mock replay: :253-256
    \/ MCCommitApp                                  \* consumer: execution.go:284-288
    \/ MCSaveState                                  \* persists c for H+1: :295-299
    \/ MCAbortRejectedApply                         \* consequence: consensus/state.go:1834-1836
    \/ MCCrash                                      \* crash cut across validation
    \/ MCBeginHandshake                             \* replay.go:241-267
    \/ MCSelectRealReplay                           \* re-validation, real app: replay.go:408-415
    \/ MCSelectMockReplay                           \* re-validation, saved response: :417-433
    \/ MCCompleteHandshake                          \* replay.go:385-438

(* Omitted context: they change only appHeight / replay flag / observers.  *)
OmittedContextActions ==
    \/ \E h \in 0..MaxHeight : MCAppReportsOlderHeight(h)   \* replay.go:388-406
    \/ MCReplayAppBlock                                     \* replay.go:441-489
    \/ MCEnvironmentStutter

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

-----------------------------------------------------------------------------
(* Rely for omitted context (modular-verification.md).  While the node is  *)
(* down or in the handshake, the application's reported height may move but *)
(* never above Max(appHeight, stateStoreHeight): an omitted Action can never *)
(* fabricate "the application committed the stored block", which is the    *)
(* premise of mock replay.  Parameters, responses, heights of the stores,   *)
(* phase and in-flight update are framed.                                    *)
MaxOf(a, b) == IF a >= b THEN a ELSE b

EnvUpdate ==
    /\ phase \in {"down", "handshake"}
    /\ appHeight' \in 0..MaxOf(appHeight, stateStoreHeight)
    /\ appHeight' /= appHeight
    /\ replayMutatesState' \in {replayMutatesState, FALSE}
    /\ coverage' \in {coverage \cup S :
                        S \in SUBSET {"appReportedOlder", "appOnlyReplay"}}
    \* only the app-rollback budget may be consumed (blocks/crashes framed)
    /\ counters' \in {[counters EXCEPT !.appRollbacks = r] :
                        r \in counters.appRollbacks..MaxAppRollbacks}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    phase, pendingBlockHeight, pendingParam, updatePresent,
                    validationOutcome>>

OpenNext == AffectedActions \/ InteractionActions \/ EnvUpdate
OpenSpec == MCInit /\ [][OpenNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely (checked
\* over the full MCSpec reachable state space; stuttering is trivially ok).
DischargeEnvUpdate == [][OmittedContextActions => EnvUpdate]_mcVars

\* Non-vacuity canary for the discharge: expected VIOLATION, showing that
\* omitted context Actions really fire in the checked state space.
DischargeCanaryOmittedNeverFires == [][~OmittedContextActions]_mcVars

-----------------------------------------------------------------------------
(* Update properties.                                                        *)

\* Helpers guarded so TLC never compares a model value with an integer.
HasAbci(upd) == upd /= NoParam /\ upd.abci /= NoAbci
H == pendingBlockHeight

\* Application contract for consensus_param_updates.Abci:
\*   spec/abci/abci++_app_requirements.md:760-777 ("Must always be set to a
\*   future height. Once set to a value different from 0, its value must not
\*   be changed."), :779-789 (each non-empty sub-record is applied in full;
\*   unchanged values are re-sent), :1118-1129 (enable via FinalizeBlock at a
\*   height > current, earliest h+1).  Changing an already non-zero value is
\*   contract-illegal (the implementation may tolerate it; tolerance is not
\*   checked here).
ContractLegalAbci(cur, upd, h) ==
    \/ upd.abci = NoAbci
    \/ upd.abci = cur.veh                         \* unchanged: not a change
    \/ /\ cur.veh = 0                             \* first enablement ...
       /\ upd.abci > h                            \* ... at a future height

ContractLegalUpdate(cur, upd, h) ==
    /\ upd /= NoParam
    /\ ValidateBasicOK(ApplyParamUpdate(cur, upd))
    /\ ContractLegalAbci(cur, upd, h)

\* P-U1 (new, halt-freedom).  Scenario U1/U2.  A rejected update makes
\* ApplyBlock fail; consensus panics (consensus/state.go:1834-1836) and the
\* replay re-executes the same block and rejects again (replay.go:408-415,
\* execution.go:622), so every honest node halts at H.  Hence a contract-legal
\* update must never be rejected.  In phase "rejected", activeParam is the
\* record the update was validated against (RejectedUpdateDoesNotInstall).
ContractLegalUpdateAccepted ==
    phase = "rejected" =>
        ~ContractLegalUpdate(activeParam, pendingParam, H)

\* P-U2 (revised safety of the changed rule).  Scenario U3.  Once vote
\* extensions are enabled at H, an accepted update cannot move the enable
\* height (rows 4 and 8; abci++_app_requirements.md:770-777).
VEEnableHeightImmutableOnceEnabled ==
    (phase \in {"updated", "committed"} /\ VEEnabled(persistedParam.veh, H))
        => activeParam.veh = persistedParam.veh

\* P-U3 (interaction with unchanged consumers).  Scenario U3.  After the
\* update is installed, consumers evaluate VoteExtensionsEnabled(k) for an
\* already-decided height k <= H with the NEW record:
\* reconstructLastCommit (internal/consensus/state.go:589-597),
\* blocksync (internal/blocksync/reactor.go:384-386), and
\* buildExtendedCommitInfo (internal/state/execution.go:536-543).  The
\* answer for decided heights must not change.
VEStatusOfDecidedHeightsPreserved ==
    phase \in {"updated", "committed"} =>
        \A k \in 1..H :
            VEEnabled(activeParam.veh, k) = VEEnabled(persistedParam.veh, k)

\* P-U4 (interaction with recovery).  Scenario U4.  Mock replay is selected
\* only when the application already committed the stored block
\* (replay.go:417-433), i.e. the original validation accepted it.  The
\* re-validation of the saved response must therefore never reject.
MockReplayRevalidationAccepts ==
    (phase = "rejected" /\ replayMutatesState) => appHeight < H

-----------------------------------------------------------------------------
(* Reachability canaries (expected violations = witnesses).                 *)
UpdatedWith(pred(_)) ==
    phase = "updated" /\ HasAbci(pendingParam) /\ pred(pendingParam.abci)

\* row 7: first enablement accepted
NeverEnableFromZeroAccepted ==
    ~(persistedParam.veh = 0 /\ UpdatedWith(LAMBDA u : u > H))
\* row 5: cancel a not-yet-reached enable height
NeverCancelFutureAccepted ==
    ~(persistedParam.veh > H /\ UpdatedWith(LAMBDA u : u = 0))
\* row 9: move a not-yet-reached enable height
NeverModifyFutureAccepted ==
    ~(persistedParam.veh > H
      /\ UpdatedWith(LAMBDA u : u > H /\ u /= persistedParam.veh))
\* row 3: 0 -> 0
NeverZeroToZeroAccepted ==
    ~(persistedParam.veh = 0 /\ UpdatedWith(LAMBDA u : u = 0))

RejectedUpdate(pred(_)) ==
    /\ phase = "rejected"
    /\ HasAbci(pendingParam)
    /\ ValidateBasicOK(ApplyParamUpdate(activeParam, pendingParam))
    /\ pred(pendingParam.abci)

\* row 6 with c enabled and u = c: the regression class
NeverUnchangedAfterEnableRejected ==
    ~(VEEnabled(persistedParam.veh, H)
      /\ RejectedUpdate(LAMBDA u : u = persistedParam.veh))
\* row 4
NeverDisableAfterEnableRejected ==
    ~(VEEnabled(persistedParam.veh, H) /\ RejectedUpdate(LAMBDA u : u = 0))
\* row 8
NeverModifyAfterEnableRejected ==
    ~(VEEnabled(persistedParam.veh, H) /\ RejectedUpdate(LAMBDA u : u > H))
\* row 6 with c = 0 (u <= h)
NeverPastHeightRejected ==
    ~(persistedParam.veh = 0 /\ RejectedUpdate(LAMBDA u : u > 0 /\ u <= H))

\* recovery interactions
NeverMockReplayRevalidatedVE ==
    ~(phase = "updated" /\ replayMutatesState /\ appHeight = H
      /\ HasAbci(pendingParam))
NeverRealReplayRejected ==
    ~(phase = "rejected" /\ replayMutatesState)
\* consequence witness: a contract-legal update is rejected again on replay
NeverLegalUpdateRejectedOnReplay ==
    ~(phase = "rejected" /\ replayMutatesState
      /\ ContractLegalUpdate(activeParam, pendingParam, H))

=============================================================================
