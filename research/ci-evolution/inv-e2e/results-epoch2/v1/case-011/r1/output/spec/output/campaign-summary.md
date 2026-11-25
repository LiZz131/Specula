| Run | Config | Mode | Verdict | Violation | Distinct states | Depth | Queue left |
|---|---|---|---|---|---|---|---|
| MC-membership | MC-membership.cfg | BFS | LIMITED_COVERAGE(queue=5452163) (tlc rc=0) | - | 13485457 | 23 | 5452163 |
| MC | MC.cfg | BFS | LIMITED_COVERAGE(queue=8388541) (tlc rc=0) | - | 15748310 | 17 | 8388541 |
| Update_discharge | Update_discharge.cfg | BFS | LIMITED_COVERAGE(queue=4190952) (tlc rc=0) | - | 7727867 | 15 | 4190952 |
| Update_focused-sim | Update_focused.cfg | simulation | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 396619 | - | - |
| Update_focused | Update_focused.cfg | BFS | LIMITED_COVERAGE(queue=9207761) (tlc rc=0) | - | 15894086 | 15 | 9207761 |
| Update_focused_cont | Update_focused_cont.cfg | BFS | LIMITED_COVERAGE(queue=6833262) (tlc rc=0) | - | 11635196 | 13 | 6833262 |
| Update_full | Update_full.cfg | BFS | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 10437408 | 15 | 6126155 |
| Update_full_cont1 | Update_full_cont1.cfg | BFS | LIMITED_COVERAGE(queue=10708645) (tlc rc=0) | - | 18617678 | 15 | 10708645 |
| Update_full_cont2-sim | Update_full_cont2.cfg | simulation | SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0) | - | 64640767 | - | - |
| Update_full_cont2 | Update_full_cont2.cfg | BFS | LIMITED_COVERAGE(queue=11532575) (tlc rc=0) | - | 20065101 | 16 | 11532575 |
| Update_open-evalerror | Update_open.cfg | BFS | TLC EVALUATION ERROR in EnvUpdate (effectiveConfig'[i] read before assignment), not a property violation; fixed in Update.tla and rerun as mc-Update_open.log | - | 494459 | 12 | 286449 |
| Update_open | Update_open.cfg | BFS | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 4743269 | 16 | 2530001 |
| Update_open_cont | Update_open_cont.cfg | BFS | LIMITED_COVERAGE(queue=7629658) (tlc rc=0) | - | 14612340 | 17 | 7629658 |
| canary-CanaryNoFollowerLog | Canary_CanaryNoFollowerLog.cfg | BFS | VIOLATION (tlc rc=12) | CanaryNoFollowerLog | 60879 | 14 | 24734 |
| canary-CanaryNoGrantedPreVoteResp | Canary_CanaryNoGrantedPreVoteResp.cfg | BFS | VIOLATION (tlc rc=12) | CanaryNoGrantedPreVoteResp | 45 | 5 | 27 |
| canary-CanaryNoLeader | Canary_CanaryNoLeader.cfg | BFS | VIOLATION (tlc rc=12) | CanaryNoLeader | 9566 | 11 | 4722 |
| canary-CanaryNoLeaderWithPreCandidate | Canary_CanaryNoLeaderWithPreCandidate.cfg | BFS | VIOLATION (tlc rc=12) | CanaryNoLeaderWithPreCandidate | 21983 | 12 | 9851 |
| canary-CanaryNoPreCandidate | Canary_CanaryNoPreCandidate.cfg | BFS | VIOLATION (tlc rc=12) | CanaryNoPreCandidate | 2 | 2 | 0 |
| canary-CanaryNoPreCandidateCleared | Canary_CanaryNoPreCandidateCleared.cfg | BFS | VIOLATION (tlc rc=12) | CanaryNoPreCandidateCleared | 63954 | 15 | 26016 |
| canary-CanaryNoPreVoteTally | Canary_CanaryNoPreVoteTally.cfg | BFS | LIMITED_COVERAGE(queue=471) (tlc rc=143) | - | 2133625 | 21 | 903471 |
| canary-CanaryNoRejectedPreVoteResp | Canary_CanaryNoRejectedPreVoteResp.cfg | BFS | VIOLATION (tlc rc=12) | CanaryNoRejectedPreVoteResp | 1035 | 8 | 518 |
| hunt-leader-demote-bfs | MC_hunt_prevote_leader_demote.cfg | BFS | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 98258 | 17 | 39677 |
| hunt-leader-demote-cont-sim | MC_hunt_prevote_leader_demote_cont.cfg | simulation | SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0) | - | 47549009 | - | - |
| hunt-leader-demote-cont | MC_hunt_prevote_leader_demote_cont.cfg | BFS | LIMITED_COVERAGE(queue=5938669) (tlc rc=0) | - | 15182176 | 25 | 5938669 |
| hunt-livelock-bfs | MC_hunt_prevote_livelock.cfg | BFS | LIMITED_COVERAGE(queue=5559486) (tlc rc=0) | - | 13578324 | 21 | 5559486 |
| hunt-livelock-cont-sim | MC_hunt_prevote_livelock_cont.cfg | simulation | SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0) | - | 36665228 | - | - |
| hunt-livelock-directed-bfs | MC_hunt_prevote_livelock_directed_bfs.cfg | BFS | LIMITED_COVERAGE(queue=838) (tlc rc=143) | - | 1219018 | 18 | 491838 |
| hunt-livelock-directed-sim | MC_hunt_prevote_livelock_directed.cfg | simulation | INCOMPLETE(rc=143) (tlc rc=143) | - | 6044708 | - | - |
| hunt-livelock-phased-bfs | MC_hunt_prevote_livelock_phased.cfg | BFS | VIOLATION (tlc rc=12) | NoPermanentPreVoteLivelock | 4086089 | 26 | 1505969 |
