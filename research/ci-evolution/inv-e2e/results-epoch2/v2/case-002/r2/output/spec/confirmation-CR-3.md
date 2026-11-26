# Confirmation CR-3: a proposal ACK can be consumed as the NEWLEADER ACK

- **Source**: code review of the update (Chapter 3 Scenario U4). Not model
  checked: the model's messages are unordered and the property is liveness /
  availability; no model counterexample exists.
- **Revision**: new `2efbdfc` (`repro/work-new`), old control `1414ebf` (`repro/work-old`).
- **Novelty**: NEW in this run's inputs (persistent findings lookup empty).
- **Status**: **REPRODUCED** (level 1 timing assistance only), consequence
  limited to availability; the learners' sync timeout and re-sync bound it.
- **Severity**: Low.

## Mechanism (updated source)

1. At NEWLEADER the learner starts its SyncRequestProcessor and queues the DIFF
   proposals (`quorum/Learner.java:751-757`) before writing the NEWLEADER ACK
   (`:760`). The SyncRequestProcessor fsyncs them on its own thread and its
   `SendAckRequestProcessor` writes `ACK(zxid of the proposal)` on the same
   learner socket.
2. If that proposal ACK is written first, `LearnerHandler.run` reads it as the
   first packet after NEWLEADER, checks only that it is an `ACK`
   (`quorum/LearnerHandler.java:611-621`), and calls
   `waitForNewLeaderAck(sid, proposalZxid)` (`:623`).
3. `Leader.waitForNewLeaderAck` logs "NEWLEADER ACK from sid … is from a
   different epoch" and returns without counting the learner
   (`quorum/Leader.java:1555-1563`). The real NEWLEADER ACK later reaches the
   main loop and `processAck` ignores epoch zxids. The handler then blocks in
   `waitForStartup`, so the learner gets no UPTODATE until its
   `tickTime*syncLimit` read timeout (`Learner.java:749`) makes it reconnect and
   re-sync; if the race repeats, the leader's `initLimit` wait can expire
   ("Timeout while waiting for NEWLEADER to be acked by quorum", `Leader.java:1583`).
4. In the old code nothing was handed to the SyncRequestProcessor before the
   NEWLEADER ACK, so no proposal ACK could precede it.

## Reproduction

Test `repro/NewLeaderAckOrderReproTest.java`, driver
`repro/test_bug3_proposal_ack_before_newleader_ack.sh` (Maven under
`timeout 900s`). Preparation as in `DIFFSyncConsistencyTest` (both learners must
receive a DIFF proposal). Timing assistance: a test-fixture `Follower`
subclass delays the learner thread's first epoch-zxid ACK write of the session
by 1.5 s (a descheduled learner thread); ZooKeeper logic is unchanged.

| revision | runs | rejected NEWLEADER ACKs (leader ERROR log) | leader served after learner restart | result |
|---|---|---|---|---|
| new 2efbdfc | 2 | 2 per run | 23010 ms, 22393 ms | FAIL `NEWLEADER quorum was missed: leader activation took … ms although all learners acked NEWLEADER` |
| old 1414ebf | 1 | 0 | 3782 ms | pass |

Leader log excerpt (new, run 1):

```
07:31:44,158 ERROR [LearnerHandler…:Leader@1557] - NEWLEADER ACK from sid: 1 is from a different epoch - current 0x200000000 received 0x100000002
07:31:44,170 ERROR [LearnerHandler…:Leader@1557] - NEWLEADER ACK from sid: 0 is from a different epoch - current 0x200000000 received 0x100000002
07:32:05,695 INFO  [QuorumPeer…:Leader@1500] - Have quorum of supporters, sids: [[1, 2]]; starting up …
```

Both learners had acked NEWLEADER at 07:31:44; the leader started serving only
21.5 s later, after a learner re-synced. Recommendation: make
`LearnerHandler` wait for the ACK carrying the NEWLEADER zxid and treat earlier
proposal ACKs as ordinary ACKs (instead of consuming the first ACK). This is
also needed by any fix of MC-1 that delays the NEWLEADER ACK until the logged
proposals are durable, because their proposal ACKs would then always precede it.
