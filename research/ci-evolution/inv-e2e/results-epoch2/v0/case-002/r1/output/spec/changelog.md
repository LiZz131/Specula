# Changelog — incremental run (old `1414ebf` → new `2efbdfc`)

The exact-old prior changelog is preserved unchanged in
`/work/previous/.specula-output/spec/changelog.md`.

## Round 1 — Generation (source delta + required repairs)

Disposition: **MODEL_CHANGE_REQUIRED** (see `../analysis-report.md` §Incremental).

Source-driven updates (new behaviour of `Learner.syncWithLeader`, `ZooKeeperServer.startup*`):
- [update] `LearnerNewLeaderStartup` (new action): NEWLEADER now does `setSyncMode(NONE)` and
  `zk.startupWithoutServing()` (state INITIAL, processors running) — Learner.java:748-751.
- [update] `LearnerLogPendingOne` (new action): NEWLEADER logs every `packetsNotCommitted`
  entry through `fzk.logRequest` (asynchronous SyncRequestProcessor queue) — Learner.java:752-757.
- [update] `LearnerSendNewLeaderAck` (new action): ACK(newLeaderZxid) only after the buffer is
  empty; does not wait for fsync — Learner.java:757-760.
- [update] `LearnerUptodateStartServing/LogOne/CommitOne`, `LearnerEnterBroadcast`: UPTODATE
  now only `startServing()`s (RUNNING), logs packets buffered after NEWLEADER and commits
  `packetsCommitted` — Learner.java:711-725, :762-786.

Repairs of prior abstractions (implementation-backed; needed to observe the update):
- [repair] Prior `CompleteSync` made the leader history instantly durable at the learner; now
  `SyncWithLeader` buffers DIFF proposals/commits (`pending`, `syncCommits`) and only the
  txn-log pipeline (`queued`→`appended`→`durable`) persists them.
- [repair] Prior `LeaderBroadcast` counted followers already in BROADCAST (after UPTODATE);
  the leader actually counts NEWLEADER ACKs (`nlAcks`, Leader.waitForNewLeaderAck) and then
  `startZkServer` (`LeaderStartZkServer`) before setting BROADCAST (`LeaderEnterBroadcast`).
- [repair] Prior model never committed a leader's recovered log; establishment now commits the
  leader's loaded tree (`committed := proposed`, ghost `maxCommitted`).
- [repair] Votes / FOLLOWERINFO / sync-mode choice use the DataTree position
  (`QuorumPeer.getLastLoggedZxid`), modelled as `applied` + `treeFloor` (`LastLogged`), not the
  txn log; `Restore`, `FastForward`, `TruncateLog` follow FileTxnSnapLog/FileTxnLog.
- [repair] Role exits go through `ServerShutdown`, which honours `canShutdown()` (RUNNING
  only): fast-forward + drain for running instances, nothing (leaked SyncRequestProcessor keeps
  flushing) otherwise.  `Crash`/`Restart` restore snapshot + log.
- [repair] Entry zxids carry `ctr`; `recovered` variable removed (subsumed by `Restore`).
- [fix-inv] `ApplyRequiresCommitCertificate` → `ServingApplyRequiresCommitCertificate`:
  restart replays every logged txn into the tree (FileTxnSnapLog.restore), so the promise only
  holds for a serving (RUNNING) instance.
- [fix-inv] `PipelinePrefix`: log pipeline prefixes + `committed ⊑ proposed` for active roles
  (the role history and the txn log legitimately differ after a skipped shutdown).
- Preflight: SANY (base, MC, Update, Trace) clean; VAV clean except the disabled
  `ReceiveCommit` `OTHER -> FALSE` arm.

## Round 1 — Trace Validation

- [harness] Prior patch rebased: 1 hunk (`BroadcastReady` after `zk.startup()`) re-anchored after
  `zk.startServing()`; update-window probes added (see `instrumentation-spec.md`).
- [harness] `QuorumZooKeeperServer.setState` overrides without `super` — `ZkServerState` probe
  added there (attempt 2 traces superseded).
- [harness] `DatabaseLoaded` probe at `QuorumPeer.start` so in-process peer restarts are visible
  (attempt 3 traces superseded).
- [harness] `CommitDelivered` probe moved before `commitProcessor.commit` (probe-ordering race:
  `TxnApplied` was logged before the delivery; attempt 4 traces superseded).
- [fix] Trace: fixture DIFF leader seeded with exactly the scripted stream (Zab1_0Test sends DIFF
  anchored at 1.1 to an empty follower) (Trace: follower-diff.ndjson).
- [fix] Trace: implied `Leader.propose` (uninstrumented) gated to the leader's next zxid
  (Trace: diff-sync-uptodate-failure.ndjson).
- [fix] Trace: leader may log `NewLeaderAckCounted` before the learner's post-`writePacket`
  probe; that event then performs `LearnerSendNewLeaderAck` for the learner (same guards).
- [fix] Trace: SNAP selection clears the learner history until `SnapshotInstalled`.
- [fix-inv] `OneActiveLeaderPerEpoch` (Case A, real trace seq 136 of attempt 3 /
  `diff-sync` runs): a peer is LEADING before `getEpochToPropose` persists its epoch; only
  epoch-bound leaders (`leadersByEpoch`) are counted.
- Final regression (stable candidate, `output/trace-final-*.log`): 5/5 fresh traces PASS with
  `TraceMatched` (records 27, 27, 185, 89, 349 → states = records + 1).
- Non-vacuity: 3 mutants of follower-diff (ACK before logging; ACK with pending=1; ACK while
  RUNNING) all rejected (`output/trace-nonvacuity-summary.txt`).

## Archived trace dispositions

- `traces/archived-v0/*` (exact-old V0 traces): **superseded** — old record schema (no `aux`,
  no update-window events) and they cross intentionally changed behaviour (old code logs DIFF
  proposals after UPTODATE).  They remain immutable evidence of the old run; the fresh
  new-version traces regenerated from the same scenarios are the gate.
- `traces/superseded-attempt{2,3,4}/*`: fresh new-version traces from earlier harness revisions,
  superseded by probe fixes above.  `superseded-attempt3/diff-sync-uptodate-failure.ndjson`
  is kept as supplementary evidence (seq 120-143: stale-tree peers re-elected in-process).

## Round 1 — Model Checking

- Checkpoint witness (`Update-checkpoint-witness.cfg`, `output/mc-checkpoint-witness-r2.log`):
  DIFFSyncConsistencyTest precondition reachable from `MCInit` in 16 states; `FocusInit`
  copies its final state (canary `output/mc-focusinit-canary-r2.log`).
- [fix-spec, Case B] `WinElection` reused votes collected in earlier rounds
  (`output/mc-update-focus-bfs-r1.log`, stale `votes[s1]`): votes are now consumed on a win
  (`candidate \in votes[candidate]` required) and withdrawn on role exit/crash (`ForgetVotes`).
  Campaigns started before this fix were stopped and rerun.
- [bug] MC-1 `LearnerSendNewLeaderAck` (U-1): ACK before the learner's fsync →
  `NewLeaderAckImpliesDurable`, and with a learner crash `LeaderCompleteness`
  (`output/mc-final-hunt-crash-window-bfs.log`).
- [bug] MC-2 `ServerShutdown` in INITIAL (U-2): stale DataTree, in-process re-election →
  `AckedHistoryRetained`, `LeaderCompleteness` (`output/mc-final-hunt-reelection-bfs.log`).
- [bug] MC-3 `SyncWithLeader` TRUNC to an absent zxid keeps the next entry →
  `ServingApplyRequiresCommitCertificate` (`output/mc-final-focus-trunc-bfs.log`);
  update-independent.  Update hunts prune it with `FilterTruncExtraEntry` (documented);
  `MC.cfg` keeps it enabled.
- [fix-spec, Case B, from real reproduction trace] `ServerShutdown` fast-forward now starts
  after the DataTree position `LastLogged` (FileTxnSnapLog.fastForwardFromEdits reads from
  `dt.lastProcessedZxid + 1`, which is the `(epoch,0)` marker for an established leader);
  the old helper resurrected a stale entry (`output/trace-r1-repro-stale-tree-reelection-1.log`,
  CommittedHistoriesPrefix at event 204).  Trace suite re-validated (`trace-final2-*`), all
  final campaigns rerun on the final artifacts (`output/final-candidate-sha256.txt`).
- [fix] `EnvUpdate` made constructive (`EnvDrop`, `EnvSnapshot`); discharge uses the
  base-variable rely `EnvUpdateBase`.

## Supplementary reproduction (real implementation)
- MC-2: `harness/repro/StaleTreeReelectionReproTest.java` fails on the update revision
  (`output/repro-new-1.log`) and on the baseline control (`output/repro-old-1.log`).
- MC-1: `harness/repro/AckBeforeFsyncReproTest.java` (stalled, then failing follower log
  append = crash before fsync) fails on the update revision
  (`output/repro-ackfsync-new-1.log`) and on the baseline (`output/repro-ackbeforefsync-old-1.log`).
- MC-3: `harness/repro/TruncAbsentZxidReproTest.java` fails on both
  (`output/repro-trunc-new-1.log`, `output/repro-truncabsentzxid-old-1.log`).

## Result
Trace validation converged (6/6 retained traces pass on the final artifacts).  Model checking:
3 model-checking findings with counterexamples, all reproduced on the real update revision;
all campaigns are budget-limited explorations (see `output/campaign-summary.md`).
