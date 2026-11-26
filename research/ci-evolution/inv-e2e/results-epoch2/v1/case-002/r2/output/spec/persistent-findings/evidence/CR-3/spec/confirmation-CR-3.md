# Confirmation: CR-3 — a SyncThread txn ACK can overtake the NEWLEADER ACK

- **Source**: Code Review (no model counterexample; message-type confusion below model granularity)
- **Novelty**: not determined (history/issue search prohibited by the blindness contract)
- **Status**: REPRODUCED (Level 1: the learner thread is descheduled 500 ms before writing its NEWLEADER ACK; no
  logic changed)
- **Severity**: Medium (availability: the leader cannot count the affected learners toward the NEWLEADER quorum and
  waits until its init limit; introduced by the update)
- **Location**: `Learner.java:751-760` (processors started and txns handed off before the ACK),
  `LearnerHandler.java:611-623` (first ACK after NEWLEADER is taken as the NEWLEADER ACK),
  `Leader.java:1555-1563` (rejects a non-matching zxid)

## Description
Because SyncRequestProcessor and SendAckRequestProcessor now run during synchronization, SyncThread can flush a
handed-off txn and write its per-txn ACK before the learner thread writes the NEWLEADER ACK (writes are serialized
only by `leaderOs`). `LearnerHandler` passes the first ACK's zxid to `waitForNewLeaderAck`, which logs
"NEWLEADER ACK ... is from a different epoch" and does not count it; the real NEWLEADER ACK later reaches
`processAck`, which ignores counter-0 zxids.

## Reproduction
Test `harness/repro/NewLeaderAckOrderReproTest.java`, driver `harness/repro/test_bug3_newleader_ack_order.sh`
(`ACK_DELAY_MS` default 500). Same 3-server setup as MC-1 (leader logs `/zk<L>` while followers are down; followers
DIFF-sync it).

| Tree | Result | Evidence |
|---|---|---|
| updated `artifact/` | FAIL (bug): leader does not serve within 15 s after both NEWLEADER ACKs | `spec/output/incr/repro/repro3-new.log`, `repro3-new-markers.txt` |
| old revision `controls/old-pristine` | PASS: leader serves | `spec/output/incr/repro/repro3-old.log`, `repro3-old-markers.txt` |

Updated-tree output:
```
REPRO-CR3: server 0 writes NEWLEADER ACK 0x200000000 after txn ACKs up to 0x100000002
REPRO-CR3: server 1 writes NEWLEADER ACK 0x200000000 after txn ACKs up to 0x100000002
ERROR [LearnerHandler-...:Leader@1557] - NEWLEADER ACK from sid: 0 is from a different epoch - current 0x200000000 received 0x100000002
ERROR [LearnerHandler-...:Leader@1557] - NEWLEADER ACK from sid: 1 is from a different epoch - current 0x200000000 received 0x100000002
REPRO-CR3: leader served /zk2 within 15s after both NEWLEADER ACKs: false
```
Level 0 was not separately attempted: without descheduling, the learner thread normally writes the ACK within
microseconds of `logRequest`, while SyncThread needs an append and fsync; the Level-1 delay models a GC/scheduling
pause of the learner thread longer than one fsync.

## Recommendation
Send the NEWLEADER ACK before any per-txn ACK can be emitted (e.g. emit it from SyncThread after the flush, which
also fixes MC-1), or make `LearnerHandler` skip per-txn ACKs while waiting for the NEWLEADER ACK.

Full JUnit outputs: `spec/output/incr/repro/surefire/repro3-{new,old}-*-output.txt`.
