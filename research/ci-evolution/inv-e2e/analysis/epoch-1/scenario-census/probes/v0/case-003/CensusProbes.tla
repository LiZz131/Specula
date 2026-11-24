---- MODULE CensusProbes ----
EXTENDS Update

\* Positive control: an update was accepted (agent canary NeverReachedAcceptedUpdate negated, MC.tla:78,86).
SC_CTRL_accepted == "acceptedUpdate" \in coverage

\* U1: "first enablement must be accepted (fixed halt)" (modeling-brief.md:180)
\* = agent canary NeverEnableFromZeroAccepted negated (Update.tla:161-163)
SC_U1a_enable_from_zero_accepted == persistedParam.veh = 0 /\ UpdatedWith(LAMBDA u : u > H)

\* U1: "does re-sending after enablement still pass?" (modeling-brief.md:180)
\* -> after enablement, an update re-sending the same enable height is validated (accepted or rejected)
SC_U1b_resend_after_enable_validated ==
    /\ phase \in {"updated", "rejected"}
    /\ HasAbci(pendingParam)
    /\ VEEnabled(persistedParam.veh, H)
    /\ pendingParam.abci = persistedParam.veh

\* U2: "app re-sends its unchanged Abci sub-record (full params echo)" ... "rejection = chain halt"
\* (modeling-brief.md:181) = agent canary NeverUnchangedAfterEnableRejected negated (Update.tla:181-184)
SC_U2_unchanged_after_enable_rejected ==
    VEEnabled(persistedParam.veh, H) /\ RejectedUpdate(LAMBDA u : u = persistedParam.veh)

\* U3: "relaxed rule (cancel / move future height) must not change VE status of heights <= H"
\* (modeling-brief.md:182): cancel = NeverCancelFutureAccepted negated (Update.tla:164-166)
SC_U3a_cancel_future_accepted == persistedParam.veh > H /\ UpdatedWith(LAMBDA u : u = 0)
\* move = NeverModifyFutureAccepted negated (Update.tla:167-170)
SC_U3b_move_future_accepted ==
    persistedParam.veh > H /\ UpdatedWith(LAMBDA u : u > H /\ u /= persistedParam.veh)
\* U3: "... nor disable once enabled" (modeling-brief.md:182): a disable attempt after enablement is validated
SC_U3c_disable_after_enable_attempted ==
    /\ phase \in {"updated", "rejected"}
    /\ HasAbci(pendingParam)
    /\ VEEnabled(persistedParam.veh, H)
    /\ pendingParam.abci = 0

\* U4: "real replay re-rejects deterministically" (modeling-brief.md:183)
\* = agent canary NeverRealReplayRejected negated (Update.tla:199-200), restricted to real replay
\* (SelectRealReplay leaves appHeight = stateStoreHeight < pendingBlockHeight, base.tla:363-372)
SC_U4a_real_replay_rejected == phase = "rejected" /\ replayMutatesState /\ appHeight < H
\* U4: "mock replay must re-accept" (modeling-brief.md:183)
\* = agent canary NeverMockReplayRevalidatedVE negated (Update.tla:196-198)
SC_U4b_mock_replay_revalidated ==
    phase = "updated" /\ replayMutatesState /\ appHeight = H /\ HasAbci(pendingParam)
====
