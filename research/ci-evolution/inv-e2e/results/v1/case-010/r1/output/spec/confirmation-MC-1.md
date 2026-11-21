# MC-1 confirmation evidence (mechanism)

Finding: learner exit no longer drains or stops the follower `SyncRequestProcessor` (update-introduced).

## Reproduction (real code, both revisions)

Command: `harness/repro-mc1.sh` (runs `SpeculaTraceScenarioTest#testServingLearnerExitStopsSyncProcessor` on `artifact` = update `b16ba71` and on `artifact-old` = baseline `f8533cd`, same harness patch, tracing disabled).

Scenario (normal API only): start a 3-server ensemble, create a node, stop the leader process so both followers leave FOLLOWING while serving (`Learner.shutdown`), let them re-elect and accept a write, then stop all servers. Assertion: each live server runs exactly one `SyncThread:<sid>` after the re-election, and none after all servers stop.

| Revision | Result | Observation |
|---|---|---|
| update (new) | **FAIL** | `live SyncThread:0 threads after one learner exit: {SyncThread:0=2, SyncThread:1=2}` (`spec/output/harness/repro-mc1-artifact.log`, `repro-mc1-artifact.surefire-output.txt`) |
| baseline (old) | PASS | `{SyncThread:0=1, SyncThread:1=1}` after leader loss, `{}` after shutdown (`spec/output/harness/repro-mc1-artifact-old.log`, `repro-mc1-artifact-old.surefire-output.txt`) |

Earlier observation runs agree (`spec/output/harness/upd-serving-exit-v3.surefire-output.txt`: new revision keeps leaked threads after all servers stop: `{SyncThread:0=2, SyncThread:1=1, SyncThread:2=1}`), and the fresh trace `traces/upd-serving-exit-v3d.ndjson` records `LearnerShutdown{served:true, leakedNow:true}` while the old-revision trace records `leakedNow:false`.

## Code path

`QuorumPeer.run` FOLLOWING `finally` -> `Follower.shutdown()` -> `Learner.shutdown()` -> `zk.shutdown(self.getSyncMode().equals(SNAP))` (`Learner.java:864`) -> `ZooKeeperServer.shutdown(boolean)` (`ZooKeeperServer.java:803-858`); `LearnerZooKeeperServer` overrides only `shutdown()` (`LearnerZooKeeperServer.java:154-173`), which is where `syncProcessor.shutdown()` (drain, join, flush; `SyncRequestProcessor.java:251-270`) is called. The old call `zk.shutdown()` reached that override.

## Consequence status

- Reproduced: the follower log processor survives every serving learner exit and every `QuorumPeer.shutdown()` (thread leak; queued writes no longer flushed inside the exit).
- Model-level only (not reproduced here): the data consequences in `spec/bug-report.md` Bug 1 (a re-synced follower's recoverable log missing a committed txn, or a stale record after newer ones) require a crash or a TRUNC log reopen before the leaked thread writes; they are shown by the model counterexamples, and the exact-old semantics are exhaustively clean for the committed-gap property in the same model scenario.
