| Run | Module | Config | Mode | Budget | Result | Coverage |
|---|---|---|---|---|---|---|
| discharge_negcontrol | Update.tla | Update_discharge_negcontrol.cfg | BFS | 300s x2 | VIOLATION: Action property DischargeNegativeControl is violated. (3-state trace) | 25 gen / 22 distinct / 17 queued, depth 3 |
| final_hunt_us4_guided | Update.tla | Update_hunt_us4_guided.cfg | BFS | 1800s x8 | VIOLATION: Invariant ReadIndexFreshness is violated. (37-state trace) | 25,319,382 gen / 3,928,358 distinct / 639,231 queued, depth 41 |
| final_mc_standard | MC.tla | MC.cfg | BFS | 1800s x8 | no violation, EXHAUSTED | 22,496,273 gen / 4,291,336 distinct / 0 queued, depth 31 |
| final_update_discharge | Update.tla | Update_discharge.cfg | BFS | 600s x4 | no violation, LIMITED_COVERAGE (time budget) | 6,097,105 gen / 1,492,681 distinct / 764,829 queued, depth 14 |
| final_update_focused | Update.tla | Update_focused.cfg | BFS | 1200s x8 | VIOLATION: Invariant ReadDeliveryJustifiedFresh is violated. (22-state trace) | 3,319,245 gen / 869,112 distinct / 449,206 queued, depth 23 |
| final_update_focused_reset | Update.tla | Update_focused_reset.cfg | BFS | 1200s x8 | VIOLATION: Invariant ReadDeliveryJustifiedFresh is violated. (21-state trace) | 10,462,487 gen / 2,411,394 distinct / 1,308,388 queued, depth 21 |
| final_update_full | Update.tla | Update_full.cfg | BFS | 1800s x6 | no violation, LIMITED_COVERAGE (time budget) | 71,213,499 gen / 15,646,198 distinct / 8,505,280 queued, depth 21 |
| final_update_open | Update.tla | Update_open.cfg | BFS | 900s x4 | no violation, LIMITED_COVERAGE (time budget) | 73,611,246 gen / 3,193,264 distinct / 1,654,423 queued, depth 18 |
| hunt_us4_focused | Update.tla | Update_hunt_us4_focused.cfg | BFS | 1500s x8 | no violation, LIMITED_COVERAGE (time budget) | 39,482,419 gen / 10,377,769 distinct / 5,110,614 queued, depth 26 |
| hunt_us4_guided | Update.tla | Update_hunt_us4_guided.cfg | BFS | 1800s x8 | VIOLATION: Invariant ReadIndexFreshness is violated. (37-state trace) | 25,393,991 gen / 3,946,146 distinct / 645,422 queued, depth 39 |
| mc_complete_core | MC.tla | MC_complete_core.cfg | BFS | 900s x4 | no violation, EXHAUSTED | 109,936 gen / 26,255 distinct / 0 queued, depth 23 |
| mc_hunt_s1_election | MC.tla | MC_hunt_s1_election.cfg | BFS | 900s x4 | no violation, EXHAUSTED | 71,848 gen / 18,550 distinct / 0 queued, depth 18 |
| mc_hunt_s2_replication | MC.tla | MC_hunt_s2_replication.cfg | BFS | 900s x4 | no violation, LIMITED_COVERAGE (time budget) | 19,867,489 gen / 4,524,454 distinct / 2,518,664 queued, depth 19 |
| mc_hunt_s3_quorum | MC.tla | MC_hunt_s3_quorum.cfg | BFS | 900s x4 | no violation, EXHAUSTED | 25,861 gen / 4,912 distinct / 0 queued, depth 20 |
| mc_hunt_s4_readindex | MC.tla | MC_hunt_s4_readindex.cfg | BFS | 900s x4 | no violation, LIMITED_COVERAGE (time budget) | 26,189,018 gen / 4,620,656 distinct / 3,115,519 queued, depth 20 |
| mc_hunt_s5_forwarded_read | MC.tla | MC_hunt_s5_forwarded_read.cfg | BFS | 900s x4 | no violation, LIMITED_COVERAGE (time budget) | 13,793,922 gen / 3,094,870 distinct / 1,639,559 queued, depth 24 |
| mc_standard | MC.tla | MC.cfg | BFS | 1800s x8 | no violation, EXHAUSTED | 22,496,273 gen / 4,291,336 distinct / 0 queued, depth 31 |
| reach_update_freed | Update.tla | Update_reach_freed.cfg | BFS | 120s x4 | VIOLATION: Invariant HuntReadFreed is violated. (16-state trace) | 1,655 gen / 627 distinct / 263 queued, depth 17 |
| reach_update_reenqueue | Update.tla | Update_reach_reenqueue.cfg | BFS | 600s x1 | VIOLATION: Invariant HuntReadReenqueue is violated. (16-state trace) | 4,098 gen / 1,309 distinct / 660 queued, depth 16 |
| reach_update_reset_drop | Update.tla | Update_reach_reset_drop.cfg | BFS | 600s x1 | VIOLATION: Invariant HuntResetDropsRead is violated. (15-state trace) | 2,566 gen / 897 distinct / 415 queued, depth 15 |
| reach_update_reuse_release | Update.tla | Update_reach_reuse_release.cfg | BFS | 600s x1 | VIOLATION: Invariant HuntReuseRelease is violated. (18-state trace) | 19,593 gen / 5,477 distinct / 2,795 queued, depth 18 |
| reach_v0_s1_leader | MC.tla | Reach_s1_leader.cfg | BFS | 600s x2 | VIOLATION: Invariant HuntLeader is violated. (7-state trace) | 2,169 gen / 788 distinct / 471 queued, depth 8 |
| reach_v0_s2_commit | MC.tla | Reach_s2_commit.cfg | BFS | 600s x2 | VIOLATION: Invariant HuntCommit is violated. (12-state trace) | 149,059 gen / 37,680 distinct / 18,303 queued, depth 12 |
| reach_v0_s3_quorum | MC.tla | Reach_s3_quorum.cfg | BFS | 600s x2 | VIOLATION: Invariant HuntQuorumCheck is violated. (8-state trace) | 183 gen / 74 distinct / 25 queued, depth 9 |
| reach_v0_s4_ready_read | MC.tla | Reach_s4_ready_read.cfg | BFS | 600s x2 | VIOLATION: Invariant HuntReadyRead is violated. (17-state trace) | 1,314,409 gen / 249,390 distinct / 152,160 queued, depth 17 |
| reach_v0_s5_forwarded_read | MC.tla | Reach_s5_forwarded_read.cfg | BFS | 600s x2 | VIOLATION: Invariant HuntReadResponse is violated. (16-state trace) | 56,827 gen / 14,725 distinct / 7,745 queued, depth 16 |
| sim_hunt_s2_replication | MC.tla | MC_hunt_s2_replication.cfg | simulation | 600s x2 | no violation, LIMITED_COVERAGE (time budget) | 4610513 states checked, 34668 traces (depth<=100) |
| sim_hunt_s4_readindex | MC.tla | MC_hunt_s4_readindex.cfg | simulation | 600s x2 | no violation, LIMITED_COVERAGE (time budget) | 6759797 states checked, 170070 traces (depth<=100) |
| sim_hunt_s5_forwarded_read | MC.tla | MC_hunt_s5_forwarded_read.cfg | simulation | 600s x2 | no violation, LIMITED_COVERAGE (time budget) | 3959099 states checked, 30096 traces (depth<=100) |
| sim_hunt_us4_focused | Update.tla | Update_hunt_us4_focused.cfg | simulation | 600s x2 | no violation, LIMITED_COVERAGE (time budget) | 5006336 states checked, 30756 traces (depth<=100) |
| sim_mc_standard | MC.tla | MC.cfg | simulation | 1200s x4 | no violation, LIMITED_COVERAGE (time budget) | 20733181 states checked, 246708 traces (depth<=100) |
| sim_update_full | Update.tla | Update_full.cfg | simulation | 900s x4 | VIOLATION: Invariant ReadDeliveryJustifiedFresh is violated. (44-state trace) | 310313 states checked, 2284 traces (depth<=100) |
| sim_us4_full | Update.tla | Update_hunt_us4_sim.cfg | simulation | 1500s x8 | no violation, LIMITED_COVERAGE (time budget) | 36388075 states checked, 263174 traces (depth<=100) |
| update_discharge | Update.tla | Update_discharge.cfg | BFS | 900s x4 | no violation, LIMITED_COVERAGE (time budget) | 6,502,140 gen / 1,594,448 distinct / 818,813 queued, depth 14 |
| update_focused | Update.tla | Update_focused.cfg | BFS | 1800s x8 | VIOLATION: Invariant ReadDeliveryJustifiedFresh is violated. (22-state trace) | 2,720,506 gen / 716,796 distinct / 369,798 queued, depth 24 |
| update_focused_reset | Update.tla | Update_focused_reset.cfg | BFS | 1200s x4 | VIOLATION: Invariant ReadDeliveryJustifiedFresh is violated. (21-state trace) | 10,042,249 gen / 2,323,855 distinct / 1,267,584 queued, depth 21 |
| update_full | Update.tla | Update_full.cfg | BFS | 1800s x8 | no violation, LIMITED_COVERAGE (time budget) | 77,133,266 gen / 16,925,760 distinct / 9,192,502 queued, depth 21 |
| update_open | Update.tla | Update_open.cfg | BFS | 1200s x4 | no violation, LIMITED_COVERAGE (time budget) | 78,069,383 gen / 3,395,199 distinct / 1,767,705 queued, depth 17 |

Ghost-fix boundary: `base.tla` HandleReadIndexResponse ghost correspondence was
repaired at 2026-11-18T01:13:24-06:00 (Case B, ghost-only). Runs started before it:
hunt_us4_guided, mc_complete_core, mc_hunt_s1_election, mc_hunt_s2_replication, mc_hunt_s4_readindex, mc_standard, reach_update_freed, reach_update_reenqueue, reach_update_reset_drop, reach_update_reuse_release, reach_v0_s1_leader, reach_v0_s2_commit, reach_v0_s3_quorum, reach_v0_s4_ready_read, sim_mc_standard, update_discharge, update_focused, update_focused_reset, update_full, update_open.
Their real-state exploration is identical and every property is monotone in the
changed ghost fields, so their no-violation results remain sound and their
local-read counterexamples are unaffected; the affected campaigns were rerun on
the final artifacts (`final_*`, `hunt_us4_focused`, `sim_us4_full`, s5 and later
runs). Pre-fix artifact runs that hit the ghost defect are kept under
`output/mc/superseded/`.

Result vocabulary: EXHAUSTED = TLC finished with 0 states left on queue;
LIMITED_COVERAGE = stopped by its time budget (`-Dtlc2.TLC.stopAfter`), not a proof.
