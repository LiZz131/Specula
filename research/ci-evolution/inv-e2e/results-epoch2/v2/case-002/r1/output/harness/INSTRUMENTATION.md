# Harness instrumentation (rebased)

Opt-in synchronous probes (`-Dspecula.trace.file`, `-Dspecula.trace.scenario`) in
`work-source/` only; the patch is `patches/instrumentation.patch` against commit
`update`. Full event/field/Action mapping: `../spec/instrumentation-spec.md`.

Changed points relative to V0:

| Probe | File (after apply) | Change |
|---|---|---|
| `BroadcastReady` | `quorum/Learner.java`, after `zk.startServing()` | moved (V0: after `zk.startup()`, which no longer exists at that point) |
| `NewLeaderAckSent` | `quorum/Learner.java`, NEWLEADER case, immediately before `writePacket(ACK newLeaderZxid)` | new |
| `NewLeaderAckCounted` / `NewLeaderAckMismatch` | `quorum/Leader.java` `waitForNewLeaderAck`, after `addAck(sid)` / in the zxid-mismatch branch | new; `SpeculaTrace.emitPeer` adds `"peer"` |
| `PeerDatabaseLoaded` | `quorum/QuorumPeer.java` `loadDataBase`, after epoch files are read | new (in-JVM restarts in the update scenario) |
| `CommitDelivered` | `quorum/FollowerZooKeeperServer.java` `commit`, before `commitProcessor.commit` | moved (race with CommitProcessor's `TxnApplied`) |

To add a field: extend `SpeculaTrace.emit(String,long,long,long,long,String,String,String)`
and the `TraceInputOK`/`Validate*` predicates in `spec/Trace.tla`. To add an event:
call `SpeculaTrace.emit(name, peer, zxid)` at the real code point, add the name to
`EventNames` and to `Kind` in `Trace.tla`. Rebuild/rerun: `harness/run.sh <scenario>`
(set `SKIP_APPLY=1` to reuse an applied and built tree).
