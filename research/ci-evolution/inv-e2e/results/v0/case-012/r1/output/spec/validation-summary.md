# Incremental validation summary (baseline ce863f4 → update aa05a38)

## Result

- Decision: **MODEL_CHANGE_REQUIRED** (reported as `MODEL_UPDATED`).
- Trace validation: **27/27 fresh new-version traces pass** with real TLC
  (`TraceMatched` + full pre/post-state checks); 13/13 single-field mutants are
  rejected. Coverage is limited to Engine-level unit environments
  (LIMITED_COVERAGE).
- Model checking: one **Case C** finding, **MC-1** (leader commits a joint
  membership entry without a joint quorum through the new VecProgress commit
  path), reproduced on the real runtime with applied-entry divergence; baseline
  control is clean. One **Case A** property repair (V0 `OneOutstandingMembership`).
  All other campaigns: no violation within bounds/time budgets —
  **LIMITED_COVERAGE**, never a proof.

## Handoff (Validation 4)

- Source: updated tree `artifact/` commit aa05a38 (neutral `update`), baseline
  ce863f4. Instrumented copy: `work-source/` (patch
  `harness/patches/instrumentation.patch`, applies cleanly to aa05a38).
- Harness command: `bash harness/run.sh` (stable toolchain; build + 21 scenario
  runs ≈ 10 s after first build; logs `spec/output/harness-*.log`).
- Trace validation command: `spec/run_trace_validation.sh <tag> [trace...]`;
  final regression `spec/output/trace-validation-final.summary` (run after the
  last base/Trace edit); per-trace logs `spec/output/trace-final-*.log`.
- Semantic spec files changed during validation: one additive action
  (`HandleVoteResp`) for the newly traced vote-response path; no repair was
  forced by a trace mismatch.

### Harness provenance and dispositions

| V0 scenario | Disposition on the updated implementation |
|---|---|
| election | rerun, unchanged test (harness file), fresh trace passes |
| leader_append (`test_leader_append_entries_normal`) | rerun, passes |
| leader_membership_append (`..._with_membership`) | test **removed by the update**; replaced by `test_leader_append_entries_fast_commit_upto_membership_entry` (closest successor), passes |
| follower_commit (`..._gt_last_entry`) | rerun, passes (event args re-encoded as log ids) |
| membership_update (`..._at_index_3`) | rerun, passes |
| progress (`vec_progress_update`) | rerun (9 events, new nonexistent-id case), passes with vector order checked |
| quorum (`test_effective_membership_majority`) | rerun, passes |
| replication_state (`test_is_line_rate`) | rerun, passes |
| greatest_majority (`test_membership_greatest_majority_value`) | **superseded**: function and test deleted by the update; archived V0 trace kept in `traces/v0-archived/` |

Rebase changes: patch regenerated against aa05a38 (engine hunks moved; V0
`Display` bounds replaced by `Any`-based rendering because the leader progress
value type is `Option<LogId>`); `cargo +nightly` → `+stable` (only stable is
installed; `/opt/rustup` read-only); `depth` field and fixture splitting added
to the preprocessor. Archived V0 traces: `traces/v0-archived/` (not used as
evidence for the new version).

### Update coverage (fresh traces)

| Affected path | Observed in | Compared by |
|---|---|---|
| `Engine::elect` → `new_leader` (progress creation, vote quorum via progress qs) | `election`, `elect_multi-seg1..3` | `TraceElect` + progress vector/qs/committed, `vote_granted`, `leader_some` |
| `Engine::handle_vote_resp` (`is_vote_granted` via progress qs; Leader cleared on higher vote) | `vote_resp-seg1..5` | `TraceHandleVoteResp` |
| `leader_append_entries` (update_progress before/after membership, fast commit) | `leader_append`, `leader_membership_append`, `leader_fast_commit*` (3), `membership_change_then_acks` | `TraceLeaderAppend` incl. engine committed + progress |
| `update_effective_membership` (+ `upgrade_quorum_set`) | `update_effective_leader`, `update_effective_learner`, inside `membership_change_then_acks` | `TraceUpdateEffectiveMembership`, `TraceLeaderAppend` |
| `update_progress` (leader check, `update_committed`) | `update_progress`, `update_progress_no_leader`, `membership_change_then_acks` | `TraceUpdateProgress` |
| `VecProgress::update` / `upgrade_quorum_set` | `progress`, `progress_upgrade` | `TraceProgressUpdate/Upgrade` (vector order + committed) |
| `follower_commit_entries` → `update_committed` | `follower_commit`, `follower_commit_lt_last`, `follower_commit_no_update` | `TraceFollowerCommit` |
| Interaction: ack → upgraded progress → commit | `membership_change_then_acks` (harness scenario U1+U3) | the replay reproduces the implementation's commit of index 2 with node 1 at index 1 |

Not directly traced (environment limitation, as in V0): LeaderState
`handle_update_matched` bookkeeping (`ReplicationState.matched`, early return),
`SendAppendEntries`/`DeliverAppendEntries`/`RejectAppendConflict`, voter-side
`GrantVote`, loss, crash/recover — they run in the async RaftCore runtime. The
runtime reproduction tests (`harness/repro/`) exercise them end to end but are
not replayed against Trace.tla.

## Model checking

Campaign table (generated from the logs by `spec/summarize_campaigns.py`) is
appended below. Bounds per cfg are in the cfg files; MC uses 3 servers
`{n1,n2,n3}`, no symmetry, message buffer ≤ 4. `BUDGET-LIMITED` = TLC stopped
at its configured time budget (`-Dtlc2.TLC.stopAfter`) with states still
queued: no violation in the explored part only.

### Campaigns on the final artifacts

| Run | Module / cfg | Mode | Elapsed | Distinct states | Queue left | Depth | Outcome |
|---|---|---|---:|---:|---:|---:|---|
| mc-main-final | MC.tla / MC.cfg | BFS | 808s | 4234312 | 0 | 31 | COMPLETE, no error |
| mc-hunt-s3-final | MC.tla / MC_hunt_s3_follower_commit.cfg | BFS | 131s | 4234312 | 0 | 31 | COMPLETE, no error |
| upd-hunt-u1-bfs-final | Update.tla / Update_hunt_u1_membership_progress.cfg | BFS | 3s | 2000 | 1298 | 8 | VIOLATION ProgressSortedAboveCommitted |
| upd-hunt-u1-consequence-final | Update.tla / Update_hunt_u1_consequence.cfg | BFS | 5s | 32908 | 18871 | 12 | VIOLATION CommitWitnessSound |
| upd-full-final | Update.tla / Update_full.cfg | BFS | 7s | 14106 | 10679 | 8 | VIOLATION ProgressSortedAboveCommitted |
| upd-focused-final | Update.tla / Update_focused.cfg | BFS | 10s | 30752 | 21850 | 11 | VIOLATION ProgressSortedAboveCommitted |
| upd-open-final | Update.tla / Update_open.cfg | BFS | 9s | 24962 | 18896 | 9 | VIOLATION ProgressSortedAboveCommitted |
| upd-full-sim | Update.tla / Update_full.cfg -simulate num=999999999 -depth 100 | simulation | 14s | 154664 states checked, 400 traces (mean len 76) | n/a | 100 (sim) | VIOLATION ProgressSortedAboveCommitted |
| upd-full-residual | Update.tla / Update_full_residual.cfg | BFS | 1485s | 17586888 | 11110858 | 15 | no error; BUDGET-LIMITED (queue not empty) |
| upd-full-residual-sim | Update.tla / Update_full_residual.cfg -simulate num=999999999 -depth 100 | simulation | 882s | 18226530 states checked, 46958 traces (mean len 78) | n/a | 100 (sim) | no error (simulation, time budget) |
| upd-focused-residual | Update.tla / Update_focused_residual.cfg | BFS | 1485s | 17751940 | 10630703 | 15 | no error; BUDGET-LIMITED (queue not empty) |
| upd-open-residual | Update.tla / Update_open_residual.cfg | BFS | 1486s | 17140817 | 11575829 | 17 | no error; BUDGET-LIMITED (queue not empty) |
| upd-discharge | Update.tla / Update_discharge.cfg | BFS | 1485s | 14320318 | 9181697 | 15 | no error; BUDGET-LIMITED (queue not empty) |
| upd-hunt-u2-bfs-final | Update.tla / Update_hunt_u2_membership_client_loss.cfg | BFS | 3s | 4208 | 3040 | 9 | VIOLATION ProgressSortedAboveCommitted |
| upd-hunt-u2-residual | Update.tla / Update_hunt_u2_membership_client_loss_residual.cfg | BFS | 1485s | 11661498 | 6223344 | 17 | no error; BUDGET-LIMITED (queue not empty) |
| upd-hunt-u2-residual-sim | Update.tla / Update_hunt_u2_membership_client_loss_residual.cfg -simulate num=999999999 -depth 100 | simulation | 882s | 18345205 states checked, 44691 traces (mean len 81) | n/a | 100 (sim) | no error (simulation, time budget) |
| upd-hunt-u4-bfs-final | Update.tla / Update_hunt_u4_reelection_crash.cfg | BFS | 6s | 31850 | 23910 | 9 | VIOLATION ProgressSortedAboveCommitted |
| upd-hunt-u4-residual | Update.tla / Update_hunt_u4_reelection_crash_residual.cfg | BFS | 1486s | 14308335 | 9109440 | 15 | no error; BUDGET-LIMITED (queue not empty) |
| upd-hunt-u4-residual-sim | Update.tla / Update_hunt_u4_reelection_crash_residual.cfg -simulate num=999999999 -depth 100 | simulation | 881s | 18497010 states checked, 52504 traces (mean len 68) | n/a | 100 (sim) | no error (simulation, time budget) |
| mc-hunt-s1-sim | MC.tla / MC_hunt_s1_progress.cfg -simulate num=999999999 -depth 100 | simulation | 881s | 20614597 states checked, 51297 traces (mean len 81) | n/a | 100 (sim) | no error (simulation, time budget) |
| mc-hunt-s2-bfs-final | MC.tla / MC_hunt_s2_membership.cfg | BFS | 5s | 34419 | 19594 | 12 | VIOLATION CommitWitnessSound |
| mc-hunt-s2-residual | MC.tla / MC_hunt_s2_membership_residual.cfg | BFS | 1485s | 12095402 | 1641103 | 25 | no error; BUDGET-LIMITED (queue not empty) |
| mc-hunt-s2-residual-sim | MC.tla / MC_hunt_s2_membership_residual.cfg -simulate num=999999999 -depth 100 | simulation | 882s | 23512635 states checked, 58720 traces (mean len 81) | n/a | 100 (sim) | no error (simulation, time budget) |
| mc-hunt-s4-sim | MC.tla / MC_hunt_s4_election.cfg -simulate num=999999999 -depth 100 | simulation | 882s | 24936909 states checked, 71600 traces (mean len 70) | n/a | 100 (sim) | no error (simulation, time budget) |
| mc-scale | MC.tla / MC_scale.cfg | BFS | 1485s | 26004168 | 16987431 | 15 | no error; BUDGET-LIMITED (queue not empty) |
| mc-scale-sim | MC.tla / MC_scale.cfg -simulate num=999999999 -depth 100 | simulation | 881s | 19704885 states checked, 53846 traces (mean len 76) | n/a | 100 (sim) | no error (simulation, time budget) |
| mc-reach-leader-final | MC.tla / MC_reach_leader.cfg | BFS | 1s | 6 | 1 | 3 | REACH WITNESS (NotReachLeader) |
| mc-reach-commit-final | MC.tla / MC_reach_commit.cfg | BFS | 2s | 152 | 91 | 7 | REACH WITNESS (NotReachCommitWitness) |
| mc-reach-membership-final | MC.tla / MC_reach_membership.cfg | BFS | 1s | 18 | 8 | 5 | REACH WITNESS (NotReachOutstandingMembership) |
| upd-reach-leadernotfirst-final | Update.tla / Update_reach_LeaderNotFirst.cfg | BFS | 2s | 1987 | 1302 | 8 | REACH WITNESS (NotReachLeaderNotFirst) |
| upd-reach-upgraded-final | Update.tla / Update_reach_UpgradedWithFollowerProgress.cfg | BFS | 2s | 537 | 365 | 8 | REACH WITNESS (NotReachUpgradedWithFollowerProgress) |
| upd-reach-jointcommit-final | Update.tla / Update_reach_JointQuorumCommit.cfg | BFS | 2s | 556 | 378 | 8 | REACH WITNESS (NotReachJointQuorumCommit) |
| upd-reach-progresscommit-final | Update.tla / Update_reach_ProgressCommit.cfg | BFS | 1s | 333 | 228 | 7 | REACH WITNESS (NotReachProgressCommit) |
| upd-reach-reelected | Update.tla / Update_reach_ReelectedLeaderProgress.cfg | BFS | 5s | 571 | 347 | 8 | REACH WITNESS (NotReachReelectedLeaderProgress) |

Reading guide: `VIOLATION ProgressSortedAboveCommitted` / `CommitWitnessSound`
rows are finding **MC-1** (Case C). `REACH WITNESS` rows are expected
violations of `NotReach*` canaries (non-vacuity evidence for S1–S4, U1–U4).
`*_residual` cfgs omit only the three properties MC-1 violates. The discharge
obligation `DischargeContext` had no violation in 14.3M states (budget-limited),
so the open-focused result is accepted only within that budget.

### Earlier runs (superseded or pre-revision; kept as evidence)

| Run | Module / cfg | Mode | Elapsed | Distinct states | Queue left | Depth | Outcome |
|---|---|---|---:|---:|---:|---:|---|
| upd-full-bfs | Update.tla / Update_full.cfg | BFS | 5s | 13340 | 9998 | 10 | VIOLATION OneOutstandingMembership |
| upd-focused-bfs | Update.tla / Update_focused.cfg | BFS | 5s | 10859 | 8008 | 10 | VIOLATION OneOutstandingMembership |
| upd-open-bfs | Update.tla / Update_open.cfg | BFS | 6s | 12440 | 9308 | 10 | VIOLATION ProgressSortedAboveCommitted |
| upd-hunt-u1-bfs | Update.tla / Update_hunt_u1_membership_progress.cfg | BFS | 2s | 3706 | 2336 | 10 | VIOLATION ProgressSortedAboveCommitted |
| upd-hunt-u1-consequence-bfs | Update.tla / Update_hunt_u1_consequence.cfg | BFS | 4s | 42656 | 23725 | 13 | VIOLATION CommitWitnessSound |
| mc-hunt-s2-bfs | MC.tla / MC_hunt_s2_membership.cfg | BFS | 6s | 26698 | 15537 | 12 | VIOLATION CommitWitnessSound |
| upd-hunt-u2-bfs | Update.tla / Update_hunt_u2_membership_client_loss.cfg | BFS | 4s | 4419 | 3193 | 9 | VIOLATION ProgressSortedAboveCommitted |
| upd-hunt-u4-bfs | Update.tla / Update_hunt_u4_reelection_crash.cfg | BFS | 6s | 20881 | 15702 | 9 | VIOLATION ProgressSortedAboveCommitted |
| mc-main-r1 | MC.tla / MC.cfg | BFS | 94s | 4234312 | 0 | 31 | COMPLETE, no error |
| mc-hunt-s1-bfs | MC.tla / MC_hunt_s1_progress.cfg | BFS | 1183s | 8142061 | 1449653 | 24 | no error; BUDGET-LIMITED (queue not empty) |
| mc-hunt-s3-bfs | MC.tla / MC_hunt_s3_follower_commit.cfg | BFS | 605s | 4234312 | 0 | 31 | COMPLETE, no error |
| mc-hunt-s4-bfs | MC.tla / MC_hunt_s4_election.cfg | BFS | 1185s | 12779532 | 5083846 | 20 | no error; BUDGET-LIMITED (queue not empty) |
| mc-reach-leader | MC.tla / MC_reach_leader.cfg | BFS | 2s | 6 | 1 | 3 | REACH WITNESS (NotReachLeader) |
| mc-reach-commit | MC.tla / MC_reach_commit.cfg | BFS | 1s | 159 | 95 | 7 | REACH WITNESS (NotReachCommitWitness) |
| mc-reach-membership | MC.tla / MC_reach_membership.cfg | BFS | 2s | 35 | 19 | 5 | REACH WITNESS (NotReachOutstandingMembership) |
| upd-reach-leadernotfirst | Update.tla / Update_reach_LeaderNotFirst.cfg | BFS | 3s | 2083 | 1340 | 9 | REACH WITNESS (NotReachLeaderNotFirst) |
| upd-reach-upgraded | Update.tla / Update_reach_UpgradedWithFollowerProgress.cfg | BFS | 3s | 717 | 484 | 8 | REACH WITNESS (NotReachUpgradedWithFollowerProgress) |
| upd-reach-jointcommit | Update.tla / Update_reach_JointQuorumCommit.cfg | BFS | 2s | 667 | 451 | 8 | REACH WITNESS (NotReachJointQuorumCommit) |
| upd-reach-progresscommit | Update.tla / Update_reach_ProgressCommit.cfg | BFS | 2s | 372 | 255 | 7 | REACH WITNESS (NotReachProgressCommit) |

`upd-full-bfs` / `upd-focused-bfs` produced the Case A counterexample for V0
`OneOutstandingMembership` (crash resets the volatile commit; see changelog);
all other earlier runs were repeated on the final artifacts except
`mc-hunt-s1-bfs` and `mc-hunt-s4-bfs`, which ran before the observer-only
`commitHigh` ghost was added (their actions and enabled properties are
unchanged by it; their final-artifact counterparts are the `-sim` runs).

## Coverage limits (all results LIMITED_COVERAGE)

- 3 model servers, MaxTerm ≤ 2, MaxIndex ≤ 2, ≤ 3 elections, ≤ 1 membership
  change, ≤ 1 crash, ≤ 1 loss, message buffer ≤ 4; most BFS runs stopped at
  their 20–25 minute budget with states queued; simulations sampled depth-100
  paths for ~15 minutes each.
- MC-1's applied-entry divergence needs ≥ 5 voters; it was shown on the real
  runtime (`spec/confirmation-MC-1.md`), not in the 3-server model.
- Trace validation covers Engine-level unit environments; the async runtime
  paths listed above are not trace-validated.
- Snapshot, log purge, apply/state machine, timers, and the follower
  "last two memberships" bookkeeping remain outside the modeled scope.
