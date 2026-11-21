-------------------------------- MODULE MC ---------------------------------
(* V1: wrappers over the updated reference base.tla.  UpdateStateRejected is
   parameterized by the failing validation stage (execution.go:617-625). *)
EXTENDS base

CONSTANTS MaxBlocks, MaxCrashes, MaxAppRollbacks

VARIABLE counters

mcVars == <<vars, counters>>

\* The TLC cfg parser does not accept negative literals; cfgs substitute this
\* domain (includes -1 to exercise ValidateBasic's negative check,
\* types/params.go:188-190) with  VEHValues <- MCVEHValuesWithNegative.
MCVEHValuesWithNegative == {-1, 0, 1, 2, 3}

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
MCUpdateStateRejected(s) == UpdateStateRejected(s) /\ UNCHANGED counters
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
    \/ \E p \in UpdateOrNone : MCFinalizeBlock(p)
    \/ MCSaveFinalizeBlockResponse
    \/ MCUpdateStateAccepted
    \/ \E s \in RejectStages : MCUpdateStateRejected(s)
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

MCTypeOK ==
    /\ TypeOK
    /\ counters \in [blocks : 0..MaxBlocks,
                      crashes : 0..MaxCrashes,
                      appRollbacks : 0..MaxAppRollbacks]

ReachedAcceptedUpdate == "acceptedUpdate" \in coverage
ReachedRejectedUpdate == "rejectedUpdate" \in coverage
ReachedCrash == "crashed" \in coverage
ReachedAppOnlyReplay == "appOnlyReplay" \in coverage
ReachedRealReplay == "realReplaySelected" \in coverage
ReachedMockReplay == "mockReplaySelected" \in coverage
ReachedHandshakeComplete == "handshakeComplete" \in coverage

NeverReachedAcceptedUpdate == ~ReachedAcceptedUpdate
NeverReachedRejectedUpdate == ~ReachedRejectedUpdate
NeverReachedCrash == ~ReachedCrash
NeverReachedAppOnlyReplay == ~ReachedAppOnlyReplay
NeverReachedRealReplay == ~ReachedRealReplay
NeverReachedMockReplay == ~ReachedMockReplay
NeverReachedHandshakeComplete == ~ReachedHandshakeComplete

=============================================================================
