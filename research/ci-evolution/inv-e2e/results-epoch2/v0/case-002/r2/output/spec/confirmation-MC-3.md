# Confirmation MC-3 — NullPointerException for a COMMIT after NEWLEADER

- **Source**: MC (`spec/output/update-hunt-npe-sim.log` 60 states full MCNext;
  `spec/output/update-focused-npe-bfs.log` focused BFS;
  `spec/output/trace-oracle-diff-commit-after-newleader.log`)
- **Novelty**: not searched (blind run: issue/history research prohibited)
- **Status**: REPRODUCED
- **Severity**: High (a learner cannot synchronize with an established leader
  while writes are in flight; each attempt is aborted and retried)
- **Update attribution**: introduced by the update (old-tree controls pass).
- **Location**: `quorum/Learner.java:757` (`packetsNotCommitted.clear()`, new)
  with the unchanged `:643-646` (`pif = packetsNotCommitted.peekFirst(); pif.hdr...`).

## Investigation

An established leader's `startForwarding` queues outstanding PROPOSALs for the
learner, and `LearnerHandler.run` queues NEWLEADER afterwards; COMMITs of those
proposals are forwarded whenever the quorum ACKs arrive, i.e. possibly after
NEWLEADER and before UPTODATE.  The updated NEWLEADER branch logs and clears the
buffer, so the unchanged COMMIT branch dereferences `null`.
`Follower.followLeader` catches the exception, closes the socket and the peer
returns to LOOKING.  Old code kept the buffer, so the COMMIT matched it.

## Reproduction

1. `harness/repro/test_bugMC-3_npe_fixture.sh` — Level 0 (legitimate wire
   sequence DIFF, PROPOSAL(1,1), NEWLEADER, COMMIT(1,1), UPTODATE from a
   test-side leader).  New: `java.lang.NullPointerException at
   ...Learner.syncWithLeader(Learner.java:646)`, `zabState=SYNCHRONIZATION`, test
   fails; old: `zabState=BROADCAST`, passes.
2. `harness/repro/test_bugMC-3_npe_cluster.sh` — Level 0 real 3-peer ensemble, no
   injection: a follower restarts and rejoins the established leader while a
   client issues asynchronous creates.  New
   (`spec/output/repro-npe-cluster-r3-new-surefire-output.txt`):
   ```
   SPECULAR-OBSERVATION rejoin attempts=1 issuedWrites=1635 syncExceptions=[sid=0 java.lang.NullPointerException at org.apache.zookeeper.server.quorum.Learner.syncWithLeader(Learner.java:646)] allSynced=true
   NullPointerException in Learner.syncWithLeader while rejoining ... ==> expected: <true> but was: <false>
   ```
   (The first run showed the same at attempt 1 with 1341 writes; its log was
   overwritten by the final re-run.)
   Old control: `rejoin attempts=5 issuedWrites=10586 syncExceptions=[]`, passes.
   (Both versions also log unrelated shutdown-time NPEs in
   SendAckRequestProcessor/ZKDatabase.)

   Trigger rate (no injection, timing-dependent): new tree, 5 runs — NPE in 4
   runs (`repro-npe-cluster-new*` run 1: attempt 1; run 2 (final re-run with
   the final test sources, `repro-npe-cluster-new-run2*`): none in 5 attempts;
   `repro-npe-cluster-r3/r4/r5-new*`: attempts 1, 1, 3), i.e. 4 of 11 rejoin
   attempts.  Old tree, 2 runs: 0 of 10 attempts.  The fixture reproduction
   (item 1) is deterministic.

## Recommendation

Keep the logged proposals available for COMMIT matching (do not clear, or
null-check `pif` and record the zxid in `packetsCommitted` when writeToTxnLog).
