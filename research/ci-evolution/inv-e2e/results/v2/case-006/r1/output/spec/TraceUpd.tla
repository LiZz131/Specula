---------------------------- MODULE TraceUpd ----------------------------
(***************************************************************************
 * Trace replay plus the update properties of Update.tla evaluated on every
 * replayed state.  Update.tla is instantiated with dummy MC bounds (its
 * properties read only base variables), so no property is redefined here.
 *************************************************************************)
EXTENDS Trace

U == INSTANCE Update WITH
        faultCounters <- [campaign |-> 0, proposal |-> 0, heartbeat |-> 0,
                          read |-> 0, ready |-> 0, quorumCheck |-> 0,
                          crash |-> 0, lose |-> 0],
        MaxCampaignLimit <- 0, MaxProposalLimit <- 0, MaxHeartbeatLimit <- 0,
        MaxReadLimit <- 0, MaxReadyLimit <- 0, MaxQuorumCheckLimit <- 0,
        MaxCrashLimit <- 0, MaxLoseLimit <- 0, MaxMsgBufferLimit <- 0

TrUpdPendingMatchesQueue == U!UpdPendingMatchesQueue
TrUpdReadStateOnlyAtLeader == U!UpdReadStateOnlyAtLeader
TrUpdReadAckFresh == U!UpdReadAckFresh
TrUpdReadIndexLinearizable == U!UpdReadIndexLinearizable

\* Evidence oracle for a fully consumed trace: a violation is reported only
\* on the final replayed state, after every record was matched.
TrFinalReadAckFresh == TraceDone => TrUpdReadAckFresh
TrFinalReadIndexLinearizable == TraceDone => TrUpdReadIndexLinearizable
\* Non-vacuity of the separating state: the final state carries published
\* reads (ReadDeliveryJustified quantifies over them) and served records.
TrFinalRecordsNonEmpty ==
    TraceDone => (Len(publishedReads) >= 2 /\ Cardinality(servedReads) >= 2)
=============================================================================
