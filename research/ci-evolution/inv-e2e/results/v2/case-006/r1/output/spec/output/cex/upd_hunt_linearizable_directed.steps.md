| # | inferred step | consumed | produced | notable post-state |
|---|---|---|---|---|
| 2 | Campaign(s1) |  | MsgVote s1->s2 t1; MsgVote s1->s3 t1 | s1: term 1 Candidate |
| 3 | ReadyPublish(s1) |  |  |  |
| 4 | HandleVoteRequest(s2) | MsgVote s1->s2 t1 | MsgVoteResp s2->s1 t1 | s2: term 1 Follower |
| 5 | ReadyPublish(s2) |  |  |  |
| 6 | HandleVoteResponse(s1) | MsgVoteResp s2->s1 t1 |  |  |
| 7 | ReadyAdvance(s1) |  |  |  |
| 8 | BecomeLeader(s1) |  | MsgApp s1->s2 t1 i0 e1 c0; MsgApp s1->s3 t1 i0 e1 c0 | s1: term 1 Leader |
| 9 | ReadyPublish(s1) |  |  |  |
| 10 | HandleAppendEntries(s2) | MsgApp s1->s2 t1 i0 e1 c0 | MsgAppResp s2->s1 t1 i1 |  |
| 11 | HandleAppendEntries(s3) | MsgApp s1->s3 t1 i0 e1 c0 | MsgAppResp s3->s1 t1 i1 | s3: term 1 Follower |
| 12 | ReadyPublish(s3) |  |  |  |
| 13 | HandleAppendResponse(s1) | MsgAppResp s3->s1 t1 i1 |  | s1: commit 1; commitHistory [1] |
| 14 | ClientReadIndex(s1) |  | MsgHeartbeat s1->s2 t1 c0 ctx=ctx1; MsgHeartbeat s1->s3 t1 c1 ctx=ctx1 | s1: queue ['ctx1']; s1: pending[ctx1] active idx=1 stamp=1 acks=[] gcommit=1; readStamp 1 |
| 15 | HandleHeartbeat(s2) | MsgHeartbeat s1->s2 t1 c0 ctx=ctx1 | MsgHeartbeatResp s2->s1 t1 ctx=ctx1 gstamp=1 |  |
| 16 | HandleHeartbeatResponse(s1) | MsgHeartbeatResp s2->s1 t1 ctx=ctx1 gstamp=1 |  | s1: queue []; s1: pending[ctx1] freed; served s1@t1 ctx=ctx1 index=1 acks=['s1', 's2'] freshAcks=['s1', 's2'] gcommit=1 |
| 17 | Campaign(s2) |  | MsgVote s2->s1 t2; MsgVote s2->s3 t2 | s2: term 2 Candidate |
| 18 | ReadyAdvance(s1) |  |  |  |
| 19 | ReadyPublish(s1) |  |  |  |
| 20 | HandleHeartbeat(s3) | MsgHeartbeat s1->s3 t1 c1 ctx=ctx1 | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 | s3: commit 1 |
| 21 | ReadyAdvance(s2) |  |  |  |
| 22 | ReadyAdvance(s3) |  |  |  |
| 23 | ReadyPublish(s2) |  |  |  |
| 24 | HandleVoteRequest(s3) | MsgVote s2->s3 t2 | MsgVoteResp s3->s2 t2 | s3: term 2 Follower |
| 25 | ReadyPublish(s3) |  |  |  |
| 26 | ReadyAdvance(s2) |  |  |  |
| 27 | HandleVoteResponse(s2) | MsgVoteResp s3->s2 t2 |  |  |
| 28 | ReadyAdvance(s3) |  |  |  |
| 29 | BecomeLeader(s2) |  | MsgApp s2->s1 t2 i1 e2 c0; MsgApp s2->s3 t2 i1 e2 c0 | s2: term 2 Leader |
| 30 | ReadyPublish(s2) |  |  |  |
| 31 | HandleAppendEntries(s3) | MsgApp s2->s3 t2 i1 e2 c0 | MsgAppResp s3->s2 t2 i2 |  |
| 32 | ReadyPublish(s3) |  |  |  |
| 33 | HandleAppendResponse(s2) | MsgAppResp s3->s2 t2 i2 |  | s2: commit 2; commitHistory [1, 1, 2] |
| 34 | ClientReadIndex(s1) |  | MsgHeartbeat s1->s2 t1 c0 ctx=ctx1; MsgHeartbeat s1->s3 t1 c1 ctx=ctx1 | s1: queue ['ctx1']; s1: pending[ctx1] active idx=1 stamp=2 acks=[] gcommit=2; readStamp 2 |
| 35 | HandleHeartbeatResponse(s1) | MsgHeartbeatResp s3->s1 t1 ctx=ctx1 gstamp=1 |  | s1: queue []; s1: pending[ctx1] freed; served s1@t1 ctx=ctx1 index=1 acks=['s1', 's3'] freshAcks=['s1'] gcommit=2 |
