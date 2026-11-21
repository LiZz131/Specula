-------------------------------- MODULE MC ---------------------------------
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
    \/ \E p \in ParamOrNone : MCFinalizeBlock(p)
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
\* verified: base
\* note:     no source evidence searched or expected for a type and bound invariant.
\* review:   ok
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

\* REQ-EVIDENCE NeverReachedAcceptedUpdate
\* intent:   An accepted consensus-parameter update is never reached; this canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    source/internal/state/execution.go:updateState
\* verified: base
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
NeverReachedAcceptedUpdate == ~ReachedAcceptedUpdate
\* REQ-EVIDENCE NeverReachedRejectedUpdate
\* intent:   A rejected consensus-parameter update is never reached; this canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    source/internal/state/execution.go:updateState; source/types/params.go:ConsensusParams.ValidateUpdate
\* verified: base
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
NeverReachedRejectedUpdate == ~ReachedRejectedUpdate
\* REQ-EVIDENCE NeverReachedCrash
\* intent:   A crash is never reached; this canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    none
\* verified: base
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
NeverReachedCrash == ~ReachedCrash
\* REQ-EVIDENCE NeverReachedAppOnlyReplay
\* intent:   An app-only block replay during the handshake is never reached; this canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    source/internal/consensus/replay.go:Handshaker.replayBlocks; source/internal/state/execution.go:ExecCommitBlock
\* verified: base
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
NeverReachedAppOnlyReplay == ~ReachedAppOnlyReplay
\* REQ-EVIDENCE NeverReachedRealReplay
\* intent:   A handshake replay of the last block with the real app is never reached; this canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    source/internal/consensus/replay.go:Handshaker.ReplayBlocks
\* verified: base
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
NeverReachedRealReplay == ~ReachedRealReplay
\* REQ-EVIDENCE NeverReachedMockReplay
\* intent:   A handshake replay of the last block with the mock app is never reached; this canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    source/internal/consensus/replay.go:Handshaker.ReplayBlocks; source/internal/consensus/replay_stubs.go:newMockProxyApp
\* verified: base
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
NeverReachedMockReplay == ~ReachedMockReplay
\* REQ-EVIDENCE NeverReachedHandshakeComplete
\* intent:   A completed handshake is never reached; this canary is expected to be violated, which shows the path is reachable.
\* status:   model-internal
\* watch:    source/internal/consensus/replay.go:Handshaker.Handshake
\* verified: base
\* note:     no source evidence searched or expected for a reachability canary.
\* review:   ok
NeverReachedHandshakeComplete == ~ReachedHandshakeComplete

=============================================================================
