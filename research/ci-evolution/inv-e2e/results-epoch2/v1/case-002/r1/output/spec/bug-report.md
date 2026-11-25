# Bug Report — Apache ZooKeeper Zab, V1 incremental run (source revision `update`)

## Summary

- Update analysed: `Learner.syncWithLeader` NEWLEADER branch now starts the
  request processors (`ZooKeeperServer.startupWithoutServing`, state `INITIAL`),
  hands the buffered DIFF/sync proposals to `logRequest`, and then writes the
  NEWLEADER ACK; UPTODATE calls `startServing()`.
- Scenarios tested: U1/U2 (ACK before durability, crash/epoch window), U3 (ACK
  ordering), U4 (failure between NEWLEADER ACK and UPTODATE), plus the inherited
  V0 scenarios (election, sync, mutation, recovery).
- Bugs found: **3** model-checking findings (MC-1, MC-2, MC-3), all reproduced
  on the real updated implementation with in-process quorum tests (MC-1 3/3 with
  a stalled-disk fault, MC-2 3/3 without fault injection, MC-3 1/1 with a
  learner-thread delay); old-revision controls in each section.
- Configs run (final model; logs in `spec/output/incremental/runs/`, ledger
  `runs/ledger.ndjson`): `MC.cfg`, `MC-filtered.cfg` (BFS + simulation),
  `base.cfg`, `Update-full-P1..P5.cfg`, `Update-focused-P1..P5.cfg`,
  filtered follow-ups, `Update-open.cfg`, `Update-discharge.cfg`,
  `Update-hunt2s-*.cfg`, `HuntU1-P3*.cfg`, canaries, inherited `MC-hunt-*.cfg`.
- Coverage is budget-limited (finite constants, 15–30 min per run); no run is a
  proof. See `spec/output/incremental/campaign-summary.md`.

## Bug 1 (MC-1): NEWLEADER ACK is written before the synced transactions are durable

- **Scenario**: U1/U2 (`modeling-brief.md` V1 addendum)
- **Severity**: High
- **Invariant violated**: `CertifiedDurableOnQuorum` (P2); also
  `NewLeaderAckImpliesDurableSync` (P1) and, as consequence,
  `CertifiedRetainedByLaterLeaders` (P3)
- **Config**: `Update-hunt2s-CertifiedDurableOnQuorum.cfg` (FocusedSpec, 2
  servers); `Update-full-P1.cfg` (full MCNext); `Update-full-P2.cfg` simulation
  (full MCNext, 3 servers); `HuntU1-P3-crash.cfg` (consequence)
- **Counterexample**: `spec/output/cex/MC-1_CertifiedDurableOnQuorum_hunt2s.out`
  (27 states), `MC-1_CertifiedDurableOnQuorum_fullMCNext_sim.out` (55 states),
  `MC-1_NewLeaderAckImpliesDurableSync_fullMCNext.out` (20 states),
  `MC-1_CertifiedRetainedByLaterLeaders_crash_huntU1.out` (42 states)

### Trace Summary

Epoch 1: s1 leads with s2, proposes t1 and makes it durable only locally
(s2 never receives it). Epoch 2: s1 is re-elected with s2's vote; s2 syncs with
DIFF (t1 in `packetsNotCommitted`), handles NEWLEADER (`setCurrentEpoch(2)`,
`logRequest(t1)` = enqueue only) and writes the NEWLEADER ACK; s1 counts it,
reaches the NEWLEADER quorum and starts serving its loaded history, certifying
t1 while t1 is durable only on s1 (P2 violated). Consequence variant (3
servers): s2 crashes before its SyncRequestProcessor appends/fsyncs t1, restarts
with `currentEpoch = 2` and an empty log, s3 (epoch 0) votes for it, and s2
establishes epoch 3 without the committed, already-served t1 (P3 violated).

### Root Cause

`Learner.java:752-760`: `FollowerZooKeeperServer.logRequest`
(`FollowerZooKeeperServer.java:82-89`) only adds the request to `pendingTxns`
and to the `SyncRequestProcessor` queue (`SyncRequestProcessor.java:273-278`);
the append and the `FileTxnLog` force happen later on `SyncThread`
(`SyncRequestProcessor.java:156-252`). The NEWLEADER ACK is written right away,
and `Leader.waitForNewLeaderAck` (`Leader.java:1547-1572`) treats it as the
learner's commitment to the leader's initial history (`Leader.java:652-712`).
`setCurrentEpoch(newEpoch)` (`Learner.java:743`) is persisted even earlier, so a
crashed learner wins FLE (`FastLeaderElection.java:880-884`) over peers that
hold the transaction. Real-trace evidence: in `follower-diff`,
`follower-diff-bulk-r1..r3` and `diff-sync-uptodate-failure` every NEWLEADER ACK
that logged txns was written with `fsyncedZxidAtAck` below the logged zxid; the
first DIFF fsync happened only after UPTODATE.

### Reproduction (real implementation)

`harness/work-source/.../SpeculaU1ReproTest.java` (update test scenario; fault:
the restarted followers' SyncRequestProcessor input is stalled during the
NEWLEADER window, i.e. a slow disk until the process restarts — on disk the same
as a crash before the flush; the followers fail at UPTODATE as in the update's
test and restart from disk). Result: **3/3 runs** "Data inconsistency detected!
Server 1 should have a view of /zk2" (`spec/output/incremental/harness/repro-u1-stalled-log-r*.log`).
Control without the stall (`SpeculaDiffSyncControlTest`, non-vacuous leader wait):
new revision passes 2/2, old revision fails 2/2 — the update fixes the
restart-after-flush case but not the case where the ACKed txns were not yet
durable. Old revision with the stall: fails 1/1.

### Affected Code

- `quorum/Learner.java:743` — epoch persisted before the synced txns are durable
- `quorum/Learner.java:752-760` — `logRequest` (enqueue) followed immediately by the NEWLEADER ACK
- `quorum/FollowerZooKeeperServer.java:82-89`, `SyncRequestProcessor.java:156-252,273-278` — asynchronous append/fsync
- `quorum/Leader.java:663-712,1547-1572` — NEWLEADER-quorum establishment

### Recommendation

Make the NEWLEADER ACK conditional on durability of everything logged in the
NEWLEADER branch (e.g. append and flush/force the buffered packets synchronously
before writing the ACK), and avoid persisting the new current epoch before the
synced history is durable (or make that order crash-safe).

---

## Bug 2 (MC-2): Failure between NEWLEADER ACK and UPTODATE leaves the server INITIAL; shutdown is skipped and the stale in-memory DB is used to vote and lead

- **Scenario**: U4
- **Severity**: High
- **Invariant violated**: `CertifiedRetainedByLaterLeaders` (P3),
  `VotingHistoryCoversDurable` (P5), and the reference `PipelinePrefix`
  (standard `MC.cfg`)
- **Config**: `HuntU1-P3.cfg`; `Update-hunt2s-VotingHistoryCoversDurable.cfg`;
  `Update-full-P5.cfg`; `MC.cfg`; `MC-filtered.cfg` (variant)
- **Counterexample**: `spec/output/cex/MC-2_CertifiedRetainedByLaterLeaders_noCrash_huntU1.out`
  (40 states, no crash), `MC-2_VotingHistoryCoversDurable_*.out`,
  `MC-2_PipelinePrefix_MCcfg.out` (23 states), `MC-2_PipelinePrefix_MCcfg_variant.out`

### Trace Summary

Epoch 2: s1 (DIFF) logs t1 at NEWLEADER and ACKs; the leader s2 counts the
ACK and certifies/serves t1. Before UPTODATE s1's connection fails:
`Learner.shutdown → zk.shutdown()` returns early because the server is still
`INITIAL`, so the in-memory DB is not fast-forwarded and the processors are not
stopped (the leaked SyncThread may still write t1 to the log). s1 goes LOOKING
with its new epoch and an in-memory history without t1; the absent peer s3
votes for it; `Leader.lead → loadData` uses the initialized (stale) DB, and s1
establishes epoch 3 without t1 (P3). In the leaked-flush branch the log holds t1
while the leader's served history does not (P5 at the vote; `PipelinePrefix`
once it leads), so a later restart of that server would replay t1.

### Root Cause

`ZooKeeperServer.startupWithoutServing` (`ZooKeeperServer.java:673-675`, new)
leaves `State.INITIAL`; `canShutdown()` is false for it
(`ZooKeeperServer.java:784-786`), so `ZooKeeperServer.shutdown`
(`:803-807`) and `LearnerZooKeeperServer.shutdown` (`:155-159`) return before
`fastForwardDataBase` and `syncProcessor.shutdown()`. FLE and `registerWithLeader`
then use `QuorumPeer.getLastLoggedZxid` = in-memory position
(`QuorumPeer.java:1257-1262`), and `ZooKeeperServer.loadData` keeps the
initialized DB (`ZooKeeperServer.java:480-503`).

### Reproduction (real implementation)

`SpeculaU4ReproTest` (update test scenario without restarting the followers;
old leader stopped after it served `/zk2`): **3/3 runs** on the new revision —
new leader elected in-process with in-memory zxid `0x100000001` lacks `/zk2`
("Data inconsistency detected!"); traces `traces/repro-u4-no-restart-r*.ndjson`
show `ShutdownSkipped(INITIAL)`, leaked `SyncThread` `TxnDurable (1,2)` while
LOOKING, `ElectionWon` with `(1,1)`, and a DIFF advertising `(1,1)`. Old revision
control: also loses `/zk2` (1/1): the loss path predates the update and the
update does not fix it for the no-restart case; the leaked processors and the
log/in-memory divergence are introduced by the update.

### Affected Code

- `ZooKeeperServer.java:669-680` (`startupWithoutServing`), `:784-807` (`canShutdown`/early return)
- `quorum/LearnerZooKeeperServer.java:155-172`
- `quorum/Learner.java:751,850-863`; `quorum/QuorumPeer.java:1257-1262,1468-1480`
- `ZooKeeperServer.java:480-503` (`loadData` on an initialized DB)

### Recommendation

Allow a learner server started without serving to be shut down (stop and drain
its processors, fast-forward or reload the DB), or reload the database from disk
before re-entering leader election when the server never reached `RUNNING`.

---

## Bug 3 (MC-3): A learner txn ACK can precede its NEWLEADER ACK

- **Scenario**: U3
- **Severity**: Medium (availability)
- **Invariant violated**: `NewLeaderAckIsFirstAck` (P4)
- **Config**: `Update-hunt2s-NewLeaderAckIsFirstAck.cfg`; `Update-full-P4.cfg`
- **Counterexample**: `spec/output/cex/MC-3_NewLeaderAckIsFirstAck_hunt2s.out`
  (23 states), `MC-3_NewLeaderAckIsFirstAck_fullMCNext.out`

### Trace Summary

After `FollowerProcessNewLeader` the learner's SyncRequestProcessor appends and
fsyncs a logged txn and `SendAckRequestProcessor` writes its ACK before the
learner thread writes the NEWLEADER ACK.

### Root Cause

`Learner.java:751-760` starts the processors before the NEWLEADER ACK write.
`LearnerHandler.java:606-623` consumes the first ACK as the NEWLEADER ACK;
`Leader.waitForNewLeaderAck` rejects a txn zxid (`Leader.java:1556-1562`), and the
real NEWLEADER ACK is then ignored by `processAck` (`Leader.java:988-994`); the
swallowed txn ACK is never counted either. During epoch establishment the
learner is not counted (the leader may time out and re-elect).

### Reproduction

Natural runs: not observed (NEWLEADER ACK first in every traced exchange and in
`SpeculaNewLeaderAckOrderTest` with 7, 1500 and 3000 DIFF txns, with and without
tracing). Timing-injected run (`SpeculaU3ReproTest`, update test scenario; the
restarted learners pause 1.5 s before writing an epoch ACK, emulating a
descheduled learner thread): the leader's `NewLeaderAckReceived` probe shows
`rejected-zxid-mismatch` for both learners' first ACK (txn (1,2)) in epochs 2, 3
and 4; the leader logged "NEWLEADER ACK ... is from a different epoch" 10 times
and no leader was established within 100 s (trace
`traces/fault-injected-repro/repro-u3-ack-delay-r1.ndjson`). Old revision with
the same pause: leader established, 0 rejections
(`spec/output/incremental/harness/old-control-repro-u3-r1.log`). Combined with
MC-2 (learners keep a stale in-memory DB after each failed round, so the leader
resends the same DIFF), the rejection repeats every round.

### Recommendation

Do not let the learner's ACK path emit txn ACKs before the NEWLEADER ACK has
been written (e.g. write the ACK after a synchronous flush but before enabling
`SendAckRequestProcessor`, or tag NEWLEADER ACKs unambiguously).

---

## Not Reproduced / no violation within budget

| Scenario | Config | States explored | Result |
|---|---|---|---|
| Reference properties, MC-2 class filtered (`FilterKnownU4`) | `MC-filtered.cfg` BFS | 5,841,254 distinct, depth 23, queue 0 | No violation; depth-23 constrained space exhausted (finite-bound, not a proof) |
| Reference properties, round-1 filter | `MC-filtered.cfg` simulation | 81.8M states, 30 min | No violation (LIMITED_COVERAGE) |
| P2 over full / focused, MC-2 filtered | `Update-{full,focused}-P2-filtered.cfg` BFS | 10.6M / 10.4M distinct, depth 26 | No violation within budget (P2 path needs depth ≈27-28 here; found by hunt and simulations) |
| P3 over full / focused, MC-2 filtered | `Update-{full,focused}-P3-filtered.cfg` BFS | 16.1M / 16.6M distinct, depth 25 | No violation within budget (P3 paths need depth ≈40; found by `HuntU1`) |
| P3 focused simulation, MC-2 filtered | `Update-focused-P3-filtered.cfg` | 45.3M states, 10 min | No violation (LIMITED_COVERAGE) |
| P3 full simulation | `Update-full-P3.cfg` | 32.2M states, 10 min | No violation (LIMITED_COVERAGE) |
| Discharge of omitted context vs `EnvUpdate` | `Update-discharge.cfg` (v2) | 13.7M distinct, depth 26 | No violation (LIMITED_COVERAGE) |
| Open focused spec | `Update-open.cfg` (v2) | 1.2M distinct, depth 20 | P1 violated (same as concrete focused; provisional) |
| Reachability canaries | `Update-canary-*.cfg`, `HuntU1-canary-certloss.cfg`, `MC-hunt-*.cfg` | — | All witnesses reached (uptodate, non-durable NEWLEADER ACK, ACK shadowing, INITIAL exit with flush, certified-loss premise at depth 39, V0 election/mutation/recovery/sync) |

Additional MC-1 witness: `spec/output/cex/MC-1_CertifiedDurableOnQuorum_focused3s_sim.out`
(3-server focused simulation, 57 states, MC-2 class filtered).
Full per-run table: `spec/output/incremental/campaign-summary.md`.

## Spec fixes during checking

- [fix-spec] `Crash` clears the crashed peer's FLE vote tally (round-1 crash
  counterexample reused a pre-crash vote; same outcome after the repair).
- [fix-spec] `Update.tla` `EnvUpdate` conjunct order and rollback frame (open
  spec evaluation error, not a semantic change of the reference).
- Exploration-only filters `FilterKnownU4` / `FilterKnownU4Flushed` used in
  follow-up runs to keep exploring past the analysed MC-2 class.

## Persistent findings / lineage

The V0 prior recorded no findings (`/work/previous/.specula-output/spec/findings.json`
is empty), so there was no historical record to match or reuse; the `specular`
CLI (findings registry, `ci-result`) is not installed in this environment, so
`spec/final-result.json` was written but the generated CI reports could not be
produced.
