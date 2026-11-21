# Harness instrumentation

The harness uses synchronous, opt-in probes installed only in
`/work/work-source`. Set `specula.trace.file` to enable one-object-per-line
NDJSON output; without it, every probe returns without reading additional peer
state. The exact source-relative patch is preserved at
`patches/instrumentation.patch` against neutral commit
`774296b074905daf3924854264ec54c27842aa9f`.

Each record contains a process-local sequence, actual wall-clock and monotonic
time, Java thread identity, scenario name, event name, node, zxid decomposition,
and the available accepted/current epoch, role, phase, and synchronization mode.
The writer is synchronized, opens and closes the target for every event, and
starts no background work. Full event-to-code and event-to-spec mappings are in
`../instrumentation-spec.md`.

`run.sh` exercises SNAP, DIFF, quorum startup/client mutation/shutdown, and
leader abandonment/restart/recovery with a 240-second outer timeout per Maven
test. Existing traces are moved aside under a process-qualified name before a
fresh run, and the script rejects empty trace output.

## Incremental rebase (updated source)

- Applied the prior patch to artifact commit `update`; every hunk applied except
  the `BroadcastReady` hunk in `Learner.java`, whose anchor (`zk.startup()`) was
  removed by the update. It was re-anchored after `zk.startServing()`.
- Added update-local probes (see `../instrumentation-spec.md` section 2b):
  `SyncProposalReceived`, `SyncCommitReceived`, `NewLeaderAckSent`,
  `NewLeaderAckWritten`, `NewLeaderAckCounted`, `NewLeaderAckRejected`, and a
  `detail` object in `SpeculaTrace` (`emitDetail`, `emitNewLeaderAck`).
- Added the update observation test
  `zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/SpeculaUpdateObservationTest.java`
  (follower conversations; no product-code change); it is part of the patch.
- Rebuild/rerun: `timeout 3600s /work/current/.specula-output/harness/run.sh`
  (`SKIP_BUILD=1` reuses the installed build; `RUN_OBSERVATIONS=0` skips the two
  observation tests).
