-------------------------------- MODULE MC ---------------------------------
(***************************************************************************
Bounded model-checking wrapper for the V1 reference (base.tla).
Fault-injection/nondeterministic environment actions are counter-bounded;
reactive implementation steps are not.
***************************************************************************)
EXTENDS base

CONSTANTS MaxBlocks, MaxCrashes, MaxAppRollbacks

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
MCFinalizeBlock(p, a) == FinalizeBlock(p, a) /\ UNCHANGED counters
MCSaveFinalizeBlockResponse == SaveFinalizeBlockResponse /\ UNCHANGED counters
MCUpdateStateAccepted == UpdateStateAccepted /\ UNCHANGED counters
MCUpdateStateRejectedBasic == UpdateStateRejectedBasic /\ UNCHANGED counters
MCUpdateStateRejectedVE == UpdateStateRejectedVE /\ UNCHANGED counters
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
    \/ \E p \in ParamOrNone, a \in BOOLEAN : MCFinalizeBlock(p, a)
    \/ MCSaveFinalizeBlockResponse
    \/ MCUpdateStateAccepted
    \/ MCUpdateStateRejectedBasic
    \/ MCUpdateStateRejectedVE
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

\* VEH domains including a negative value (TLC cfg files cannot spell -1).
\* -1 exercises ValidateBasic's VEH clause (types/params.go:188-190), which
\* masks ValidateUpdate row 2.
VEHRangeNeg2 == -1..2
VEHRangeNeg3 == -1..3
VEHRangeNeg4 == -1..4
VEHRangeNeg6 == -1..6

MCTypeOK ==
    /\ TypeOK
    /\ counters \in [blocks : 0..MaxBlocks,
                      crashes : 0..MaxCrashes,
                      appRollbacks : 0..MaxAppRollbacks]

(***************************************************************************
Reachability / non-vacuity canaries.  Each NeverReached* invariant is
expected to be VIOLATED (TLC exit 12); the counterexample is the witness.
***************************************************************************)
ReachedAcceptedUpdate == "acceptedUpdate" \in coverage
ReachedRejectedUpdate == "rejectedUpdate" \in coverage
ReachedCrash == "crashed" \in coverage
ReachedAppOnlyReplay == "appOnlyReplay" \in coverage
ReachedRealReplay == "realReplaySelected" \in coverage
ReachedMockReplay == "mockReplaySelected" \in coverage
ReachedHandshakeComplete == "handshakeComplete" \in coverage

\* V1: the decided ValidateUpdate row, observable while the decision is held.
\* persistedParam is the receiver's value (ValidationInputStable).
DecidedRow ==
    ValidateUpdateRow(persistedParam.veh, pendingAbciPresent,
                      pendingParam.veh, pendingBlockHeight)

ReachedRow(r) ==
    /\ phase \in {"updated", "rejected"}
    /\ updatePresent
    /\ ValidateBasicOK(pendingParam)
    /\ DecidedRow = r

ReachedBasicRejection ==
    phase = "rejected" /\ ~ValidateBasicOK(pendingParam)
ReachedVERejection ==
    phase = "rejected" /\ ValidateBasicOK(pendingParam)
ReachedReplayVERejection ==
    ReachedVERejection /\ replayMutatesState

NeverReachedAcceptedUpdate == ~ReachedAcceptedUpdate
NeverReachedRejectedUpdate == ~ReachedRejectedUpdate
NeverReachedCrash == ~ReachedCrash
NeverReachedAppOnlyReplay == ~ReachedAppOnlyReplay
NeverReachedRealReplay == ~ReachedRealReplay
NeverReachedMockReplay == ~ReachedMockReplay
NeverReachedHandshakeComplete == ~ReachedHandshakeComplete
NeverReachedRow1 == ~ReachedRow(1)
NeverReachedRow3 == ~ReachedRow(3)
NeverReachedRow4 == ~ReachedRow(4)
NeverReachedRow5 == ~ReachedRow(5)
NeverReachedRow6 == ~ReachedRow(6)
NeverReachedRow7 == ~ReachedRow(7)
NeverReachedRow8 == ~ReachedRow(8)
NeverReachedRow9 == ~ReachedRow(9)
NeverReachedBasicRejection == ~ReachedBasicRejection
NeverReachedReplayVERejection == ~ReachedReplayVERejection

=============================================================================
