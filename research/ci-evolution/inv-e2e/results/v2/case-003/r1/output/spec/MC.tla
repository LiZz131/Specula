-------------------------------- MODULE MC ---------------------------------
(***************************************************************************
Bounded model-checking wrapper for the updated reference (base.tla).
Fault/environment injections (block production, crash, app rollback) are
counter-bounded; reactive pipeline/recovery steps are not.
***************************************************************************)
EXTENDS base

CONSTANTS MaxBlocks, MaxCrashes, MaxAppRollbacks,
          InitialRest,   \* genesis non-ABCI identity
          InitialVEs,    \* genesis VoteExtensionsEnableHeight choices (>= 0)
          VEProposals    \* non-negative enable heights an app may propose

\* The cfg parser cannot express negative literals; -1 stands for every negative
\* proposal (rejected by ValidateBasic, types/params.go:188-190).
MCVEValues == {-1} \cup VEProposals

\* Genesis parameter records (cfg files cannot hold records; InitialParams <- MCInitialParams).
MCInitialParams == [rest : {InitialRest}, ve : InitialVEs]

VARIABLE counters

mcVars == <<vars, counters>>

MCInit ==
    /\ Init
    /\ counters = [blocks |-> 0, crashes |-> 0, appRollbacks |-> 0]

MCSaveBlock ==
    /\ counters.blocks < MaxBlocks
    /\ SaveBlock
    /\ counters' = [counters EXCEPT !.blocks = @ + 1]

MCCrash ==
    /\ counters.crashes < MaxCrashes
    /\ Crash
    /\ counters' = [counters EXCEPT !.crashes = @ + 1]

MCAppReportsOlderHeight(h) ==
    /\ counters.appRollbacks < MaxAppRollbacks
    /\ AppReportsOlderHeight(h)
    /\ counters' = [counters EXCEPT !.appRollbacks = @ + 1]

MCApplyBlockStart == ApplyBlockStart /\ UNCHANGED counters
MCFinalizeBlock(p) == FinalizeBlock(p) /\ UNCHANGED counters
MCSaveFinalizeBlockResponse == SaveFinalizeBlockResponse /\ UNCHANGED counters
MCUpdateStateAccepted == UpdateStateAccepted /\ UNCHANGED counters
MCUpdateStateRejected == UpdateStateRejected /\ UNCHANGED counters
MCCommitApp == CommitApp /\ UNCHANGED counters
MCSaveState == SaveState /\ UNCHANGED counters
MCAbortRejectedApply == AbortRejectedApply /\ UNCHANGED counters
MCBeginHandshake == BeginHandshake /\ UNCHANGED counters
MCReplayAppBlock == ReplayAppBlock /\ UNCHANGED counters
MCSelectRealReplay == SelectRealReplay /\ UNCHANGED counters
MCSelectMockReplay == SelectMockReplay /\ UNCHANGED counters
MCCompleteHandshake == CompleteHandshake /\ UNCHANGED counters
MCEnvironmentStutter == EnvironmentStutter /\ UNCHANGED counters

MCNext ==
    \/ MCSaveBlock
    \/ MCApplyBlockStart
    \/ \E p \in Updates : MCFinalizeBlock(p)
    \/ MCSaveFinalizeBlockResponse
    \/ MCUpdateStateAccepted
    \/ MCUpdateStateRejected
    \/ MCCommitApp
    \/ MCSaveState
    \/ MCAbortRejectedApply
    \/ MCCrash
    \/ \E h \in 0..MaxHeight : MCAppReportsOlderHeight(h)
    \/ MCBeginHandshake
    \/ MCReplayAppBlock
    \/ MCSelectRealReplay
    \/ MCSelectMockReplay
    \/ MCCompleteHandshake
    \/ MCEnvironmentStutter

MCSpec == MCInit /\ [][MCNext]_mcVars

\* REQ-EVIDENCE MCTypeOK
\* intent:   The base type invariant holds and the model-checking counters stay within their configured bounds.
\* status:   model-internal
\* watch:    none
\* verified: update (case-003 neutral "update" commit)
\* note:     no source evidence searched or expected for a type and bound invariant.
\* review:   ok
MCTypeOK ==
    /\ TypeOK
    /\ counters \in [blocks : 0..MaxBlocks,
                      crashes : 0..MaxCrashes,
                      appRollbacks : 0..MaxAppRollbacks]

\* ---------------------------------------------------------------------------
\* Reachability canaries.  Each NeverReached* invariant is expected to FAIL;
\* the violation trace is the non-vacuity witness for the named behavior.
\* REQ-EVIDENCE NeverReached*  (all canaries below)
\* intent:   The named behavior is never reached; each canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    source/internal/state/execution.go:updateState; source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/consensus/replay.go:Handshaker.ReplayBlocks
\* verified: update (case-003 neutral "update" commit)
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
\* ---------------------------------------------------------------------------
NeverReachedAcceptedUpdate == "acceptedUpdate" \notin coverage
NeverReachedRejectedUpdate == "rejectedUpdate" \notin coverage
NeverReachedCrash == "crashed" \notin coverage
NeverReachedAppOnlyReplay == "appOnlyReplay" \notin coverage
NeverReachedRealReplay == "realReplaySelected" \notin coverage
NeverReachedMockReplay == "mockReplaySelected" \notin coverage
NeverReachedHandshakeComplete == "handshakeComplete" \notin coverage

\* Update-focused canaries (one per changed decision-table row and interaction).
NeverReachedVEAcceptRow1 == "veAccRow1" \notin coverage   \* Abci nil
NeverReachedVEAcceptRow3 == "veAccRow3" \notin coverage   \* 0 -> 0
NeverReachedVEAcceptRow5 == "veAccRow5" \notin coverage   \* cancel a not-yet-reached height (changed: old rejected)
NeverReachedVEAcceptRow7 == "veAccRow7" \notin coverage   \* enable from 0 at a future height (changed: old rejected)
NeverReachedVEAcceptRow9 == "veAccRow9" \notin coverage   \* modify a not-yet-reached height
NeverReachedVERejectBasic == "veRejbasic" \notin coverage \* ValidateBasic failure (incl. negative enable height)
NeverReachedVERejectRow4 == "veRejr4" \notin coverage     \* disable after enable
NeverReachedVERejectRow6 == "veRejr6" \notin coverage     \* set to a past/current height
NeverReachedVERejectRow8 == "veRejr8" \notin coverage     \* modify after enable
NeverReachedVERejectIdentity == "veRejIdentity" \notin coverage \* unchanged value re-sent after enable (changed: old accepted)
NeverReachedVEEnabledBlock == "veEnabledBlockStored" \notin coverage
NeverReachedVEUpdateMockReplay == "veUpdateMockReplay" \notin coverage
NeverReachedVEUpdateRealReplay == "veUpdateRealReplay" \notin coverage

=============================================================================
