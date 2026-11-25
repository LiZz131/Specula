| Run | Cfg | Mode | Status | Distinct | Depth | Queue left | Violated / trace |
|---|---|---|---|---|---|---|---|
| mc-standard | MC.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 14,315,098 | 16 | 7,859,902 | - |
| mc-membership | MC-membership.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 7,675,374 | 23 | 2,341,889 | - |
| sim-mc-standard | MC.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 26,905,845 checked / 294,977 traces | mean len 41, bound 60 | - | - |
| update-full | Update-full.cfg | BFS | VIOLATION | 4,386,936 | 13 | 2,585,421 | TickPreVoteNeverDeposesLeader (13 states) |
| update-full-noU2 | Update-full-noU2.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 21,452,958 | 16 | 11,594,404 | - |
| sim-update-full-noU2 | Update-full-noU2.cfg | simulation | VIOLATION | 8,002,533 checked / 87,693 traces | mean len 41, bound 60 | - | PreVoteTrackerWellFormed (31 states) |
| sim-update-full-noU2-noMC2 | Update-full-noU2-noMC2.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 60,295,516 checked / 661,345 traces | mean len 35, bound 60 | - | - |
| update-full-enabled | Update-full-enabled.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 17,960,781 | 19 | 10,470,020 | - |
| sim-update-full-enabled | Update-full-enabled.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 21,700,039 checked / 293,788 traces | mean len 43, bound 60 | - | - |
| update-focused | Update-focused.cfg | BFS | VIOLATION | 5,254,540 | 13 | 3,056,771 | TickPreVoteNeverDeposesLeader (12 states) |
| update-open | Update-open.cfg | BFS | VIOLATION | 4,980,338 | 13 | 2,925,782 | TickPreVoteNeverDeposesLeader (12 states) |
| update-discharge | Update-discharge.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 6,905,721 | 13 | 3,946,275 | - |
| hunt-prevote-leader | MC_hunt_prevote_leader.cfg | BFS | VIOLATION | 4,237,363 | 16 | 2,032,083 | TickPreVoteNeverDeposesLeader (14 states) |
| hunt-prevote-term | MC_hunt_prevote_term.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 13,862,983 | 15 | 7,214,172 | - |
| sim-hunt-prevote-term | MC_hunt_prevote_term.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 22,129,714 checked / 281,721 traces | mean len 43, bound 60 | - | - |
| hunt-prevote-membership | MC_hunt_prevote_membership.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 9,377,310 | 20 | 3,838,822 | - |
| sim-hunt-prevote-membership | MC_hunt_prevote_membership.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 64,041,586 checked / 1,036,369 traces | mean len 37, bound 60 | - | - |
| hunt-prevote-stale-grant | MC_hunt_prevote_stale_grant.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 10,720,816 | 19 | 6,118,095 | - |
| sim-hunt-prevote-stale-grant | MC_hunt_prevote_stale_grant.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 28,008,777 checked / 370,587 traces | mean len 35, bound 60 | - | - |
| hunt-prevote-stale-grant-tight | MC_hunt_prevote_stale_grant_tight.cfg | BFS | VIOLATION | 3,312,276 | 20 | 2,046,878 | PreVoteTrackerWellFormed (17 states) |
| hunt-prevote-restart | MC_hunt_prevote_restart.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 15,245,205 | 14 | 7,871,295 | - |
| canary-leader-tick-round | Canary-leader-tick-round.cfg | BFS | VIOLATION | 53,740 | 12 | 25,786 | CanaryNoLeaderWithTickPreRound (11 states) |
| canary-joint-round | Canary-joint-round.cfg | BFS | VIOLATION | 47 | 7 | 21 | CanaryNoJointPreVoteRound (6 states) |
| canary-rejected-resp | Canary-rejected-resp.cfg | BFS | VIOLATION | 251 | 5 | 216 | CanaryNoRejectedPreVoteResponse (4 states) |
| canary-PreVoteElection | Canary-PreVoteElection.cfg | BFS | VIOLATION | 669 | 6 | 573 | CanaryNoPreVoteElection (4 states) |
| canary-LeaseRejectedPreVote | Canary-LeaseRejectedPreVote.cfg | BFS | VIOLATION | 193,278 | 11 | 106,829 | CanaryNoLeaseRejectedPreVote (10 states) |
| canary-PreVoteCancelledByFollowing | Canary-PreVoteCancelledByFollowing.cfg | BFS | VIOLATION | 4,148 | 7 | 3,193 | CanaryNoPreVoteCancelledByFollowing (6 states) |
| canary-GreaterLogFromPreVote | Canary-GreaterLogFromPreVote.cfg | BFS | VIOLATION | 427,687 | 12 | 221,781 | CanaryNoGreaterLogFromPreVote (11 states) |
| canary-PreVoteAfterRestart | Canary-PreVoteAfterRestart.cfg | BFS | VIOLATION | 304 | 5 | 270 | CanaryNoPreVoteAfterRestart (5 states) |
| invalid-vacuous-mc-standard | MC.cfg | BFS | OTHER (exit 143) | 14,009,561 | 16 | 6,547,798 | - |
| invalid-vacuous-mc-membership | MC-membership.cfg | BFS | OTHER (exit 143) | 8,965,475 | 24 | 2,695,846 | - |
| hunt-prevote-membership-prerepair | MC_hunt_prevote_membership.cfg | BFS | VIOLATION | 158,616 | 14 | 85,393 | PreVoteTrackerWellFormed (13 states) |
| hunt-prevote-restart-prerepair | MC_hunt_prevote_restart.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 11,241,913 | 14 | 6,063,450 | - |
