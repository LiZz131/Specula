# Validation summary — incremental run case-012 (updated revision aa05a38)

Disposition: **MODEL_CHANGE_REQUIRED** (reported as MODEL_UPDATED). Overall: **COMPLETED_WITH_LIMITED_COVERAGE**, one model-checking finding (MC-1) confirmed by code observation.

## 1. Validation handoff

- Source: `artifact` HEAD aa05a382856ecfec567c8ac6f06be740e597ef96 (`update`); old control ce863f4 (`baseline`).
- Harness command: `bash harness/run.sh` (applies `harness/patches/instrumentation.patch` to `work/instrumented`, builds with `cargo +stable`, runs 17 scenarios, writes `traces/*.ndjson`); log `spec/output/harness-run.log`. Patch applies to a fresh artifact copy (`spec/output/patch-apply-check.log`).
- Validation command: `bash harness/validate_traces.sh r3` → `spec/output/trace-<name>-r3.log`, summary `spec/output/trace-validation-r3-summary.txt`. Each run is real TLC on `Trace.tla`/`Trace.cfg` with temporal `TraceMatched` plus `TypeOK` and `MembershipOrder`.
- Trace inventory with hashes: `spec/output/trace-inventory.json` (17 traces, 140 events).
- Semantic spec files were changed by validation once (VecProgress default value, see changelog Round 1).

### Fresh new-version traces (all PASS, r3)

| trace | origin | events | event kinds | TLC |
|---|---|---|---|---|
| election | V0 rerun | 2 | Elect×1, QuorumCheck×1 | PASS |
| follower_commit | V0 rerun | 1 | FollowerCommit×1 | PASS |
| leader_append | V0 rerun | 1 | LeaderAppend×1 | PASS |
| leader_fast_commit | update scenario | 3 | LeaderAppend×1, ProgressUpdate×1, QuorumCheck×1 | PASS |
| leader_membership_append | V0 rerun (re-targeted test) | 6 | LeaderAppend×1, ProgressUpdate×3, ProgressUpgrade×1, QuorumCheck×1 | PASS |
| leader_membership_no_voter_change | update scenario | 8 | LeaderAppend×1, ProgressUpdate×3, ProgressUpgrade×1, QuorumCheck×3 | PASS |
| leader_membership_to_1 | update scenario | 9 | LeaderAppend×1, ProgressUpdate×4, ProgressUpgrade×1, QuorumCheck×3 | PASS |
| membership_update | V0 rerun | 1 | UpdateCommittedMembership×1 | PASS |
| progress | V0 rerun | 9 | ProgressUpdate×9 | PASS |
| progress_upgrade | update scenario | 15 | ProgressUpdate×13, ProgressUpgrade×2 | PASS |
| quorum | V0 rerun | 12 | QuorumCheck×12 | PASS |
| replication_state | V0 rerun | 8 | ReplicationLagCheck×8 | PASS |
| u1_joint_commit_order | update scenario | 22 | Elect×1, HandleVoteResp×1, LeaderAppend×2, ProgressUpdate×8, ProgressUpgrade×1, QuorumCheck×7, UpdateProgress×2 | PASS |
| u2_uniform_commit | update scenario | 23 | Elect×1, HandleVoteResp×1, LeaderAppend×3, ProgressUpdate×7, QuorumCheck×7, UpdateProgress×4 | PASS |
| update_effective_membership_leader | update scenario | 4 | ProgressUpdate×2, ProgressUpgrade×1, UpdateEffectiveMembership×1 | PASS |
| update_progress | update scenario | 15 | ProgressUpdate×4, QuorumCheck×7, UpdateProgress×4 | PASS |
| u3_follower_no_advance | update scenario | 1 | FollowerCommit×1 | PASS |

Negative controls (field consumption): mutated `committed`, re-sorted `post_vector`, mutated `progress_committed`, mutated `vote_granted` — all rejected by TLC (`spec/output/trace-negative-controls-summary.txt`, logs `trace-negative-*.log`).

### Archived V0 traces (`traces/archive-v0/`)

| V0 trace | disposition |
|---|---|
| election, leader_append, follower_commit, membership_update, progress, quorum, replication_state | superseded by fresh reruns of the same scenarios (V0 schema lacks the mandatory Engine leader-state fields) |
| leader_membership_append | superseded: V0 test `test_leader_append_entries_with_membership` was replaced by the update; rerun targets `test_leader_append_entries_fast_commit_upto_membership_entry` (same batch shape) |
| greatest_majority | superseded: `Membership::greatest_majority_value` and its test were deleted by the update |

### Update coverage

| Affected/interaction behaviour | Fresh trace observation | Comparison predicate |
|---|---|---|
| `LeaderAppendEntries` (no leader state; single-node fast commit; membership mid-batch: upto, no voter change, voter change to 1; joint upgrade) | leader_append, leader_fast_commit, leader_membership_*, u1, u2 | `EngineSnapshotMatchesNext` incl. `progress`, `leaderActive` |
| `UpdateProgress` (core of `HandleUpdateMatched`) incl. term filter and promotion | update_progress, u1, u2 | same |
| `VecUpdate` / `UpgradeQuorumSetD` (exact order) | progress, progress_upgrade, all nested probes | `TraceProgressUpdate`, `TraceProgressUpgrade` |
| `StartElection` + vote counting on progress quorum set | election, u1, u2 (`Elect`, `HandleVoteResp`) | `EngineSnapshotMatchesNext` incl. `voteGranted` |
| `UpdateEffectiveMembership` (leader not demoted, progress upgrade) | update_effective_membership_leader | same |
| `FollowerCommitEntries` promotion only on advance | follower_commit (advance), u3_follower_no_advance (no advance) | same |
| MC-only: `HandleUpdateMatched` early return / ReplicationState, `DeliverAppendEntries`, `RejectAppendConflict`, `GrantVote` voter side, `Crash` | not traced (async LeaderState/ReplicationCore/storage; same limitation as V0) | — (coverage gap) |

Final trace regression on the final reference (after the Round 2 follower repair): `spec/output/trace-validation-r5-summary.txt` — 17/17 PASS. Keep-evidence replay with `OneOutstandingMembership` added (`Trace_keep.cfg`): 7/7 no error (`spec/output/trace-keep-summary.txt`).

## 2. Model checking

Runner: `harness/run_tlc.sh <Module> <cfg> <tag> <bfs|sim> <minutes> [workers] [depth]` (TLC `-Dtlc2.TLC.stopAfter`, outer `timeout`, states in `/dev/shm/specula-e2e-case-012/<tag>` removed after each run, log `spec/output/mc-<tag>.log`). Batches: `spec/output/batch-campaign-{1,2,3}.txt` (Round 1 model) and `batch-final-{A,B,C}.txt` (final model). Complete table of every run: `spec/output/mc-run-table.md`. TLC prints "No error has been found" also when stopped by its time limit; a run is credited as complete only with an empty queue.

### Final-model campaign (after all repairs)

| Campaign | Config | Result |
|---|---|---|
| Standard convergence | `MC.cfg` | complete, 4,234,432 distinct states, queue 0, no error |
| Inherited V0 hunts s1-s4 | `MC_hunt_s{1..4}*.cfg` | each complete (queue 0), no error |
| V0 reachability canaries | `MC_reach_{leader,commit,membership}.cfg` | reached (expected) |
| 1. Full update check (complete MCNext) | `Update_full.cfg` / `_cws` / `_pcs` / `_sorted` | **MC-1**: `ProgressSortedAboveCommitted` (8), `CommitWitnessSound` and `ProgressCommittedSupported` (11 states) |
| 1b. Full update check, remaining properties | `Update_full_control.cfg`, `Update_full_faults_control.cfg` (crash+loss, 2 terms) | time-bounded, no error (LIMITED_COVERAGE) |
| 2. Concrete focused | `Update_focused_cws.cfg` / `Update_focused_control.cfg` | MC-1 reproduced / time-bounded no error |
| 3. Open focused (EnvUpdate) | `Update_open.cfg` / `Update_open_control.cfg` (+`EnvRelyHolds`) | MC-1 reproduced / time-bounded no error, rely held |
| 3b. Discharge | `Update_discharge.cfg` (`DischargeContext` over MCNext) | time-bounded, no violation |
| 4. Update hunts | `Update_hunt_u1_deep`, `u2_uniform`, `u3_follower`, `u4_election` | u4 complete; others time-bounded no error (u1-deep/u3 also simulated) |
| 4b. Update canaries | `Update_reach_{JointCommit,UpgradedProgress,TwoAboveCommitted,LeaderProgressCommit,ElectedByVotes,FollowerPromotion}` | all reached (expected witnesses) |
| 4c. Directed consequence | `MC5_u1_divergence.cfg` (5 servers, ACTION_CONSTRAINT restricts exploration only) | **`CommittedLogAgreement` violated** (17 states): MC-1 lets a stale leader commit a different entry at an index already committed |
| Broad scale probe | `MC_scale.cfg` | time-bounded, no error |
| Simulation follow-ups (BFS depth ≤ 25) | full_control, faults_control, focused_control, open_control, discharge, u1_deep, u2, u3, u4 (20 min each, depth 60-100; `batch-final-{A,B,C}.txt`) | 9.2M-39.7M states generated each, no violation (time-bounded) |

### Round 1 results superseded by the Round 2 repair

All Round 1 runs (`*-r1`, `*-r2`, `*-sim1`, `batch-campaign-{1,2,3}`) used the pre-repair follower model. Their MC-1 violations reproduce on the final model (`*-final` logs). The Round 1 `MembershipOrder` violation (`mc-upd-hunt-u1deep-sim1.log`) was a model defect (Case B) and is absent after the repair (`mc-upd-hunt-u1deep-sim2.log`). Interrupted runs (`*-r1` of full/faults control, `interrupted-*.log`) are listed only for provenance.

### Classification of every counterexample

| Violation | Classification | Disposition |
|---|---|---|
| CommitWitnessSound / ProgressCommittedSupported / ProgressSortedAboveCommitted (Update full/focused/open) | Case C (implementation) | MC-1, confirmed by `spec/output/new-observe-u1.log` and the TLC-validated trace `traces/u1_joint_commit_order.ndjson` |
| CommittedLogAgreement (MC5 directed) | Case C consequence of MC-1 | `spec/output/MC-1_consequence_counterexample_MC5_divergence.out`; Engine-level `spec/output/new-observe-add-voters.log` |
| OneOutstandingMembership after Crash (`mc-upd-full-r1.log`, `mc-upd-open-r1.log`) | Case A, pre-existing (identical on V0: `mc-v0-control-oneoutstanding-crash.log`) | property kept; enabled only in crash-free configs |
| DischargeContext (`mc-upd-discharge-r1.log`) | discharge frame error (MC counters) | obligation corrected (`CounterFrame`) |
| MembershipOrder (`mc-upd-hunt-u1deep-sim1.log`) | Case B, pre-existing V0 follower abstraction exposed by promote-on-advance | repaired (Round 2) |

### Coverage limits (LIMITED_COVERAGE)

- 3 servers (5 in the directed run), MaxTerm ≤ 2, MaxIndex ≤ 2, ≤ 4 in-flight messages, small action/fault budgets; time-bounded runs did not exhaust their queues. No result is a proof.
- Symmetry reduction is disabled (VecProgress order depends on node ids), which reduces reachable depth per minute relative to V0.
- Divergence beyond the directed scenario was not searched exhaustively in 5-server models.

## 3. Outputs

- Findings: `spec/findings.json`, `spec/bug-report.md`, `spec/final-result.json` (the `specula ci-result` command is not installed here, so generated CI reports were not produced).
- Property evidence: `spec/invariant-evidence.json`, `spec/evidence/`.
- Final response: `/work/current/final-response.json`.
