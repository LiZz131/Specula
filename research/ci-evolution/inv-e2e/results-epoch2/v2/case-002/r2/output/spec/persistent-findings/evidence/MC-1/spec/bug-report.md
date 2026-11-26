# Bug Report — ZooKeeper Zab, incremental run for update 2efbdfc

## Summary

- Source revisions: old `baseline` 1414ebf (V0 prior suite), new `update` 2efbdfc.
- Disposition: MODEL_CHANGE_REQUIRED (NEWLEADER handling reordered relative to
  learner logging; see `../modeling-brief.md` §8).
- Fresh traces: 5 (4 V0 regression scenarios + the update's
  `DIFFSyncConsistencyTest`), all replayed by TLC (`output/trace-validation/inventory.md`).
- Findings: **MC-1** (model-checking counterexample, REPRODUCED),
  **CR-2** and **CR-3** (code review, REPRODUCED). Campaign table below;
  every budget-terminated run is LIMITED_COVERAGE, not a proof.

## Bug 1 (MC-1): NEWLEADER ACK is sent before the DIFF-synced transactions are durable

- **Violated property**: `CommittedQuorumDurable` (`Update.tla`), with
  consequence properties `CommittedNeverLostByLeader` / `CommittedHistoriesPrefix`
  demonstrated on the real implementation (see confirmation).
- **Counterexamples** (decoded step lists next to each log):
  - `output/mc/update-hunt-durable-bfs.log` (first finding, 27 states,
    `Update-hunt-durable.cfg`: focused spec, 3 servers, 1 txn, MaxEpoch 2, no faults);
  - `output/mc/update-hunt-durable-final.log` (26 states, same cfg, after the
    FIFO/SelectSync repairs; uses no Crash and no FollowLeader from a non-LOOKING
    peer, so it is also a behavior of the final model);
  - `output/mc/update-hunt-durable-2s-r3.log` (final model, 2 servers);
  - `output/mc/update-full-bfs-r3.log` (final model, **full** `MCNext` with
    crash/drop/snapshot faults, `Update-full.cfg`, 26 states) — the full-reference
    update check reproduces the violation directly;
  - consequence: `output/mc/update-hunt-loss-witness-r3.log` — continuation
    from the reachable state 27 of the first counterexample
    (`output/mc/witness-state27-final-model.txt`, module
    `UpdateLossFromWitness.tla`): s1 and s2 return to election, the acking
    learner s3 crashes before its fsync and restarts, s3 wins epoch 3 with s2's
    vote, s1 follows and is TRUNCated to s3's empty history, s3 activates →
    `CommittedNeverLostByLeader` violated (t1 was committed and served by s1).
  Every focused counterexample uses only `MCNext` actions, so it is admitted by
  the full reference.
- **Reference actions on the path**: `BeginElection`, `CastVote`,
  `WinElection`, `FollowLeader`, `AcceptEpoch`, `FinishDiscovery`,
  `EnterSyncPhase`, `SelectSync(DIFF)`, `CompleteSync`,
  **`SyncWithLeaderNewLeader`** (affected), **`LeaderBroadcast`**, `Propose`,
  `AppendOne`, `FsyncOne`.
- **Path**: epoch 1 — s1 leads with s2's NEWLEADER ACK, proposes t1 and fsyncs
  it only locally (states 2-16). s1 returns to election and is re-elected for
  epoch 2 with s3's vote (17-22). s3 DIFF-syncs: t1 is buffered (25); at
  NEWLEADER s3 persists epoch 2, queues t1 to its SyncRequestProcessor and its
  ACK is counted (26). s1 activates and serves t1 while t1 is durable only on
  s1 (27) — a crash of s3 before its fsync plus s1's unavailability loses t1.
- **Implementation evidence**: `Learner.java:752-760` (logRequest only
  enqueues; ACK written immediately), `FollowerZooKeeperServer.java:86-88`,
  `SyncRequestProcessor.java:166-246`, `Leader.java:663-712, 1547-1573`. The
  fresh real trace `traces/diff-sync-uncommitted-log.ndjson` shows the window
  (events 84-93) and `CommittedQuorumDurable` is FALSE on its replayed state 91.
- **Update attribution**: the update intended to close this window (comment
  `Learner.java:748`, test `DIFFSyncConsistencyTest`) but only moved the
  enqueue before the ACK; the old code had the same defect with a longer window
  (old-revision control also loses the transaction).
- **Reproduction**: REPRODUCED on 2efbdfc (3/3), old control 1414ebf also
  fails (2/2); controls without crash or without slow disk pass. Details:
  `confirmation-MC-1.md`, `../repro/`.

## Bug 2 (CR-2): learner failure between NEWLEADER and UPTODATE leaks an INITIAL server

- **Source**: code review (Scenario U3), no MC counterexample (stale data-tree
  votes are not modeled). Real-trace evidence: leaked `SyncThread:1` fsyncs
  after the peer left the session; the peer later votes/leads with a data-tree
  zxid lower than its durable log (diff-sync trace events 86-103).
- **Mechanism**: `zk.startupWithoutServing()` at NEWLEADER, but
  `ZooKeeperServer/LearnerZooKeeperServer.shutdown` skip an INITIAL server.
- **Reproduction**: REPRODUCED — 3 injected UPTODATE failures leave 3 leaked
  `CommitProcessor` threads on 2efbdfc; none on 1414ebf. `confirmation-CR-2.md`.

## Bug 3 (CR-3): a proposal ACK can be consumed as the NEWLEADER ACK

- **Source**: code review (Scenario U4); liveness/availability only.
- **Mechanism**: the SyncRequestProcessor started at NEWLEADER can write a
  proposal ACK before the NEWLEADER ACK; `LearnerHandler` consumes the first ACK
  and `waitForNewLeaderAck` drops a mismatched zxid.
- **Reproduction**: REPRODUCED — with a 1.5 s learner-thread delay both
  NEWLEADER ACKs are rejected and the leader activates only after a learner
  re-sync (~22 s); `confirmation-CR-3.md`.

## Model-checking campaigns

Logs: `output/mc/<label>.log`; one JSON line per run in
`output/mc/campaigns.ndjson` (exact command, start/end, exit, last statistics).
States under `/dev/shm/specular-e2e-case-002/<label>` were removed after every
run. Runs aborted after the FIFO/SelectSync repair are kept in
`output/mc/aborted-r1/` and are not counted.

The final table is in `output/mc/campaign-summary.md`.
