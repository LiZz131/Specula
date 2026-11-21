# Bug Report — OpenRaft V1 incremental run (artifact `baseline` ce863f4 -> `update` aa05a38)

## Summary

- Source disposition: MODEL_CHANGE_REQUIRED (reference, MC, Trace and Update suites revised).
- Scenarios tested: 4 inherited (S1–S4) + 4 update Scenarios (U-S1–U-S4).
- Bugs found: **0**. No implementation-caused (Case C) counterexample was found.
- All model-checking results are bounded: **LIMITED_COVERAGE**, not proof. Runs that stopped at their 30-minute budget still had states queued, even where TLC printed "Model checking completed" (which `-Dtlc2.TLC.stopAfter` prints on a timed stop).
- Counterexamples that were found during the campaign were classified as specification/property issues and are not findings:
  - `OneOutstandingMembership` with crashes: Case A, pre-existing restart-path mismatch.
  - `MembershipOrder` in the first focused run: Case B, pre-existing follower-membership abstraction, repaired.

  Details are in `spec/changelog.md` Round 2; the superseded logs are in `spec/output/superseded-prerepair/`.

## Not Reproduced (all on the repaired, final suite; 3 servers)

| Scenario | Config (module) | Mode | States explored | Queue left | Diameter | Result |
|---|---|---|---:|---:|---:|---|
| standard | MC.cfg (MC) | BFS | 8,115 distinct | 0 | 20 | no violation (exhaustive within bounds) |
| full update | Update_full.cfg (Update, MCNext) | BFS 30 min | 24,663,954 distinct | 12,095,611 | 18 | no violation, budget-limited |
| full update | Update_full.cfg | simulation 30 min, depth 100 | 32,436,515 states | n/a | n/a | no violation |
| focused | Update_focused.cfg (FocusedNext) | BFS 30 min | 19,687,489 distinct | 10,663,694 | 18 | no violation, budget-limited |
| focused | Update_focused.cfg | simulation 30 min | 26,514,630 states | n/a | n/a | no violation |
| open | Update_open.cfg (OpenNext = focused + EnvUpdate) | BFS 30 min | 20,265,105 distinct | 10,078,493 | 18 | no violation, budget-limited |
| open | Update_open.cfg | simulation 30 min | 31,777,025 states | n/a | n/a | no violation |
| discharge | Update_discharge.cfg (DischargeContext over MCNext) | BFS 30 min | 15,864,326 distinct | 8,134,770 | 17 | rely holds on all explored omitted-context steps, budget-limited |
| S1 progress/commit | MC_hunt_s1_progress.cfg (Update) | BFS | 17,130 distinct | 0 | 20 | no violation (exhaustive within bounds) |
| S1 | same | simulation 30 min | 48,925,757 states | n/a | n/a | no violation |
| S2 membership | MC_hunt_s2_membership.cfg (Update) | BFS | 55,571 distinct | 0 | 23 | no violation (exhaustive within bounds) |
| S2 | same | simulation 30 min | 46,874,143 states | n/a | n/a | no violation |
| S3 follower commit | MC_hunt_s3_follower_commit.cfg (MC) | BFS | 8,115 distinct | 0 | 20 | no violation (exhaustive within bounds) |
| S3 | same | simulation 30 min | 52,426,886 states | n/a | n/a | no violation |
| S4 elections/crash | MC_hunt_s4_election.cfg (MC) | BFS | 30,606 distinct | 0 | 22 | no violation (exhaustive within bounds) |
| S4 | same | simulation 30 min | 67,487,957 states | n/a | n/a | no violation |
| U-S1 append commit | MC_hunt_u1_append_commit.cfg (Update) | BFS 30 min | 11,684,632 distinct | 5,565,946 | 20 | no violation, budget-limited |
| U-S1 | same | simulation 30 min | 26,272,425 states | n/a | n/a | no violation |
| U-S2 re-election | MC_hunt_u2_reelection.cfg (Update) | BFS 30 min | 19,260,214 distinct | 4,582,085 | 24 | no violation, budget-limited |
| U-S2 | same | simulation 30 min | 39,228,699 states | n/a | n/a | no violation |
| U-S3 follower promotion | MC_hunt_u3_follower_promotion.cfg (Update) | BFS 30 min | 16,854,823 distinct | 7,287,285 | 19 | no violation, budget-limited |
| U-S3 | same | simulation 30 min | 38,701,271 states | n/a | n/a | no violation |
| V0 broad probe | MC_scale.cfg (MC) | BFS 30 min | see `spec/output/upd-mc-scale-bfs.log` | | | see validation-summary.md |

## Reachability (non-vacuity) witnesses on the final suite

| Canary | Config | Result |
|---|---|---|
| leader | MC_reach_leader.cfg | reached (depth 3) |
| commit witness | MC_reach_commit.cfg | reached (depth 7) |
| outstanding membership | MC_reach_membership.cfg | reached (depth 4) |
| U-S4 progress quorum-set upgrade | MC_reach_u4_upgrade.cfg | reached (depth 4) |
| U-S2 re-elected leader with older witness | MC_reach_u2_reelection.cfg | reached (depth 11) |
| U-S1 commit advanced by a leader append | MC_reach_u1_append_commit.cfg (`NoCommitAtLeaderAppend`) | reached (depth 13): the leader proposes `{n1,n3}` after `{n2,n3}` and commits index 1 at append time from n3's earlier acknowledgement |
| two simultaneous leaders / two committed nodes (evidence only) | MC_reach_ev_TwoLeaders.cfg / MC_reach_ev_TwoCommitted.cfg | reached |
| U-S3 covered-but-unpromoted membership (probe) | MC_reach_u3_follower_promotion.cfg | **not reached** within budget (8,633,829 distinct, queue 4,076,965). The real code produces this state only from a hand-built fixture (`spec/evidence/code-observation/new.log`). The U-S3 property checks therefore exercise only the promotion-on-advance branch. |

Logs: `spec/output/upd-*.log`; counterexample/witness JSON: `spec/output/upd-*.trace.json`.

## Coverage limits

- 3 servers; small term, index and fault budgets. Most update campaigns are budget-limited.
- `RejectAppendConflict` / `DiscardNegativeAck` had no positive coverage at the explored depths (`spec/output/upd-full-coverage.summary.md`).
- `OneOutstandingMembership` is checked only in crash-free configurations (restart Case A).
- Membership transitions in MC are arbitrary `AllowedConfigs` changes (V0 abstraction). In a 3-server universe every pair of configurations has intersecting quorums.
- RaftCore paths that change vote/role without clearing Engine leader data (install_snapshot, revert-to-follower) are not in the modeled Next relation.

## Spec fixes during hunting

See `spec/changelog.md` Round 2:
- Case A wiring of `OneOutstandingMembership` (restart).
- Case B repair of the follower membership and truncation abstraction: per-entry membership payload `logConfig`, entries carried in messages, new structural invariant `EffectiveIsLastLogMembership`.
- Explicit `IF` for a Nil-indexed guard.
