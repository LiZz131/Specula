---- MODULE PathCheck ----
\* Diagnostic only: drive MCSpec along a hand-derived S6b schedule, one MC
\* wrapper per step, to locate which guard blocks it.  Not a campaign.
EXTENDS Update
CONSTANTS s1, s2, s3, ctx1
VARIABLE pc
HB(f, t) == CHOOSE m \in messages : m.mtype = MsgHeartbeat /\ m.from = f /\ m.to = t
HBR(f, t) == CHOOSE m \in messages : m.mtype = MsgHeartbeatResp /\ m.from = f /\ m.to = t
M(ty, f, t) == CHOOSE m \in messages : m.mtype = ty /\ m.from = f /\ m.to = t
Has(ty, f, t) == \E m \in messages : m.mtype = ty /\ m.from = f /\ m.to = t
Step(k) ==
  CASE k = 1 -> MCCampaign(s1)
    [] k = 2 -> MCReadyPublish(s1)
    [] k = 3 -> MCHandleVoteRequest(s2, M(MsgVote, s1, s2))
    [] k = 4 -> MCReadyAdvance(s1)
    [] k = 5 -> MCReadyPublish(s2)
    [] k = 6 -> MCHandleVoteResponse(s1, M(MsgVoteResp, s2, s1))
    [] k = 7 -> MCBecomeLeader(s1)
    [] k = 8 -> MCReadyAdvance(s2)
    [] k = 9 -> MCReadyPublish(s1)
    [] k = 10 -> MCHandleAppendEntries(s2, M(MsgApp, s1, s2))
    [] k = 11 -> MCHandleAppendEntries(s3, M(MsgApp, s1, s3))
    [] k = 12 -> MCReadyAdvance(s1)
    [] k = 13 -> MCReadyPublish(s2)
    [] k = 14 -> MCHandleAppendResponse(s1, M(MsgAppResp, s2, s1))
    [] k = 15 -> MCClientReadIndex(s1, ctx1, s1)
    [] k = 16 -> MCReadyAdvance(s2)
    [] k = 17 -> MCReadyPublish(s1)
    [] k = 18 -> MCHandleHeartbeat(s2, HB(s1, s2))
    [] k = 19 -> MCHandleHeartbeat(s3, HB(s1, s3))
    [] k = 20 -> MCReadyAdvance(s1)
    [] k = 21 -> MCReadyPublish(s3)
    [] k = 22 -> MCHandleHeartbeatResponse(s1, HBR(s3, s1))
    [] k = 23 -> MCCampaign(s2)
    [] k = 24 -> MCReadyAdvance(s3)
    [] k = 25 -> MCReadyPublish(s2)
    [] k = 26 -> MCHandleVoteRequest(s3, M(MsgVote, s2, s3))
    [] k = 27 -> MCReadyAdvance(s2)
    [] k = 28 -> MCReadyPublish(s3)
    [] k = 29 -> MCHandleVoteResponse(s2, M(MsgVoteResp, s3, s2))
    [] k = 30 -> MCBecomeLeader(s2)
    [] k = 31 -> MCReadyAdvance(s3)
    [] k = 32 -> MCReadyPublish(s2)
    [] k = 33 -> MCHandleAppendEntries(s3, M(MsgApp, s2, s3))
    [] k = 34 -> MCReadyAdvance(s2)
    [] k = 35 -> MCReadyPublish(s3)
    [] k = 36 -> MCHandleAppendResponse(s2, M(MsgAppResp, s3, s2))
    [] k = 37 -> MCClientReadIndex(s1, ctx1, s1)
    [] k = 38 -> MCHandleHeartbeatResponse(s1, HBR(s2, s1))
    [] OTHER -> FALSE
PathInit == MCInit /\ pc = 1
PathNext == /\ Cardinality(messages) <= MaxMsgBufferLimit
            /\ Step(pc) /\ pc' = pc + 1
PathSpec == PathInit /\ [][PathNext]_<<mcVars, pc>>
PathDone == pc < 39
====
