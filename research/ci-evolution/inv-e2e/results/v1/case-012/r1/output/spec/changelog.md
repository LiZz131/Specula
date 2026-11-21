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

# Incremental run case-012 (`baseline` ce863f4 → `update` aa05a38)

Disposition: **MODEL_CHANGE_REQUIRED** (see analysis-report.md). Source-driven edits and repairs of pre-existing model defects are listed separately.

## Generation — source-driven
- [spec] base: new variables `leaderActive`, `progress` (Engine leader state / VecProgress with exact vector order); constant `ServerOrder`; operators `VecUpdate`, `MoveUpPos`, `RecalcCommitted`, `UpgradeQuorumSet(D)`, `UpdateProgressResult`, `CalcRole`.
- [spec] `LeaderAppendEntries`: three-step update_progress / update_effective_membership / update_progress; single-node fast commit removed.
- [spec] `HandleUpdateMatched`: early return for matched <= committed, then `update_progress`; commit filter on the leader's term; promotion only on advance.
- [spec] `StartElection`/`GrantVote`: progress created at elect; votes counted on the progress quorum set; accepted vote requests / appends clear Engine leader state (`GrantVote` voter, `DeliverAppendEntries`, `RejectAppendConflict`, `Crash`).
- [spec] `DeliverAppendEntries`/`FollowerCommitEntries`: committed membership promoted only when commit advances.
- [spec] new trace actions `UpdateProgress`, `UpdateEffectiveMembership`, `HandleVoteResp`; `ProgressUpdateValue` (V0 abstraction) replaced by the exact `VecUpdate` relation.
- [mc] MC: no SYMMETRY (order-dependent), `MCServerOrder`; Update.tla with Affected/Interaction actions, `EnvUpdate`/`EnvRely`, discharge, update properties and canaries.

## Generation — repairs of pre-existing model defects (source-independent)
- [repair] ReplicationState.matched reset per leadership (StartElection).
- [repair] ProposeMembership follows next_safe (`SafeNext`).
- [repair] UpdateCommittedMembership role via exact calc_server_state comparison.
- [repair] Init: non-initial members start as learners (no effect for InitialConfig = {Server}).

## Round 1 - Trace Validation
- [harness] rebased V0 patch onto the updated tree (3 engine hunks re-anchored, membership.rs hunks dropped with the deleted function, progress probes rewritten); toolchain `+nightly` → `+stable` (nightly unavailable, read-only RUSTUP_HOME).
- [harness] Engine-event `depth` + outermost-only preprocessing (nested update_progress inside leader_append_entries).
- [fix] ProgressUpgrade (Trace: progress_upgrade.ndjson): model hard-coded `None` as VecProgress default; u64 fixtures use 0 → probe emits `V::default()`, model uses `UpgradeQuorumSetD`. Traces recollected.
- [scenario] added U3 follower no-advance boundary test.
- Result r3: 17/17 fresh traces pass (TraceMatched + TypeOK + MembershipOrder); 4/4 negative controls rejected.

## Round 1 - Model Checking
- MC.cfg: no error, 4,234,432 distinct states, queue 0.
- [fix-inv/scope] OneOutstandingMembership violated after Crash (Update_full r1). Pre-existing Case A, reproduced on the unchanged V0 model (mc-v0-control-oneoutstanding-crash.log): restart resets volatile commit while persisted membership stays. Kept unchanged; enabled only in crash-free configs.
- [fix-cfg] DischargeContext: obligation used `UNCHANGED counterVars`; real omitted actions consume fault budgets → `EnvEffect /\ CounterFrame`.
- [bug] MC-1: CommitWitnessSound / ProgressCommittedSupported / ProgressSortedAboveCommitted violated over complete MCNext (Update_full*.cfg) and in the focused/open views; implementation-confirmed by code observation and a validated trace (Case C).

## Round 2 - Model Checking (simulation follow-up) and repair
- [fix-spec] DeliverAppendEntries / RejectAppendConflict / LeaderAppendEntries (Case B, pre-existing V0 abstraction exposed by the update): `Update_hunt_u1_deep.cfg` simulation violated MembershipOrder (spec/output/mc-upd-hunt-u1deep-sim1.log, 23 states) because V0 DeliverAppendEntries copied the SENDER's current effective membership instead of the membership entries in the appended suffix; V0's unconditional promotion masked it, the update's promote-on-advance exposed it. Repair: new variable `logConfig` (membership payload per log entry); DeliverAppendEntries now follows handle_append_entries_req exactly (first conflicting index via has_log_id with the committed shortcut, truncate_logs with effective-membership revert, follower_update_membership over the appended suffix, no stale tail); RejectAppendConflict reverts an effective membership in the truncated range; LeaderAppendEntries records the membership payload. Trace.tla initializes `logConfig` from the snapshot's effective/committed membership entries.
- [regression] full trace replay r5 after the repair: 17/17 PASS (spec/output/trace-validation-r5-summary.txt).
- [bug] MC-1 consequence: directed 5-server run (MC5_u1_divergence.cfg) violates CommittedLogAgreement (two different entries committed at index 1) — first found before the Round 2 repair, re-checked on the final model in wave A.
