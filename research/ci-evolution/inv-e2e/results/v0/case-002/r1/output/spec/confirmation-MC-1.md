# Confirmation MC-1 — NullPointerException when a COMMIT crosses NEWLEADER

- **Status**: REPRODUCED (bug)
- **Source**: MC (actual counterexample) + code review
- **Novelty**: NEW within this run (external issue/history search is prohibited by the blind
  input contract; no prior Specula finding exists — V0 `findings.json` is empty)
- **Attribution**: introduced by the update (old-revision control passes)
- **Severity**: High (a learner cannot finish synchronisation while the leader has in-flight
  proposals; each failed attempt also leaks the request-processor threads started in the new
  INITIAL state)
- **Source revision**: `artifact/` commit `update` 2efbdfc3754d

## Mechanism (code)
- `quorum/Learner.java:752-757` (update): at NEWLEADER every `packetsNotCommitted` entry is
  passed to `fzk.logRequest` and the deque is cleared.
- `quorum/Learner.java:643-646` (unchanged): case COMMIT/COMMITANDACTIVATE executes
  `pif = packetsNotCommitted.peekFirst(); if (pif.hdr.getZxid() == qp.getZxid() && ...)` —
  `pif` is `null` when the deque is empty.
- `quorum/Leader.java:1294-1330` `startForwarding` queues outstanding proposals for the learner
  and makes it a forwarding follower; `quorum/LearnerHandler.java:591-601` queues NEWLEADER only
  afterwards. A proposal outstanding at `startForwarding` whose quorum forms after NEWLEADER was
  queued therefore reaches the learner as PROPOSAL … NEWLEADER … COMMIT.
- The exception escapes `syncWithLeader`; `Follower.followLeader` (Follower.java:130-135) closes
  the socket; the peer goes back to LOOKING. Because the server is in State.INITIAL,
  `LearnerZooKeeperServer.shutdown()` returns without stopping the processors
  (`canShutdown()`, ZooKeeperServer.java:784-786, LearnerZooKeeperServer.java:155-159).

## Model-checking counterexample
- Property `Update!NoSyncException` (`syncError = {}`), configs `spec/Update-hunt-npe.cfg`
  (depth 34) and the stricter `spec/Update-hunt-npe-strict.cfg` (depth 38; commit quorum formed by
  an already synchronised follower, the late joiner's own ACKs never counted). Both use the full
  `MCNext` with a guidance constraint only.
- Logs: `spec/output/mc/hunt-update-npe.log`, `spec/output/mc/hunt-update-npe-strict.log`;
  JSON traces `spec/output/cex/hunt-update-npe*.json`.
- Strict path: s1 elected epoch 1, s2 synchronises and enters BROADCAST; s3 joins late
  (`SelectSync` DIFF with outstanding t1 forwarded), `LeaderQueueNewLeader`; s3
  `LearnerProposal`, `LearnerNewLeader`, `LearnerStartupWithoutServing`, `LearnerLogPending`
  (buffer cleared), `LearnerAckNewLeader`; s2 receives/forces/ACKs t1; `Commit(s1,t1)` appends
  COMMIT to s3's stream; `LearnerCommit(s3)` with empty `pnc` -> NPE branch.
- Unguided confirmation: simulation of `spec/Update-full.cfg` (full MCNext, no constraint) hit the
  same violation after 45 random traces (`spec/output/mc/sim-update-full.log`).
- Reference/Update mapping: `base!LearnerCommit` (interaction), `base!LearnerLogPending`,
  `base!LearnerAckNewLeader` (affected); Scenario U-NPE.

## Trace validation evidence
`traces/update-commit-after-newleader.ndjson` (real code, fixture leader replays the same packet
order): `SyncProposalBuffered(pending=1)`, `CurrentEpochPersisted`, `SyncModeChanged(NONE)`,
`ProposalQueued`, `NewLeaderAcked(pending=0)`, `SyncCommitReceived(pending=0)`,
`FollowerException(NullPointerException)`. Replays through `base!LearnerCommit`'s NPE branch
(`spec/output/trace-validation/final-update-commit-after-newleader.log`); the mutated trace that
claims a non-empty buffer is rejected (`negative-neg-commit-buffer-nonempty.log`).

## Reproduction
- Test: `harness/tests/SpeculaSyncUpdateTest.java#testCommitOfForwardedProposalAfterNewLeader`
  (Zab1_0Test-style leader stream DIFF, PROPOSAL p, NEWLEADER, COMMIT p, UPTODATE; asserts the
  learner ACKs UPTODATE, reaches BROADCAST and applies p).
- Command: `repro/run-repro.sh` (uninstrumented trees; JDK 21; outer timeouts).
- New revision (`repro/new-tree`): FAIL 3/3 — `learner must finish synchronization and ACK
  UPTODATE; observed [ACK:100000000, stream-ended:EOFException]`
  (`repro/new-npe-run{1,2,3}.log`, NullPointerException at Learner.syncWithLeader in the log).
- Old-revision control (`repro/old-tree`, the two exact-old changed files restored): PASS 3/3
  (`repro/old-npe-run{1,2,3}.log`).
- Final runs with the race-free assertion (wait for BROADCAST before asserting; script
  `repro/run-repro-npe-v2.sh`): new FAIL 3/3 (`repro/new-npe-v2-run{1,2,3}.log`, server logs
  `repro/surefire/new-npe-v2-run*-output.txt` show `java.lang.NullPointerException` at
  `Learner.syncWithLeader`), old PASS 3/3 (`repro/old-npe-v2-run{1,2,3}.log`). One intermediate
  capture run of the old tree failed only because the first test version asserted the ZAB state
  before `followLeader` set BROADCAST (`repro/old-capture-testCommitOfForwardedProposalAfterNewLeader.log`:
  UPTODATE was ACKed and p applied); superseded by the v2 assertion.
- Ledger: `repro/repro-results.ndjson`.

## Consequence
The learner that already ACKed NEWLEADER aborts synchronisation, never serves, and retries; with
continuous writes, every attempt can hit another COMMIT that crosses NEWLEADER, so a restarted or
lagging follower may fail to rejoin indefinitely (reduced fault tolerance), and each attempt
leaves the INITIAL-state SyncRequestProcessor/CommitProcessor threads running against the shared
ZKDatabase.

## Recommendation
In the COMMIT case, do not dereference the head of `packetsNotCommitted` unless it exists (after
NEWLEADER the proposals have been handed to the log, so the commit only needs to be recorded for
`fzk.commit` after UPTODATE); and stop the processors when a server fails in State.INITIAL.
