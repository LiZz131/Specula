# Validation repair changelog

## Round 1 - Trace Validation

- [fix] Trace selection: removed the hard-coded `follower-snap` scenario
  predicate so every trace record in the caller-selected NDJSON file is an
  obligation (audit failures: follower DIFF, quorum, and restart/recovery).
- [fix] Trace domain: generalized servers, epochs, and zxid counter values to
  cover all five retained exact-old traces without modifying trace data.
- [fix] State validation: added schema checks, post-state checks for all five
  captured peer fields, and event-specific zxid/pipeline checks for all 15
  instrumented event names.
- [fix] State-transition validation: replaced trace-fed common-field assignments
  with source-backed event gates. Accepted/current epoch, role, phase, and sync
  mode can now change only at their corresponding probes (including the nested
  election phase update in `setPeerState`), so post-state comparisons are not
  tautologies. Protocol leaders are recorded when accepted-epoch persistence
  binds the newly elected role to its Zab epoch.
- [fix] Trace abstraction: represented uninstrumented leader-side proposal and
  commit callbacks by the minimum implied common prefix, and treated snapshot
  installation as the explicit history-replacement boundary.

## Round 1 - Model Checking

- [fix-spec] `EnterSyncPhase`: required the follower's accepted epoch to equal
  the leader's persisted epoch, matching `Learner.registerWithLeader` before
  synchronization. This closes the Case-B counterexample in
  `base-canonical-repair.log` where an epoch-1 entry became durable at a
  follower whose accepted epoch was still 0.
- [fix-spec] `ReceiveProposal`/`ReceiveCommit`: required a broadcast learner's
  synchronized current epoch to match the packet epoch. This closes the
  round-3 stale-connection counterexample where a follower still synchronized
  to epoch 1 accepted an epoch-2 proposal from a re-elected server with the same
  identity.
- [fix-spec] `CompleteSync`: bound completion to equal accepted epochs at the
  learner and sync source. This closes the depth-24 counterexample where a
  pre-crash TRUNC session completed after the same leader identity restarted
  in a later epoch.
- [fix-spec] Canonical bounds retain three voters, two epochs, one transaction,
  and one bounded crash/drop/snapshot while permitting both canonical base and
  MC BFS to exhaust naturally. The broader prior run remains preserved as
  limited open-frontier evidence.
- [fix] Canonical exploration: enabled `Permutations(Server)` symmetry in base
  and MC configs. This quotients only voter renamings and leaves all three
  servers, behaviors, actions, and properties in scope.
- [fix] Canonical exploration: added an explicit TLC level-23 state constraint
  to base and MC. The bound exceeds the preserved depth-22 mutation/apply
  witness and retains crash/restart/re-election prefixes; only a natural
  zero-queue completion counts as canonical success.

## Result

Converged in one repair round. All five retained exact-old traces passed before
canonical checking. Canonical base BFS completed with 52,034,534 generated and
6,354,157 distinct states; canonical MC BFS completed with 171,870,841 generated
and 21,701,056 distinct states. Both reached depth 23, exited zero, reported no
violation, and left zero states on the queue. No bug-hunting finding was produced.
The older timeout/open-frontier logs remain preserved as limited evidence only.

---

# V1 incremental run (source revision `update`)

## Generation (MODEL_CHANGE_REQUIRED)

Source-driven (UPDATE-MAP comments in `base.tla`; `Update.tla` focus):
- [update] `FollowerProcessNewLeader`: NEWLEADER branch now sets currentEpoch,
  clears sync mode, starts processors in INITIAL state and enqueues the
  buffered sync proposals (logRequest) without making them durable
  (Learner.java:726-757; ZooKeeperServer.java:669-680).
- [update] `FollowerSendNewLeaderAck`: separate ACK write (Learner.java:760).
- [update] `FsyncOne`: a learner txn ACK written before its NEWLEADER ACK marks
  `ackShadowed`; `LeaderProcessNewLeaderAck` does not count a shadowed learner
  (LearnerHandler.java:606-623, Leader.java:1547-1572, 988-994).
- [update] `FollowerProcessUpToDate`: startServing → RUNNING (Learner.java:767).
- [update] `BeginElection` INITIAL branch: shutdown skipped (no fast-forward, no
  processor shutdown); leaked SyncRequestProcessor flush modeled as
  already-flushed or never (ZooKeeperServer.java:784-807,
  LearnerZooKeeperServer.java:155-172).

Repairs of V0 abstractions the update depends on (REPAIR comments):
- [repair] `LeaderBroadcast` gated by NEWLEADER-ACK quorum, certifies the loaded
  initial history; V0 required followers in BROADCAST (Leader.java:663-712).
- [repair] `FollowerProcessUpToDate` only after the leader is in BROADCAST
  (LearnerHandler.java:623-648); V0 `EnterBroadcast` had no leader gate.
- [repair] V0 `CompleteSync` (atomic install of the leader's durable history)
  split: directive effects in `SelectSync` (truncate/deserialize), persistence in
  the NEWLEADER branch.
- [repair] `recovered` = in-memory DB history; votes (`HistoryAtLeast` with FLE
  zxid order) and `WinElection` (`Leader.lead` → `loadData`) use it; RUNNING
  exit fast-forward/drain; `Restart` restores snapshot+log.
- [repair] `ReceiveProposal`: FIFO/forwarding guard (Leader.java:1294-1325);
  `ReceiveCommit` only in BROADCAST (sync-loop commits are buffered).
- [cleanup] Removed dead V0 actions `QueueLearnerProposal`, `ObserveCommit`
  (never in V0 `Next`); replaced `CompleteSync`, `PersistCurrentEpoch`,
  `EnterBroadcast`, `ClearSyncMode`.
- [property] Added update properties P1-P5 in `UpdateProps.tla` (owned by
  `Update.tla`); reference properties unchanged (see `invariant-evidence.json`).

## Validation (trace) — Round 1

- [harness] Rebased V0 patch; only the `BroadcastReady` hunk needed moving
  (`zk.startup()` → `zk.startServing()`); added update probes; JDK 11 build.
- [fix] Trace: added V1 events/fields and state (nlState, zkState, nlAcks,
  ackShadowed, certEpoch, syncKind, trace-local memStale).
- [fix] Trace interpretation (inherited V0 checks): `ElectionWon` zxid is the
  elected leader's vote zxid for followers (diff-sync trace line 63);
  role/phase/BroadcastReady zxids are the in-memory DataTree position — log,
  applied prefix (bulk-r1 line 33), or the stale in-memory history after
  `ShutdownSkipped(INITIAL)` (diff-sync line 108); the TxnDurable watermark in
  `NewLeaderAckSent` is compared only for DIFF sessions (leader-abandon line 252).
- [superseded] All 5 archived V0 traces stop at the first point needing V1
  probes (BroadcastReady without NEWLEADER ACK / leader BROADCAST without
  counted NEWLEADER ACKs).
- [negative] 5 field mutations rejected at the mutated event.
- Result: 8/8 fresh new-version traces pass (TraceMatched).

## Validation (trace) — Round 2 (after reproduction scenarios)

- [harness] Added update-focused scenarios derived from the diff:
  `SpeculaNewLeaderAckOrderTest` (bulk DIFF), `SpeculaU4ReproTest`,
  `SpeculaU1ReproTest` (stalled-disk fault), `SpeculaDiffSyncControlTest`.
- [fix] Trace interpretation: `FollowerRegistered`, `SyncModeChanged`,
  `SyncSelected` zxids are in-memory positions (U4 repro line 118/121);
  observed LEADING before epoch binding mapped to a non-protocol leader
  (`leaderBound`, U4 repro line 108); per-epoch protocol-leader constraint
  replaces the V0 global single-leader constraint; `ShutdownSkipped(INITIAL)`
  also from a never-started server (U1 repro line 107).
- [config] `Trace.cfg` MaxEpoch 3 → 4 (U4 repro r2 reaches epoch 4).
- [scope] U1 reproduction traces kept out of the conformance suite (injected
  input loss + unprobed restart are not representable by the observational
  trace model).

## Model Checking — Round 1 (pre-repair) and Round 2 (final model)

- [bug] MC-1 `CertifiedDurableOnQuorum`/`NewLeaderAckImpliesDurableSync`/
  `CertifiedRetainedByLaterLeaders`: NEWLEADER ACK before durability (Case C).
- [bug] MC-2 `CertifiedRetainedByLaterLeaders`/`VotingHistoryCoversDurable`/
  `PipelinePrefix`: INITIAL-state exit leaves stale in-memory DB (Case C).
- [bug] MC-3 `NewLeaderAckIsFirstAck`: txn ACK before NEWLEADER ACK (Case C,
  availability; not observed in real runs).
- [fix-spec] `Crash` clears the peer's vote tally (round-1 crash counterexample
  reused a pre-crash vote; Case B, outcome unchanged after repair).
- [fix-spec] `Update.tla` open-spec rely: `messages'` assigned before use,
  rollback frame added (evaluation error, not reference behavior).
- [filter] Follow-up runs filter the analysed MC-2 class with
  `FilterKnownU4` (= `VotingHistoryCoversDurable` as a state constraint).

## Result

Trace validation converged (13/13 fresh conformance traces pass); model
checking produced 3 Case-C findings and 2 Case-B/tooling repairs; campaigns are
budget-limited (no exhaustive pass).

## Notes

- Comment-only edits after the final campaign: UPDATE-MAP pointers for
  `BeginElection`/`LeaderBroadcast` in `base.tla`, removal of an unused
  `HuntConstraint` operator from `Update.tla` (SANY re-checked).
- V0 suite scripts (`run-validation-suite.sh`, `check-verification-suite.sh`,
  `verification-suite-manifest.json`) are retained as historical V0 artifacts;
  V1 uses `run-incremental-validation.sh`, `run-incremental-campaign.sh`,
  `run-incremental-followups.sh`, `run-tlc.sh`, and the generated
  `output/incremental/{trace-inventory,campaign-summary}.json`.
