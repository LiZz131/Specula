# Confirmation: CR-1 — COMMIT between NEWLEADER and UPTODATE crashes the learner (NPE)

- **Source**: Code Review (no model counterexample; exception/liveness behaviour is below the model's safety granularity)
- **Novelty**: not determined (history/issue search prohibited by the blindness contract)
- **Status**: REPRODUCED (Level 0: legitimate leader packet order, no delays or injection)
- **Severity**: Medium (availability: the learner abandons synchronization and must re-elect/re-sync; introduced by the update)
- **Location**: `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:645-647` (dereference) with `:757` (new `packetsNotCommitted.clear()`)
- **Source revision**: `artifact/` HEAD 2efbdfc (update); old control `controls/old-pristine` (files identical to `/work/old-source`)

## Description
The update clears `packetsNotCommitted` after handing it to `logRequest` at NEWLEADER. The leader queues NEWLEADER
only after `syncFollower` -> `startForwarding` (`LearnerHandler.java:551,596-599`), so a PROPOSAL forwarded before
NEWLEADER can be followed by its COMMIT after NEWLEADER and before UPTODATE (UPTODATE is queued only after the
learner's NEWLEADER ACK is processed and the leader runs, `LearnerHandler.java:623-648`). The COMMIT case executes
`pif = packetsNotCommitted.peekFirst(); if (pif.hdr.getZxid() == ...)` with `pif == null`.

## Trigger
Learner registers; leader sends DIFF, PROPOSAL(0x100000001), NEWLEADER, then COMMIT(0x100000001), UPTODATE.

## Reproduction
Test `harness/repro/CommitAfterNewLeaderReproTest.java` (fake-leader conversation of the existing `Zab1_0Test`
harness, real `Follower`/`Learner` code); driver `harness/repro/test_bug2_commit_after_newleader.sh <label> <tree>`
(`timeout 600s mvn -B -pl zookeeper-server ... -Dtest=CommitAfterNewLeaderReproTest#testCommitForwardedBetweenNewLeaderAndUptodate test`).

| Tree | Result | Evidence |
|---|---|---|
| updated `artifact/` | FAIL (bug): learner closes the connection after the COMMIT | `spec/output/incr/repro/repro2-new.log`, `repro2-new-markers.txt` |
| old revision `controls/old-pristine` | PASS: UPTODATE ACK 0x100000000, txn 0x100000001 applied | `spec/output/incr/repro/repro2-old.log`, `repro2-old-markers.txt` |

Updated-tree output:
```
REPRO-CR1: NEWLEADER ACK received
WARN [Thread-0:Follower@131] - Exception when following the leader
java.lang.NullPointerException: Cannot read field "hdr" because "pif" is null
	at org.apache.zookeeper.server.quorum.Learner.syncWithLeader(Learner.java:646)
REPRO-CR1: learner connection closed after COMMIT/UPTODATE: java.io.EOFException
```
Old-tree output: `REPRO-CR1: UPTODATE ACK type=3 zxid=0x100000000`, `learner lastProcessedZxid=0x100000001`.

## Attribution
Introduced by the update (the old code kept the buffer until after UPTODATE).

## Recommendation
Keep handed-off proposals matchable for later COMMITs (do not clear the deque, or record them as already logged
and route a later COMMIT to `packetsCommitted` without dereferencing a null head).

Full JUnit outputs: `spec/output/incr/repro/surefire/repro2-{new,old}-*-output.txt`.
