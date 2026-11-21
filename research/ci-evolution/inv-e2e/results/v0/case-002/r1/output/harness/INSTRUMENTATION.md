# Harness instrumentation (changes relative to V0)

Opt-in synchronous probes (`-Dspecula.trace.file`), same writer/schema as V0
(`SpeculaTrace.emit`), plus an optional `event.sync` object (`pending`, `committed`, `toLog`)
and `event.detail` string.

Changed/added points (all in the updated source):

- `quorum/Learner.java` `syncWithLeader`:
  - `BroadcastReady` re-anchored after `zk.startServing()` (V0 hunk anchored on the removed
    `zk.startup()` no longer applied).
  - `SyncProposalBuffered` after `packetsNotCommitted.add(pif)` (post-state buffer sizes).
  - `SyncCommitReceived` at the start of case COMMIT, before `peekFirst()` (pre-state sizes).
  - `NewLeaderAcked` after `writePacket(ACK newLeaderZxid)` in case NEWLEADER.
- `quorum/Follower.java` `followLeader` catch: `FollowerException` (exception class).
- `quorum/QuorumPeer.java` `loadDataBase`: `DatabaseLoaded` (in-JVM peer restarts).
- `SpeculaTrace.java`: `emitSync`, `emitDetail`.
- Test-only: `SpeculaSyncUpdateTest.java` (also kept in `harness/tests/`).

Rebuild/rerun: `harness/run.sh` (see README). The patch is regenerated from
`diff -ruN artifact/zookeeper-server/src harness/work-source/zookeeper-server/src`.
Event-to-spec mapping: `../instrumentation-spec.md`.
