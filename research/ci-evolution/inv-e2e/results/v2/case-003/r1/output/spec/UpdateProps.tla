----------------------------- MODULE UpdateProps -----------------------------
(***************************************************************************
Property section of the Update.tla checking lens for the case-003 update.
Split into its own module (EXTENDS base only) so that the same predicates
are evaluated over full MCNext (Update.tla), focused/open specs, and real
implementation traces (Trace.tla) without duplicating definitions.
Owner: Update.tla.  No Action is defined here.
***************************************************************************)
EXTENDS base

(***************************************************************************
Update properties.
***************************************************************************)

\* REQ-EVIDENCE VEHistoryStable
\* intent:   For every stored block height, whether vote extensions are required at that height is the same under the parameters that were in effect at that height (used when the block and its extended commit were saved) and under the node's current in-memory and saved parameters (used later by restart reconstruction and block-sync serving).
\* status:   requirement
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "For all heights after `H`" + "vote extensions cannot be disabled," -> once a height requires extensions, later parameters never make it not require them
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "Must always be set to a future height." -> a new enable height never makes an already-passed height require extensions
\* evidence: protocol spec/abci/abci++_comet_expected_behavior.md §Handling upgrades to ABCI 2.0 "upon saving the block for a given height *h* in the block store at decision time" -> the extended commit is stored according to the enable height at decision time
\* evidence: protocol spec/abci/abci++_comet_expected_behavior.md §Handling upgrades to ABCI 2.0 "if *h<sub>p</sub> ≥ h<sub>e</sub>*, *f* uses the extended commit to" -> catch-up later decides from the enable height whether an extended commit exists for a past height
\* evidence: contract source/internal/consensus/state.go:585-588 "If VoteExtensions are required" + "the method will panic on an absent ExtendedCommit" -> restart reconstruction relies on the save-time decision
\* evidence: impl source/internal/consensus/state.go:1786 "if cs.state.ConsensusParams.ABCI.VoteExtensionsEnabled(block.Height) {"
\* evidence: impl source/internal/consensus/state.go:590 "extensionsEnabled := state.ConsensusParams.ABCI.VoteExtensionsEnabled(state.LastBlockHeight)"
\* evidence: impl source/internal/blocksync/reactor.go:219 "if state.ConsensusParams.ABCI.VoteExtensionsEnabled(msg.Height) {"
\* watch:    source/types/params.go:ConsensusParams.ValidateUpdate; source/types/params.go:ABCIParams.VoteExtensionsEnabled; source/internal/consensus/state.go:State.finalizeCommit; source/internal/consensus/state.go:State.reconstructLastCommit; source/internal/blocksync/reactor.go:Reactor.respondToPeer
\* verified: update (case-003 neutral "update" commit)
\* note:     new interaction property (old verdict: not checked).  veHist is the durable per-height enable height (state store LoadConsensusParams(m) in traces).
\* review:   ok
VEHistoryStable ==
    \A m \in DOMAIN veHist :
        /\ VEEnabled(activeParam.ve, m) = VEEnabled(veHist[m], m)
        /\ VEEnabled(persistedParam.ve, m) = VEEnabled(veHist[m], m)

\* REQ-EVIDENCE VEEnableMonotone
\* intent:   Along the stored chain, once a height requires vote extensions every later stored height requires them too.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "For all heights after `H`" + "vote extensions cannot be disabled," -> enablement is monotone in height
\* evidence: protocol spec/abci/abci++_app_requirements.md §Application configuration required to switch to ABCI 2.0 "for all heights *h ≥ h<sub>e</sub>*, the consensus algorithm will" -> every height at or after the enable height requires extensions
\* evidence: test source/types/params_test.go:178 TestConsensusParamsUpdate_VoteExtensionsEnableHeight "current: 5, 5 -> 0" (expectedErr true) -> disabling at the enable height is rejected
\* watch:    source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/consensus/state.go:State.finalizeCommit
\* verified: update (case-003 neutral "update" commit)
\* note:     new property (old verdict: not checked).
\* review:   ok
VEEnableMonotone ==
    \A m1, m2 \in DOMAIN veHist :
        (m1 < m2 /\ VEEnabled(veHist[m1], m1)) => VEEnabled(veHist[m2], m2)

\* REQ-EVIDENCE StartupLastCommitConsistent
\* intent:   When the node is in normal operation after a stored block, if the current parameters say that block required vote extensions, then the parameters in effect when it was saved also required them (so an extended commit was stored for restart reconstruction).
\* status:   requirement
\* evidence: contract source/internal/consensus/state.go:585-588 "If VoteExtensions are required" + "the method will panic on an absent ExtendedCommit" -> reconstruction needs an extended commit whenever current params require extensions at LastBlockHeight
\* evidence: protocol spec/abci/abci++_comet_expected_behavior.md §Handling upgrades to ABCI 2.0 "if *h ≥ h<sub>e</sub>*, the corresponding extended commit that was used to decide locally is saved as well" -> extended commits exist exactly for heights enabled at decision time
\* evidence: impl source/internal/consensus/state.go:187 "cs.reconstructLastCommit(state)"
\* watch:    source/internal/consensus/state.go:NewState; source/internal/consensus/state.go:State.reconstructLastCommit; source/types/params.go:ConsensusParams.ValidateUpdate
\* verified: update (case-003 neutral "update" commit)
\* note:     consumer-specific corollary of VEHistoryStable for the restart path (old verdict: not checked).
\* review:   ok
StartupLastCommitConsistent ==
    (phase = "normal" /\ stateHeight > 0 /\ stateHeight \in DOMAIN veHist) =>
        (VEEnabled(activeParam.ve, stateHeight) => VEEnabled(veHist[stateHeight], stateHeight))

\* REQ-EVIDENCE AcceptedVEUpdateRespectsRules
\* intent:   An accepted parameter update never installs a negative enable height, never changes an enable height that has already been reached at the current block, and any change of the enable height sets it to 0 or to a height after the current block.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "This parameter is either 0 or a positive height" -> never negative
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "vote extensions cannot be disabled," -> a reached enable height is not reset to 0
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "Must always be set to a future height." -> a changed value is after the current block
\* evidence: protocol spec/abci/abci++_app_requirements.md §Application configuration required to switch to ABCI 2.0 "which MUST be higher than the current height of the chain" -> a changed value is after the current block
\* evidence: test source/types/params_test.go:184,193 TestConsensusParamsUpdate_VoteExtensionsEnableHeight "current: 5, 10 -> 5" and "current: 10, 10 -> 15" (expectedErr true) -> modifying a reached height or moving it into the past is rejected
\* evidence: test source/types/params_test.go:177,192 TestConsensusParamsUpdate_VoteExtensionsEnableHeight "current: 4, 5 -> 0" (expectedErr false) and "current: 9, 10 -> 15" (expectedErr false) -> cancelling or moving a not-yet-reached enable height is permitted (updated requirement; the protocol sentence "Once set to a value different from 0, its value must not be changed" is not applied before the height is reached, consistent with the V0 test "set to height after current height run")
\* watch:    source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/state/execution.go:updateState
\* verified: update (case-003 neutral "update" commit)
\* note:     replaces the enable-height part of V0 ParameterUpdateReflected's "pendingParam \in ValidParams"; persistedParam is the pre-block parameter record in phases updated/committed.
\* review:   ok
AcceptedVEUpdateRespectsRules ==
    (phase \in {"updated", "committed"} /\ updatePresent) =>
        LET E == persistedParam.ve
            N == activeParam.ve
            h == pendingBlockHeight
        IN /\ N >= 0
           /\ VEEnabled(E, h) => N = E
           /\ N /= E => (N = 0 \/ N > h)

\* Protocol-permitted enable-height transition (absent Abci, or the current
\* enable height not reached yet and the new value 0 or after the block).
SpecPermittedVEChange(E, u, h) ==
    \/ ~u.abciPresent
    \/ /\ u.abci >= 0
       /\ ~VEEnabled(E, h)
       /\ (u.abci = 0 \/ u.abci > h)

\* REQ-EVIDENCE PermittedVEUpdateNotRejected
\* intent:   A parameter update whose non-ABCI part is valid and whose enable-height change is permitted by the protocol (no Abci subrecord, or an enable height that is not yet reached being cancelled or set to a height after the current block) is not rejected; a rejection makes ApplyBlock fail, which halts the node and recurs on every restart.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_app_requirements.md §`FinalizeBlock`, `PrepareProposal`/`ProcessProposal` "If `ConsensusParams` is not `nil`, CometBFT will use it." -> a protocol-conforming update is installed
\* evidence: protocol spec/abci/abci++_app_requirements.md §Application configuration required to switch to ABCI 2.0 "or via the application logic by changing the `ConsensusParam` to configure the" -> enabling through FinalizeBlock is a supported path
\* evidence: protocol spec/abci/abci++_app_requirements.md §Application configuration required to switch to ABCI 2.0 "Thus the earliest value for" -> setting h_u+1 from height h_u is permitted
\* evidence: design .changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md "Validation of `VoteExtensionsEnableHeight` can cause chain halt" -> rejecting a legitimate enable-height update is the defect the update fixes
\* evidence: test source/types/params_test.go:172,177,192 "current: 4, 0 -> 5", "current: 4, 5 -> 0", "current: 9, 10 -> 15" (expectedErr false)
\* evidence: comment source/internal/consensus/state.go:1808-1810 "the State should not be resumed until we" + "successfully call ApplyBlock" -> a rejected block blocks progress, including after restart
\* evidence: impl source/internal/consensus/state.go:1834-1836 "failed to apply block; error %v"
\* watch:    source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/state/execution.go:updateState; source/internal/consensus/state.go:State.finalizeCommit
\* verified: update (case-003 neutral "update" commit)
\* note:     new property (old verdict: not checked); the V0 implementation rejects the 0 -> h+1 enable (row-7 cell), so this property detects a regression to the old behavior.
\* review:   ok
PermittedVEUpdateNotRejected ==
    phase = "rejected" =>
        ~( /\ ValidateBasic(ApplyUpdate(activeParam, pendingParam))
           /\ SpecPermittedVEChange(activeParam.ve, pendingParam, pendingBlockHeight))

\* REQ-EVIDENCE UnchangedVEUpdateNotRejected
\* intent:   A parameter update whose non-ABCI part is valid and whose Abci subrecord repeats the current enable height unchanged is not rejected (re-sending an unchanged value cannot violate any enable-height rule, and a rejection halts the chain).
\* status:   mixed
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "Once set to a value different from 0, its value must not be changed." -> the app requirement concerns changing the value; repeating it does not change it
\* evidence: protocol spec/abci/abci++_app_requirements.md §Updating Consensus Parameters "Each field that is not empty will be applied in full." -> a present Abci subrecord is applied as a whole; applying the same value is a no-op
\* evidence: protocol spec/abci/abci++_app_requirements.md §`FinalizeBlock`, `PrepareProposal`/`ProcessProposal` "If `ConsensusParams` is not `nil`, CometBFT will use it." -> CometBFT uses a present update
\* evidence: test source/internal/state/state_test.go:1044 TestConsensusParamsChangesSaveLoad "makeHeaderPartsResponsesParams(state, cp.ToProto())" -> complete-record updates (ToProto always includes Abci, types/params.go:320-342) are an in-tree producer pattern applied every block
\* evidence: history /work/old-source/types/params_test.go:196-204 TestConsensusParamsUpdate_VoteExtensionsEnableHeight "no error when unchanged" (100 -> 100 at height 500, NoError) -> the V0 requirement accepted an unchanged value after the enable height
\* evidence: design .changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md "Validation of `VoteExtensionsEnableHeight` can cause chain halt" -> the update's stated goal is to remove validation-induced halts
\* evidence: comment source/internal/consensus/state.go:1808-1810 "the State should not be resumed until we" + "successfully call ApplyBlock" -> a rejection blocks progress, also after restart
\* counter:  test source/types/params_test.go:168-169 TestConsensusParamsUpdate_VoteExtensionsEnableHeight "current: 100, 100 -> 100, " (expectedErr true) and "current: 300, 100 -> 100, " (expectedErr true) -> the updated unit test expects rejection of an unchanged value once the height is reached
\* counter:  comment source/types/params.go:215 "| 6 | *                     | <=height               | vote extensions cannot be updated to a past height" -> the updated decision table rejects any present value at or below the current height
\* counter:  protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "Must always be set to a future height." -> if re-sending counts as "setting", an unchanged past value violates the app requirement
\* watch:    source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/state/execution.go:updateState; source/internal/consensus/state.go:State.finalizeCommit
\* verified: update (case-003 neutral "update" commit)
\* clause before-reached: requirement — unchanged value with E > h: protocol text, V0 test and the updated test types/params_test.go:167 "current: 3, 100 -> 100" (expectedErr false) agree.
\* clause after-reached:  unknown — unchanged value with 0 < E <= h: protocol "must not be changed"/"applied in full", the in-tree complete-record producer and the removed V0 test support acceptance; the updated unit test and decision-table comment expect rejection.  Not weakened toward the implementation (ledger rule 6); its violation is reported as a contested finding.
\* note:     new property (old verdict: not checked).  Evidence that would settle the after-reached clause: a protocol statement that the Abci subrecord must be omitted unless the enable height changes, or a statement that repeating a reached height is invalid app behavior.
\* review:   ok
UnchangedVEUpdateNotRejected ==
    phase = "rejected" =>
        ~( /\ ValidateBasic(ApplyUpdate(activeParam, pendingParam))
           /\ pendingParam.abciPresent
           /\ pendingParam.abci = activeParam.ve)

=============================================================================
