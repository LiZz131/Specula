| # | inferred step | consumed | produced | notable post-state |
|---|---|---|---|---|
| 2 | Campaign(s1) |  | MsgVote s1->s2 t1; MsgVote s1->s3 t1 | s1: term 1 Candidate |
| 3 | ReadyPublish(s1) |  |  |  |
| 4 | ReadyAdvance(s1) |  |  |  |
| 5 | HandleVoteRequest(s2) | MsgVote s1->s2 t1 | MsgVoteResp s2->s1 t1 | s2: term 1 Follower |
| 6 | HandleVoteRequest(s3) | MsgVote s1->s3 t1 | MsgVoteResp s3->s1 t1 | s3: term 1 Follower |
| 7 | ReadyPublish(s2) |  |  |  |
| 8 | HandleVoteResponse(s1) | MsgVoteResp s2->s1 t1 |  |  |
| 9 | BecomeLeader(s1) |  | MsgApp s1->s2 t1 i0 e1 c0; MsgApp s1->s3 t1 i0 e1 c0 | s1: term 1 Leader |
| 10 | ReadyPublish(s1) |  |  |  |
| 11 | ReadyAdvance(s1) |  |  |  |
| 12 | HandleAppendEntries(s3) | MsgApp s1->s3 t1 i0 e1 c0 | MsgAppResp s3->s1 t1 i1 |  |
| 13 | ReadyPublish(s3) |  |  |  |
| 14 | HandleAppendResponse(s1) | MsgAppResp s3->s1 t1 i1 |  | s1: commit 1; commitHistory [1] |
| 15 | ClientReadIndex(s1) |  | MsgHeartbeat s1->s2 t1 c0 ctx=ctx1; MsgHeartbeat s1->s3 t1 c1 ctx=ctx1 | s1: queue ['ctx1']; s1: pending[ctx1] active idx=1 stamp=1 acks=[] gcommit=1; readStamp 1 |
| 16 | HandleHeartbeat(s2) | MsgHeartbeat s1->s2 t1 c0 ctx=ctx1 | MsgHeartbeatResp s2->s1 t1 ctx=ctx1 gstamp=1 |  |
| 17 | HandleHeartbeatResponse(s1) | MsgHeartbeatResp s2->s1 t1 ctx=ctx1 gstamp=1 | MsgReadIndexResp s1->s2 t1 ctx=ctx1 idx=1 | s1: queue []; s1: pending[ctx1] freed; served s1@t1 ctx=ctx1 index=1 acks=['s1', 's2'] freshAcks=['s1', 's2'] gcommit=1 |
| 18 | ReadyPublish(s1) |  |  |  |
| 19 | HandleHeartbeat(s3) | MsgHeartbeat s1->s3 t1 c1 ctx=ctx1 | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 | s3: commit 1 |
| 20 | ClientReadIndex(s1) |  | MsgHeartbeat s1->s2 t1 c0 ctx=ctx1; MsgHeartbeat s1->s3 t1 c1 ctx=ctx1 | s1: queue ['ctx1']; s1: pending[ctx1] active idx=1 stamp=2 acks=[] gcommit=1; readStamp 2 |
| 21 | HandleHeartbeatResponse(s1) | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 |  | s1: queue []; s1: pending[ctx1] freed; served s1@t1 ctx=ctx1 index=1 acks=['s1', 's3'] freshAcks=['s1'] gcommit=1 |
