| Run | Config | Mode | Outcome | States | Depth | Time |
|---|---|---|---|---|---|---|
| hunt_v0_s1_election | `MC_hunt_s1_election.cfg` | bfs | no violation; state space exhausted | 71,848 gen / 18,550 distinct / 0 queued | 18 | 10s |
| hunt_v0_s2_replication | `MC_hunt_s2_replication.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 7,132,750 gen / 1,697,199 distinct / 970,719 queued | 17 | 10min 02s |
| hunt_v0_s3_quorum | `MC_hunt_s3_quorum.cfg` | bfs | no violation; state space exhausted | 25,861 gen / 4,912 distinct / 0 queued | 20 | 10s |
| hunt_v0_s4_readindex | `MC_hunt_s4_readindex.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 6,221,314 gen / 1,217,620 distinct / 824,871 queued | 19 | 10min 03s |
| hunt_v0_s5_forwarded_read | `MC_hunt_s5_forwarded_read.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 6,122,364 gen / 1,310,561 distinct / 708,637 queued | 22 | 10min 01s |
| mc_complete_core | `MC_complete_core.cfg` | bfs | no violation; state space exhausted | 109,936 gen / 26,255 distinct / 0 queued | 23 | 23s |
| mc_standard | `MC.cfg` | bfs | no violation; state space exhausted | 22,496,273 gen / 4,291,336 distinct / 0 queued | 31 | 13min 49s |
| reach_update_forwarded_freed | `Reach_update_forwarded_freed.cfg` | bfs | VIOLATION: Invariant HuntForwardedFreedRead is violated. | 4,500 gen / 1,406 distinct / 710 queued | 17 | 03s |
| reach_update_freed | `Reach_update_freed.cfg` | bfs | VIOLATION: Invariant HuntReadFreed is violated. | 3,203 gen / 1,075 distinct / 536 queued | 16 | 01s |
| reach_update_leader_stepdown | `Reach_update_leader_stepdown.cfg` | bfs | VIOLATION: Invariant HuntReadLeaderSteppedDown is violated. | 3,000 gen / 1,030 distinct / 469 queued | 16 | 04s |
| reach_update_reuse | `Reach_update_reuse.cfg` | bfs | VIOLATION: Invariant HuntReadReuse is violated. | 4,494 gen / 1,408 distinct / 707 queued | 17 | 04s |
| reach_update_reuse_served | `Reach_update_reuse_served.cfg` | bfs | VIOLATION: Invariant HuntReuseServed is violated. | 20,463 gen / 5,721 distinct / 2,929 queued | 18 | 07s |
| reach_update_stale_ack | `Reach_update_stale_ack.cfg` | bfs | VIOLATION: Invariant HuntStaleAck is violated. | 82,265 gen / 22,953 distinct / 11,610 queued | 21 | 15s |
| reach_v0_s1_leader | `Reach_s1_leader.cfg` | bfs | VIOLATION: Invariant HuntLeader is violated. | 1,750 gen / 651 distinct / 410 queued | 7 | 04s |
| reach_v0_s2_commit | `Reach_s2_commit.cfg` | bfs | VIOLATION: Invariant HuntCommit is violated. | 141,802 gen / 35,802 distinct / 17,176 queued | 12 | 19s |
| reach_v0_s3_quorum | `Reach_s3_quorum.cfg` | bfs | VIOLATION: Invariant HuntQuorumCheck is violated. | 180 gen / 72 distinct / 24 queued | 9 | 03s |
| reach_v0_s4_ready_read | `Reach_s4_ready_read.cfg` | bfs | VIOLATION: Invariant HuntReadyRead is violated. | 1,289,277 gen / 251,992 distinct / 157,355 queued | 17 | 02min 04s |
| reach_v0_s5_forwarded_read | `Reach_s5_forwarded_read.cfg` | bfs | VIOLATION: Invariant HuntReadResponse is violated. | 59,168 gen / 15,246 distinct / 7,951 queued | 16 | 12s |
| upd_discharge | `Update_discharge.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 20,304,646 gen / 4,909,615 distinct / 2,928,560 queued | 19 | 20min 03s |
| upd_focused | `Update_focused.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 7,687,404 gen / 1,751,697 distinct / 992,380 queued | 19 | 04min 27s |
| upd_focused_rest | `Update_focused_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 40,816,616 gen / 8,737,524 distinct / 4,908,095 queued | 23 | 20min 03s |
| upd_focused_rest_sim | `Update_focused_rest.cfg` | sim | no violation; LIMITED_COVERAGE (time budget) | 19,321,257 states; 145,543 traces | - | 20min 01s |
| upd_full | `Update_full.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 40,359,915 gen / 9,298,689 distinct / 5,440,409 queued | 21 | 20min 02s |
| upd_full_rest | `Update_full_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 31,314,432 gen / 7,522,045 distinct / 4,541,004 queued | 19 | 20min 02s |
| upd_full_rest_sim | `Update_full_rest.cfg` | sim | no violation; LIMITED_COVERAGE (time budget) | 17,636,381 states; 107,551 traces | - | 20min 01s |
| upd_full_sim | `Update_full.cfg` | sim | VIOLATION: Invariant UpdReadAckFresh is violated. | 3,129 states; 21 traces | - | 04s |
| upd_hunt_forwarded | `Update_hunt_forwarded.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 414,826 gen / 99,013 distinct / 57,679 queued | 21 | 32s |
| upd_hunt_forwarded_rest | `Update_hunt_forwarded_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 32,484,511 gen / 6,905,928 distinct / 4,136,422 queued | 27 | 20min 02s |
| upd_hunt_linearizable | `Update_hunt_linearizable.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 35,496,927 gen / 8,948,688 distinct / 4,150,285 queued | 27 | 20min 02s |
| upd_hunt_linearizable_directed | `Update_hunt_linearizable_directed.cfg` | bfs | VIOLATION: Invariant UpdReadIndexLinearizable is violated. | 6,483,193 gen / 1,363,514 distinct / 147,723 queued | 36 | 02min 53s |
| upd_hunt_linearizable_sim | `Update_hunt_linearizable.cfg` | sim | no violation; LIMITED_COVERAGE (time budget) | 54,550,274 states; 335,383 traces | - | 30min 01s |
| upd_hunt_stale_ack | `Update_hunt_stale_ack.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 76,816 gen / 21,691 distinct / 10,875 queued | 22 | 09s |
| upd_open | `Update_open.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 21,865,705 gen / 4,960,978 distinct / 2,861,236 queued | 19 | 19min 36s |
| upd_open_rest | `Update_open_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 44,063,666 gen / 9,714,673 distinct / 5,549,063 queued | 20 | 20min 02s |
