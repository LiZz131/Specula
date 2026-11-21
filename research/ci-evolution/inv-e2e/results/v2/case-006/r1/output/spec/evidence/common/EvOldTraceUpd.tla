--------------------------- MODULE EvOldTraceUpd ---------------------------
(* Evidence E1: replay an exact-old implementation trace on the exact-old
   (V0) model and evaluate the update property UpdPendingMatchesQueue from
   the current Update.tla on every replayed state.  The property reads only
   pendingReads[i][c].active and readQueue, which have the same meaning in
   both models; the new ghost variables are substituted by their initial
   values (unused by this property). *)
EXTENDS OldTrace
U == INSTANCE Update WITH
        readStamp <- 0, servedReads <- {},
        faultCounters <- [campaign |-> 0, proposal |-> 0, heartbeat |-> 0,
                          read |-> 0, ready |-> 0, quorumCheck |-> 0,
                          crash |-> 0, lose |-> 0],
        MaxCampaignLimit <- 0, MaxProposalLimit <- 0, MaxHeartbeatLimit <- 0,
        MaxReadLimit <- 0, MaxReadyLimit <- 0, MaxQuorumCheckLimit <- 0,
        MaxCrashLimit <- 0, MaxLoseLimit <- 0, MaxMsgBufferLimit <- 0
EvUpdPendingMatchesQueue == U!UpdPendingMatchesQueue
=============================================================================
