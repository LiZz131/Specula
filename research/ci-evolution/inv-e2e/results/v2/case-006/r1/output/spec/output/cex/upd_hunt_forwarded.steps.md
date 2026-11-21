| # | inferred step | consumed | produced | notable post-state |
|---|---|---|---|---|
| 2 | Campaign(s1) |  | MsgVote s1->s2 t1; MsgVote s1->s3 t1 | s1: term 1 Candidate |
| 3 | LoseMessage | MsgVote s1->s2 t1 |  |  |
| 4 | ReadyPublish(s1) |  |  |  |
| 5 | ReadyAdvance(s1) |  |  |  |
| 6 | HandleVoteRequest(s3) | MsgVote s1->s3 t1 | MsgVoteResp s3->s1 t1 | s3: term 1 Follower |
| 7 | ReadyPublish(s3) |  |  |  |
| 8 | HandleVoteResponse(s1) | MsgVoteResp s3->s1 t1 |  |  |
| 9 | BecomeLeader(s1) |  | MsgApp s1->s2 t1 i0 e1 c0; MsgApp s1->s3 t1 i0 e1 c0 | s1: term 1 Leader |
| 10 | ReadyPublish(s1) |  |  |  |
| 11 | HandleAppendEntries(s2) | MsgApp s1->s2 t1 i0 e1 c0 | MsgAppResp s2->s1 t1 i1 | s2: term 1 Follower |
| 12 | ReadyPublish(s2) |  |  |  |
| 13 | HandleAppendResponse(s1) | MsgAppResp s2->s1 t1 i1 |  | s1: commit 1; commitHistory [1] |
| 14 | ClientReadIndex(s1) |  | MsgHeartbeat s1->s3 t1 c0 ctx=ctx1; MsgHeartbeat s1->s2 t1 c1 ctx=ctx1 | s1: queue ['ctx1']; s1: pending[ctx1] active idx=1 stamp=1 acks=[] gcommit=1; readStamp 1 |
| 15 | HandleHeartbeat(s3) | MsgHeartbeat s1->s3 t1 c0 ctx=ctx1 | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 |  |
| 16 | ClientReadIndex(s1) |  | MsgHeartbeat s1->s3 t1 c0 ctx=ctx1 |  |
| 17 | HandleHeartbeatResponse(s1) | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 |  | s1: queue []; s1: pending[ctx1] freed; served s1@t1 ctx=ctx1 index=1 acks=['s1', 's3'] freshAcks=['s1', 's3'] gcommit=1 |
| 18 | HandleHeartbeat(s3) | MsgHeartbeat s1->s3 t1 c0 ctx=ctx1 | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 |  |
| 19 | ClientReadIndex(s1) |  | MsgHeartbeat s1->s3 t1 c0 ctx=ctx1 | s1: queue ['ctx1']; s1: pending[ctx1] active idx=1 stamp=2 acks=[] gcommit=1; readStamp 2 |
| 20 | HandleHeartbeatResponse(s1) | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 |  | s1: queue []; s1: pending[ctx1] freed; served s1@t1 ctx=ctx1 index=1 acks=['s1', 's3'] freshAcks=['s1'] gcommit=1 |
