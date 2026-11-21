# Validation changelog

(Exact-old V0 history is preserved below the incremental section.)

## Incremental update c780d355 — Generation

- [update] `HandleHeartbeatResponse`: released contexts are cleared from
  `pendingReads` (read_only.go:100-105, key `string(rs.req.Entries[0].Data)`).
  Source-driven; disposition MODEL_CHANGE_REQUIRED.
- [repair R1] `Campaign`, `BecomeLeader`, `HandleVoteRequest` (higher term),
  `HandleAppendEntries`/`HandleHeartbeat` (higher term or candidate),
  `CheckQuorum` (step-down), `HandleReadIndexResponse` (higher term): recreate
  readOnly as `raft.reset()` does (raft.go:489-511). Independent V0 defect,
  required for the update's read-state lifecycle.
- [repair R2] `HandleReadIndexResponse`: justification taken from the
  leader-side release history `servedReads` instead of the leader's live
  pending map (which only worked while exact-old never freed entries).
- [repair R3] `HandleReadIndexResponse`: raft.Step term handling and
  follower-only ReadState append (raft.go:679-735, 1075-1080).
- [ghost] `readStamp`, `servedReads`, pending `stamp/ackLog/gcommit`, message
  `gstamp` — observers for update properties; no behavioral effect.
- [property] added `UpdPendingMatchesQueue`, `UpdReadAckFresh`,
  `UpdReadIndexLinearizable`, `UpdReadStateOnlyAtLeader` in `Update.tla`;
  kept `ReadDeliveryJustified`, `ReadyNoInvention`; representation-only
  revisions of `TypeOK`, `MessagesWellFormed` (spec/invariant-evidence.json).
- [trace] `Trace.tla`: update-mandatory `pending`/`readStates` comparisons;
  bag-matched messages (ghost-insensitive); forwarded-read events;
  `TraceUpd.tla` evaluates the update properties during replay.
- [preflight] SANY: base, MC, Trace, TraceUpd, Update parse
  (spec/output/sany-*.log). No TLC exploration during generation.

## Incremental update c780d355 — Validation (trace)

- [harness] V0 patch applied cleanly to the update commit; v2 patch adds the
  two state fields, read-message ctx capture, `ForwardReadIndex` and
  `HandleReadIndexResponse` probes, and four update scenarios.
- [pass] six fresh new-version traces (quorum_read 28, quorum_loss 15,
  read_reuse 33, forwarded_read 36, stepdown_pending 25, stale_ack_reuse 37
  records) replay completely with `TraceMatched`, all V0 invariants, and
  `UpdPendingMatchesQueue`/`UpdReadStateOnlyAtLeader`
  (spec/output/trace-validation-summary.log).
- [evidence] the V0 model rejects fresh quorum_read/read_reuse at the release
  record (new code frees the entry) and fresh stepdown_pending at the
  CheckQuorum step-down (reset), confirming the update and repair R1
  (spec/evidence/old-model-replay/).
- [evidence] five mutated copies of fresh traces are rejected at the mutated
  record (traces/mutants/MUTANTS.md).
- [evidence] stale_ack_reuse final state violates `UpdReadAckFresh` and
  `UpdReadIndexLinearizable` while `ReadDeliveryJustified` holds non-vacuously.
- [fix-trace] stale_ack_reuse scenario now publishes its ReadStates via
  `newReady` so the separating state carries published reads; all traces
  regenerated and revalidated.
- [archive] traces/v0-archive/{quorum_read,quorum_loss}.ndjson: superseded
  (baseline implementation, lacks update-mandatory fields, records the stale
  entry removed by the update).

## Incremental update c780d355 — Model checking

- [pass] `MC.cfg` (standard, V0 properties): state space exhausted, no
  violation (22,496,273 / 4,291,336, depth 31). `MC_complete_core.cfg`:
  exhausted, identical to V0. No Case A/B; converged in one round.
- [bug] MC-1 (Case C): `UpdReadAckFresh` violated in `Update_hunt_stale_ack`,
  `Update_focused`, `Update_open`, `Update_hunt_forwarded` and in a
  simulation of `Update_full` (complete `MCNext`); `UpdReadIndexLinearizable`
  violated in `Update_hunt_linearizable_directed`. All paths admitted by the
  complete `MCNext` (`spec/admit/`). Reproduced on the real implementation
  (`spec/output/repro.log`).
- [config] `Reach_update_leader_stepdown.cfg`: MaxQuorumCheckLimit 1 -> 2
  (one check only consumes recent activity); first run kept in
  `spec/output/superseded/`.
- [config] `*_rest.cfg` variants omit only the already-violated read-freshness
  property/properties so exploration continues for the others.
- [hunt] `Update.tla` gained `U3Next`/`U3Spec`, a phase-guarded subset of
  `MCNext` for the deep U3 consequence (no behavior defined).
- [coverage] all update and V0 reachability canaries witnessed; all other
  runs budget-limited (see validation-report.md).
- [regression] final `harness/validate.sh` on the final artifacts: all six
  fresh traces pass; evidence oracles and mutated-trace controls behave as
  expected.

## Result (incremental)

Converged in one trace/MC round after the generation repairs. Bug hunting:
1 bug (MC-1, REPRODUCED). Coverage: LIMITED_COVERAGE (time budgets; inherited
counter-free VIEW).

---

# Exact-old V0 history (prior run, preserved)

(V0 changelog)

## Round 1 — Trace validation

- [fix-spec] `HandleAppendEntries`: represented zero-entry Append messages so
  the exact-old leader commit broadcasts replay faithfully, in addition to the
  bounded one-entry append case.
- [fix-trace] State capture: encoded empty read queues as `[]` instead of JSON
  null so the sequence mapping is total.
- [pass] `quorum_read.ndjson`: all 28 records consumed; 29 distinct states.
- [pass] `quorum_loss.ndjson`: all 15 records consumed; 16 distinct states.
  `TraceMatched` and all enabled safety invariants held for both traces.

## Round 1 — Model checking

- [fix-config] Symmetry: changed MC constants from strings to model values so
  `Permutations(Server)` is valid. Trace constants remain exact Go strings.
- [fix-spec] Ready publication contract (Case B): gated ordinary message
  delivery on sender-side durable HardState/log. This removed an impossible
  pre-persistence crash/restart election counterexample without changing
  `ElectionSafety`.
- [fix-config] Disabled deadlock checking for counter-bounded terminal states;
  safety invariant checking remains enabled.

## Round 2 — Convergence and coverage

- [pass] Revalidated the final trace adapter after model changes.
- [pass] Exhausted `MC_complete_core.cfg`, `MC_hunt_s1_election.cfg`, and
  `MC_hunt_s3_quorum.cfg` without a neutral invariant violation.
- [coverage] Preserved timeout-bounded main, replication, and ReadIndex logs.
- [coverage] Split expected reachability violations into `Reach_*.cfg` and
  `reach-*.log`, separate from safety hunting results.

## Result

Trace validation passed for both collected executions. Bounded model checking
found zero model-checking bugs; overall coverage remains limited by explicit
state, action, environment, and timeout bounds.
