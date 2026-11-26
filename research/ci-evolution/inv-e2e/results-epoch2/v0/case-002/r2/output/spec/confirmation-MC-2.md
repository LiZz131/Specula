# Confirmation MC-2 — proposal ACK consumed as the NEWLEADER ACK

- **Source**: MC (`spec/output/update-focused-bfs.log` 10 states;
  full MCNext `spec/output/update-hunt-ackorder-sim.log` 58 states)
- **Novelty**: not searched (blind run: issue/history research prohibited)
- **Status**: REPRODUCED
- **Severity**: High (epoch establishment fails and is retried; proposal ACKs of
  an established leader can be silently dropped)
- **Update attribution**: introduced by the update (old-tree control passes).
- **Location**: `quorum/Learner.java:751-760` (pipeline started before the
  NEWLEADER ACK), `quorum/SendAckRequestProcessor.java:40-59`,
  `quorum/LearnerHandler.java:609-623`, `quorum/Leader.java:1547-1588`.

## Investigation

`zk.startupWithoutServing()` starts SyncRequestProcessor -> SendAckRequestProcessor
(`FollowerZooKeeperServer.setupRequestProcessors:70-78`); the buffered proposals
are then enqueued (`Learner.java:752-756`).  The SyncThread can append, force and
write `ACK(zxid)` through the shared `Learner.writePacket` before the learner
thread executes `writePacket(ACK(newLeaderZxid))` (`:760`) — any scheduling delay
of the learner thread suffices, and a DIFF larger than the SyncRequestProcessor
batch makes it likely.  `LearnerHandler.run:609-623` reads the first packet,
requires only `type == ACK`, and calls `waitForNewLeaderAck(sid, zxid)`, which
for a mismatching zxid logs "is from a different epoch" and returns without
counting the learner (`Leader.java:1553-1560`).  The later real NEWLEADER ACK is
handled by `processAck`, which ignores zero-counter zxids.  Old code starts the
pipeline only after UPTODATE, so no ACK can precede the NEWLEADER ACK.
Real-execution evidence: `traces/diff-ack-before-newleader-ack.ndjson` seq 13-16
(`AckSent` (1,1) before `NewLeaderAckSent`).

## Reproduction

1. `harness/repro/test_bugMC-2_ackorder_fixture.sh` — test-side leader, Level 1
   (1.5 s delay immediately before the learner's NEWLEADER-ACK write).
   New (`spec/output/repro-ackorder-fixture-new*`):
   ```
   SPECULAR-OBSERVATION first packet after NEWLEADER type=3 zxid=0x100000001
   first ACK after NEWLEADER is not the NEWLEADER ACK (LearnerHandler would discard it) ==> expected: <4294967296> but was: <4294967297>
   ```
   Old control: `first packet after NEWLEADER type=3 zxid=0x100000000`, test passes.
2. `harness/repro/test_bugMC-2_ackorder_cluster.sh` — real 3-peer ensemble,
   Level 1 (3 s delay before each follower's NEWLEADER-ACK write), DIFF of one
   entry into a new epoch.  New (`spec/output/repro-ackorder-cluster-new*`):
   ```
   ERROR [LearnerHandler-...:Leader@1557] - NEWLEADER ACK from sid: 0 is from a different epoch - current 0x200000000 received 0x100000002
   ERROR [LearnerHandler-...:Leader@1557] - NEWLEADER ACK from sid: 1 is from a different epoch - current 0x200000000 received 0x100000002
   (repeated for both followers in the next election round)
   SPECULAR-OBSERVATION served=false after 26591 ms; leader currentEpoch=2 acceptedEpoch=2
   re-elected leader did not establish its epoch within 25 s ==> expected: <true> but was: <false>
   ```
   Old control: `served=true after 4237 ms`, test passes (same 3 s delay).

The repeated failure in the second round also involves CR-4 (the learner that
failed between NEWLEADER and UPTODATE keeps a stale data-tree position, so it is
DIFF-synced the same entry again).

## Recommendation

Write the NEWLEADER ACK before starting the learner pipeline (or hold
SendAckRequestProcessor output until it is written), or make LearnerHandler skip
proposal ACKs while waiting for the NEWLEADER ACK.
