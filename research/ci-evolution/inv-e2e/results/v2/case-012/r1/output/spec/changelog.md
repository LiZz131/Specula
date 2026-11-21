# Validation/specification changelog

All entries below concern the V0 suite itself. None is an implementation finding, and no exact-old property was weakened to obtain a green result.

| Stage | Symptom | Classification | Correction |
|---|---|---|---|
| Trace setup | cfg parsing rejected directive ordering and a negative constant literal | trace configuration | moved init/spec directives before constants and defined `Nil` in TLA+ rather than cfg |
| Trace semantic check | standard modules did not provide the assumed `Max`/`Min` operators | trace/base specification | added explicit integer `IMax`/`IMin` operators |
| Election trace | trace action deadlocked although the implementation transition was enabled | trace specification | post-snapshot fields had been compared to the pre-state; added explicit primed next-state matchers |
| Progress/majority traces | record field selection failed inside `CHOOSE` | trace specification | bound the selected sequence index in `LET`, then selected the record field |
| Model run 1 | `Nil` was used as a function key while evaluating a log match | model specification | made sentinel branches explicit with `IF`, preserving the same log-match relation |
| Model run 2 | bounded terminal states were reported as deadlocks | model configuration | disabled deadlock checking for intentionally terminating counter budgets |
| Code-faithfulness review | election freshness used the candidate term instead of last-log term/index | model specification | aligned `LogUpToDate` with exact-old `last_log_id` comparison abstraction |
| Code-faithfulness review | conflict handling omitted exact-old `has_log_id`'s committed-prefix shortcut | model specification | committed prefixes now match without re-reading purged/local term state |
| State identity review | bound counters were omitted from the view | model configuration | retained counters in `MCView` so paths with different remaining budgets are not merged |
| Atomicity review | membership promotion was also exposed as a standalone MC step | model specification | retained promotion inside commit/delivery actions and removed the standalone transition from `Next` |
| Scale calibration | broad bounds did not drain within 600 seconds | coverage bound | preserved the scale log as incomplete evidence and added tight, converged main/scenario configs; status remains LIMITED_COVERAGE |

After the final tightening, all implementation traces were replayed again and all final model configurations were rerun.

---

# V1 incremental update (artifact `baseline` ce863f4 -> `update` aa05a38)

Source disposition: **MODEL_CHANGE_REQUIRED** (analysis-report.md, "Incremental update analysis").

## Generation (reference suite revised)

- [update] variables: `matchedIndex`/`matchedTerm` now mean Engine-owned leader progress (leader/leader.rs:29); new `leaderState` (raft_state.rs:44) and `progressConfig` (progress quorum set, progress/mod.rs:218-232). Init/TypeOK extended.
- [update] helpers: `GreatestQuorumValue` (VecProgress greatest quorum value over LogId-ordered values), `UpgradeRow` (upgrade_quorum_set), `UpdateCommittedF` (RaftState::update_committed: promotion only on commit advance), `UpdateProgressF` (Engine::update_progress incl. leader-id filter and no-leader early return), `UpdateEffectiveMembershipF` (Engine::update_effective_membership incl. progress upgrade and server-state rule), `CalcServerState`.
- [update] StartElection: fresh leader data (rows reset, progress quorum set = effective). GrantVote: vote quorum through `progressConfig`; voter drops leader data. LeaderAppendEntries: progress-to-(mIdx-1), effective change + upgrade, progress-to-last; commit only through update_progress. HandleUpdateMatched: skip progress update when `matched <= committed`, else Engine::update_progress. DeliverAppendEntries/FollowerCommitEntries: promotion only on commit advance. RejectAppendConflict/Crash: drop leader data.
- [update] new trace-only actions: UpdateProgress, UpdateEffectiveMembership, HandleVoteResp; ProgressUpdateValue ignores ids outside the quorum set (progress/mod.rs:166-171).
- [property] CommitWitnessSound (V0) superseded by Update!CommitWitnessSound_new (live matched clause replaced by supporters-retain-entry clause); new Update!LeaderProgressConfigCurrent and Update!ProgressMonotonic; see invariant-evidence.json. V0 CWS removed from all cfgs.
- [mc] Update.tla (Affected/Interaction actions, EnvUpdate rely + discharge), Update_{full,focused,open,discharge}.cfg, MC_hunt_u{1,2,3}_*.cfg, MC_reach_u{1,2,3,4}_*.cfg; inherited hunts s1/s2 switched to CommitWitnessSound_new (run on Update.tla).
- [trace] Trace.tla: TraceServer adds "9"; mandatory snapshot fields has_leader/progress/progress_configs/vote_granted (init + post checks); wrappers for UpdateProgress, UpdateEffectiveMembership, HandleVoteResp.
- [preflight] SANY clean for base, MC, Update, Trace.

## Round 1 - Trace Validation (fresh V1 traces)

- [harness] rebased: replication_state/lib/mod/effective_membership hunks applied unchanged; engine_impl.rs and progress/mod.rs probes re-placed by symbol (V0 hunk context drifted); membership.rs hunk dropped (greatest_majority_value deleted); specula_trace.rs extended (leader-data fields, nesting depth, SpeculaValue formatting); new Engine probes update_progress, update_effective_membership, handle_vote_resp; VecProgress unknown-id return probe. Toolchain `+nightly` -> `+stable` (nightly not installed; build/test logs spec/output/upd-*.log).
- [harness] preprocess: keep depth-0 events (nested helper probes dropped by nesting depth instead of by name).
- [scenario] V0 `leader_membership_append` (test removed by the update) and `greatest_majority` (function and test deleted) dispositioned as superseded by the update-focused LeaderAppend and UpdateProgress traces.
- [fix-harness] update_effective_membership_index0: unit fixture's pre-state is internally inconsistent (empty log, no commit, committed membership at index 1); the replayed transition matches, but the fixture post-state violates MembershipOrder. Classified as fixture artifact (not reachable via initialize/leader append, the only callers); validated with Trace_fixture.cfg (TraceMatched + TypeOK) and replaced for the gate by harness fixture update_effective_membership_to_learner (consistent pre-state, same branch).
- [result] 17/17 fresh traces pass Trace.cfg (TraceMatched + TypeOK + MembershipOrder); index0 passes Trace_fixture.cfg. Logs: output/trace-*-v1*.log.
- [evidence] 15 single-field mutations of fresh traces all rejected (output/mutations/); V0 model rejects the 5 update-focused traces and accepts unchanged-behavior traces (output/v0-model-replay/).

## Round 2 - Model Checking (entry round and repairs)

- [mc] standard MC.cfg (V0 bounds) on the V1 suite: completed, 8,115 distinct states, depth 20, no error (output/upd-mc-standard.log).
- [fix-inv-wiring] OneOutstandingMembership violated in the first Update_full smoke run by Crash (volatile commit reset to Nil while the committed-membership record survives). Case A, pre-existing and not update-related: the real restart path resets `committed` (raft_core.rs:189-193, storage/helper.rs get_initial_state "volatile fields") and rebuilds a committed membership (helper.rs get_membership), and the V0 ledger note already marks the restart relation as unknown. V0 never enabled this invariant with crashes. Property text unchanged; enabled only in crash-free cfgs (MC.cfg, Update_focused, hunts u1/u3/s2); recorded as unresolved in invariant-evidence.json.
- [fix-spec] (Case B, pre-existing V0 abstraction exposed by the deeper update-focused bounds) Update_focused BFS: MembershipOrder violated after a node that received a membership entry while its sender's effective membership had already advanced never adopted it, then as leader overwrote another node's effective membership with an older one (counterexample: output/superseded-prerepair/upd-focused-bfs.trace.json). Real follower code derives membership from the appended entries (follower_update_membership, engine_impl.rs:671-746) and truncate_logs reverts (engine_impl.rs:428-485). Repair: new variable `logConfig` (per-entry membership payload), append requests carry entries (`ents`, `mcfg`) as sent, DeliverAppendEntries implements first-conflict truncation + revert + append + last-two-membership adoption + promotion on advance, RejectAppendConflict reverts effective membership on truncation. New structural invariant EffectiveIsLastLogMembership (guide/src/effective-membership.md:5) enabled in MC.cfg and update cfgs. Recorded as a model repair, not a source-delta change.
- [fix-spec] TLC split the action-level disjunction `m.prev = Nil \/ HasLogId(.., m.ents[m.prev])`; replaced by IF (same pitfall as V0 Model run 1).
- [regression] after the repair batch: MC.cfg completed again (8,115 distinct, output/upd-mc-standard-r2.log); full fresh-trace regression 17/17 Trace.cfg + index0 Trace_fixture.cfg pass (output/trace-*-v1r3*.log) on base.tla sha256 prefix e37a9f30a1b38a6e.
- [mc] pre-repair campaign logs moved to output/superseded-prerepair/ (provisional, invalidated by the repair); all campaigns and canaries rerun on the repaired suite.
- [note] Update.tla gained evidence-only canaries NotReachTwoLeaders/NotReachTwoCommitted (no semantic change).

## Round 3 - Model Checking campaigns (final suite)

- [mc] Update_full / Update_focused / Update_open / Update_discharge BFS (30 min each, budget-limited) and simulation follow-ups: no violation.
- [mc] Inherited hunts S1-S4: BFS exhaustive within bounds plus 30-min simulations: no violation. Update hunts U-S1..U-S3: BFS (budget-limited) plus simulations: no violation. MC_scale: budget-limited BFS, no violation.
- [mc] Canaries on the final suite: all expected witnesses reached except the U-S3 probe (covered-but-unpromoted membership), which was not reached within budget.
- [coverage] 240 s coverage probe: every affected and interaction action fires except RejectAppendConflict and DiscardNegativeAck (output/upd-full-coverage.summary.md).
- [evidence] spec/invariant-evidence.json regenerated on the final modules (spec/evidence/*/tlc.log).

## Result

Converged after 3 rounds (trace validation -> MC entry and repairs -> trace regression -> campaigns). Bug hunting: 0 bugs found; 2 pre-existing model/property issues handled (1 Case A wiring, 1 Case B repair); no Case C. All exploration is bounded: LIMITED_COVERAGE.
