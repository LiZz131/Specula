# Confirmation MC-1 — NEWLEADER ACK written before the synced transactions are durable

- Status: **REPRODUCED** (fault-injected: stalled log until process restart, equivalent on disk to a learner crash before the SyncRequestProcessor flush)
- Source revision: `artifact/` commit 2efbdfc ("update"); old control: commit 1414ebf ("baseline") in `harness/old-control-source/`.
- Model: `spec/output/cex/MC-1_*.out` (P2 2-server hunt, 27 states; P1 full MCNext, 20 states; P2 full-MCNext simulation, 55 states; P3 crash consequence, 42 states).

## Code path
`Learner.syncWithLeader` NEWLEADER branch (`quorum/Learner.java:743-760`):
`self.setCurrentEpoch(newEpoch)` → `zk.startupWithoutServing()` →
`fzk.logRequest(...)` for each `packetsNotCommitted` entry
(`FollowerZooKeeperServer.java:82-89`: `pendingTxns.add` + `syncProcessor.processRequest`,
an enqueue, `SyncRequestProcessor.java:273-278`) → `writePacket(ACK newLeaderZxid, true)`.
Append and force happen later on `SyncThread` (`SyncRequestProcessor.java:156-252`).
The leader counts the ACK (`Leader.java:1547-1572`) and starts serving its loaded
history (`Leader.java:663-712`).

## Observations on the real implementation (no fault injection)
- `traces/follower-diff.ndjson` line 10, `follower-diff-bulk-r1..r3` (7 txns),
  `observation-only/follower-diff-bigdiff-r1` (1500 txns): `NewLeaderAckSent.update.fsyncedZxidAtAck = 0`
  with all logged txns queued; first DIFF fsync after UPTODATE.
- `traces/diff-sync-uptodate-failure.ndjson` lines 87-91, 104-106: s0/s1 ACK epoch 2
  with (1,2) queued and (1,1) fsynced; leader s2 enters BROADCAST (line 91) while
  (1,2) is durable only on s2.
- TLC evaluation of the update properties on these replayed states:
  `spec/evidence/E1`, `E2` (P1/P2 FALSE), controls `C1`, `C2` (TRUE).

## Reproduction
Command: `SKIP_PREPARE=1 SCENARIOS="repro-u1-stalled-log-r1 repro-u1-stalled-log-r2 repro-u1-stalled-log-r3" harness/run.sh`
(test `harness/repro/SpeculaU1ReproTest.java`, = `DIFFSyncConsistencyTest` scenario with
the restarted followers' SyncRequestProcessor input dropped while they sync, followers fail
at UPTODATE as in the original, then all servers are shut down and the followers restarted
from disk; the new leader is awaited until BROADCAST before checking).
Result: 3/3 `AssertionFailedError: Data inconsistency detected! Server 1 should have a view of /zk2!`
(`spec/output/incremental/harness/repro-u1-stalled-log-r{1,2,3}.log`; traces in
`traces/fault-injected-repro/`).

Controls:
- same test, old revision: fails 1/1 (`old-control-repro-u1-r1.log`) — pre-existing (the old
  code did not log before the ACK at all).
- `SpeculaDiffSyncControlTest` (no stall, non-vacuous leader wait): new revision passes 2/2
  (`control-diffsync-leaderwait-r{1,2}.log`), old revision fails 2/2
  (`old-control-diffsync-leaderwait-r{1,2}.log`): the update fixes the case where the
  logged txns reach disk before the restart, not the case where the ACK precedes durability.
