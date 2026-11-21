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

# Incremental run: baseline ce863f4 → update aa05a38

Disposition: **MODEL_CHANGE_REQUIRED** (see `analysis-report.md` § Incremental update analysis).

## Generation — source-driven edits (UPDATE-MAP comments in base.tla / MC.tla)

- [update] base: new variables `leaderSome`, `progVec`, `progCommitted`, `progQS` (Engine `state.leader` + its `VecProgress`); operators `PNew`, `PUpdate` (`move_up` + prefix scan), `PUpgrade`, `EngineUpdateProgress`, `EngineUpdateEffective`, `UpdateCommitted` (RaftState::update_committed); log-id value encoding `LV`.
- [update] `StartElection`: creates the Leader/progress over the effective membership; vote quorum via progress quorum set.
- [update] `GrantVote`: candidate quorum via progress quorum set; voter's Leader cleared (internal_handle_vote_req).
- [update] `LeaderAppendEntries`: fast_commit removed; `update_progress(self, prev)` before a membership entry, `update_effective_membership` (progress upgrade), `update_progress(self, last)`.
- [update] `HandleUpdateMatched`: record matched; early return when `matched <= committed`; else `Engine::update_progress`. V0 `CommitCandidates`/`GreatestCandidateOrOld` (calc_commit_log_id) removed.
- [update] `DeliverAppendEntries`, `FollowerCommitEntries`: committed-membership promotion only when commit increases; receiver's Leader cleared.
- [update] Trace-only direct forms: `UpdateProgressAction`, `UpdateEffectiveMembershipAction`, `ProgressUpdateValue` (now the real `PUpdate`), `ProgressUpgradeAction`, `HandleVoteResp` (candidate side of handle_vote_resp).
- [update] `CommitWitnessSound` witness now computed from the leader's real replication facts (`matchedIndex`), independent of VecProgress, recorded with the quorum set used for the decision.
- [update] Update.tla: Affected/Interaction/Omitted actions, `EnvUpdate`, `FocusedNext`, `OpenUpdateNext`, `DischargeContext`, properties `ProgressCommittedSound`, `ProgressSortedAboveCommitted`, `ProgressWithinReplication`, `ProgressTracksEffective`, five reachability canaries.

## Generation — repairs of V0 model defects needed by the update interaction

- [repair] R1 `LeaderWriteBlank` + `blankPending`: LeaderState writes the blank entry before handling replication events (core/leader_state.rs:72-97); V0 omitted it.
- [repair] R2 `StartElection` resets `matchedIndex/matchedTerm` and the witness (LeaderState starts with `matched: None`, core/replication.rs:26-47).
- [repair] R3 `ProposeMembership(i, goal)` uses `next_safe` (no direct uniform→uniform jump).
- [repair] R4 Leader cleared on vote grant / append handling (engine_impl.rs:896-897).
- [repair] R5 `SYMMETRY` removed from all cfgs (VecProgress order depends on node ids); `ServerOrder` constant added.
- [config] MaxIndex 0 → 1 in MC.cfg / inherited hunts / reach configs: the modeled blank entry occupies index 0; otherwise client append / membership entries are unreachable.

## Round 1 - Trace Validation

- Harness rebased (patch regenerated against aa05a38; `cargo +stable`; depth-tagged events; fixture splitting). Prior scenario `test_leader_append_entries_with_membership` was removed by the update → replaced by `test_leader_append_entries_fast_commit_upto_membership_entry`; `greatest_majority` superseded (function deleted).
- [fix] Trace: `update_effective_membership_test::..._at_index_0_is_allowed` builds a fixture whose effective membership is older than the committed one; replayed with `Trace_fixture.cfg` (no MembershipOrder). Control log: `output/trace-control-control_learner_under_Trace_cfg.log`.
- [add] `HandleVoteResp` probe + model action so the changed vote-quorum path is observed.
- Result: 27/27 fresh traces pass (`output/trace-validation-final.summary`); 13/13 single-field mutants rejected (`output/trace-validation-mutant.summary`). No reference repair was needed by trace validation.

## Round 1 - Model Checking

- `MC.cfg` (standard): completed, no error (`output/mc-main-r1.log`, 4,234,312 distinct states, depth 31).
- [bug] MC-1 `HandleUpdateMatched`/`LeaderAppendEntries` via `VecProgress`: leader commits a joint-membership entry without a joint quorum (Case C). `output/upd-hunt-u1-bfs.log` (ProgressSortedAboveCommitted), `output/upd-hunt-u1-consequence-bfs.log` (CommitWitnessSound), `output/mc-hunt-s2-bfs.log`. Reproduced on the real runtime, baseline control passes (`confirmation-MC-1.md`).
- [fix-inv] `OneOutstandingMembership` → `OneOutstandingMembershipDurable` (Case A, pre-existing V0 formulation): first exercised with crash + membership in `Update_full.cfg`/`Update_focused.cfg` (`output/upd-full-bfs.log`): a restart resets the volatile `committed` (core/raft_core.rs:193-196) while the committed membership is reloaded from storage. The revised property uses an MC observer ghost `commitHigh` (highest commit ever reached) and keeps the original requirement (a membership is promoted only after it was committed). Not update-related.
- [config] Residual cfgs (`*_residual.cfg`) omit only the properties already violated by MC-1 so exploration can continue past that counterexample; the full cfgs keep them enabled.

## Round 2 - Model Checking (final artifacts)

- Re-ran MC.cfg (complete, 4,234,312 distinct states, no error), all finding/hunt/canary configs, discharge, full/focused/open (+ residual), scale, and simulation follow-ups on the final spec. No further Case A/B; MC-1 reproduces in every config whose bounds include a membership change and the VecProgress properties. Final trace regression (27/27) post-dates the last base/Trace edit; MC/Update edits after it are observer-only (`commitHigh`, canary).

## Result

Converged after 1 trace round and 2 model-checking rounds (one Case A property revision, no Case B). Bug hunting: 1 bug (MC-1, Case C, update-introduced), reproduced on the real runtime with applied-entry divergence; baseline control clean. All coverage LIMITED_COVERAGE.
