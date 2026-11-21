| # | inferred step | consumed | produced | notable post-state |
|---|---|---|---|---|
| 2 | Crash/EnvCrashRestart(s3) |  |  |  |
| 3 | Campaign(s2) |  | MsgVote s2->s1 t1; MsgVote s2->s3 t1 | s2: term 1 Candidate |
| 4 | LoseMessage | MsgVote s2->s3 t1 |  |  |
| 5 | Campaign(s2) |  | MsgVote s2->s1 t2; MsgVote s2->s3 t2 | s2: term 2 Candidate |
| 6 | ReadyPublish(s2) |  |  |  |
| 7 | HandleVoteRequest(s1) | MsgVote s2->s1 t2 | MsgVoteResp s1->s2 t2 | s1: term 2 Follower |
| 8 | ReadyPublish(s1) |  |  |  |
| 9 | HandleVoteRequest(s1) | MsgVote s2->s1 t1 | MsgVoteResp s1->s2 t2 rej |  |
| 10 | Restart(s3) |  |  |  |
| 11 | HandleVoteResponse(s2) | MsgVoteResp s1->s2 t2 rej |  |  |
| 12 | ReadyAdvance(s2) |  |  |  |
| 13 | ReadyAdvance(s1) |  |  |  |
| 14 | HandleVoteResponse(s2) | MsgVoteResp s1->s2 t2 |  |  |
| 15 | HandleVoteRequest(s3) | MsgVote s2->s3 t2 | MsgVoteResp s3->s2 t2 | s3: term 2 Follower |
| 16 | ReadyPublish(s3) |  |  |  |
| 17 | HandleVoteResponse(s2) | MsgVoteResp s3->s2 t2 |  |  |
| 18 | ReadyAdvance(s3) |  |  |  |
| 19 | BecomeLeader(s2) |  | MsgApp s2->s1 t2 i0 e2 c0; MsgApp s2->s3 t2 i0 e2 c0 | s2: term 2 Leader |
| 20 | ReadyPublish(s2) |  |  |  |
| 21 | ReadyAdvance(s2) |  |  |  |
| 22 | HandleAppendEntries(s3) | MsgApp s2->s3 t2 i0 e2 c0 | MsgAppResp s3->s2 t2 i1 |  |
| 23 | ForwardReadIndex(s3) |  | MsgReadIndex s3->s2 t0 ctx=ctx1 idx=0 |  |
| 24 | ReadyPublish(s3) |  |  |  |
| 25 | HandleAppendResponse(s2) | MsgAppResp s3->s2 t2 i1 |  | s2: commit 1; commitHistory [1] |
| 26 | HandleAppendEntries(s1) | MsgApp s2->s1 t2 i0 e2 c0 | MsgAppResp s1->s2 t2 i1 |  |
| 27 | ClientReadIndex(s2) |  | MsgHeartbeat s2->s1 t2 c0 ctx=ctx1; MsgHeartbeat s2->s3 t2 c1 ctx=ctx1 | s2: queue ['ctx1']; s2: pending[ctx1] active idx=1 stamp=1 acks=[] gcommit=1; readStamp 1 |
| 28 | HandleHeartbeat(s1) | MsgHeartbeat s2->s1 t2 c0 ctx=ctx1 | MsgHeartbeatResp s1->s2 t2 ctx=ctx1 gstamp=1 |  |
| 29 | CheckQuorum(?) |  |  |  |
| 30 | ClientProposal(s2) |  | MsgApp s2->s1 t2 i1 e2 c1; MsgApp s2->s3 t2 i1 e2 c1 |  |
| 31 | ReadyPublish(s2) |  |  |  |
| 32 | HandleHeartbeat(s3) | MsgHeartbeat s2->s3 t2 c1 ctx=ctx1 | MsgHeartbeatResp s3->s2 t2 ctx=ctx1 gstamp=1 | s3: commit 1 |
| 33 | HandleHeartbeatResponse(s2) | MsgHeartbeatResp s1->s2 t2 ctx=ctx1 gstamp=1 |  | s2: queue []; s2: pending[ctx1] freed; served s2@t2 ctx=ctx1 index=1 acks=['s1', 's2'] freshAcks=['s1', 's2'] gcommit=1 |
| 34 | ReadyAdvance(s3) |  |  |  |
| 35 | ReadyAdvance(s2) |  |  |  |
| 36 | HandleAppendEntries(s1) | MsgApp s2->s1 t2 i1 e2 c1 | MsgAppResp s1->s2 t2 i2 | s1: commit 1 |
| 37 | ReadyPublish(s3) |  |  |  |
| 38 | ReadyPublish(s2) |  |  |  |
| 39 | ReadyAdvance(s3) |  |  |  |
| 40 | HandleAppendEntries(s3) | MsgApp s2->s3 t2 i1 e2 c1 | MsgAppResp s3->s2 t2 i2 |  |
| 41 | ReadyAdvance(s2) |  |  |  |
| 42 | ReadyPublish(s1) |  |  |  |
| 43 | BroadcastHeartbeat(s2) |  | MsgHeartbeat s2->s1 t2 c0 ctx=Nil; MsgHeartbeat s2->s3 t2 c1 ctx=Nil |  |
| 44 | HandleAppendResponse(s2) | MsgAppResp s1->s2 t2 i1 |  |  |
| 45 | ReadyPublish(s3) |  |  |  |
| 46 | HandleReadIndexRequest(s2) | MsgReadIndex s3->s2 t0 ctx=ctx1 idx=0 | MsgHeartbeat s2->s1 t2 c1 ctx=ctx1; MsgHeartbeat s2->s3 t2 c1 ctx=ctx1 | s2: queue ['ctx1']; s2: pending[ctx1] active idx=1 stamp=2 acks=[] gcommit=1; readStamp 2 |
| 47 | HandleHeartbeatResponse(s2) | MsgHeartbeatResp s3->s2 t2 ctx=ctx1 gstamp=1 | MsgReadIndexResp s2->s3 t2 ctx=ctx1 idx=1 | s2: queue []; s2: pending[ctx1] freed; served s2@t2 ctx=ctx1 index=1 acks=['s2', 's3'] freshAcks=['s2'] gcommit=1 |
