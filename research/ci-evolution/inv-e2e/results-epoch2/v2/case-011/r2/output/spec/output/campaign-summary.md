| run (spec/output/<run>.log) | cfg | mode | outcome | states | BFS depth |
|---|---|---|---|---|---|
| canary-CanaryNoPreVoteRound | Update_canary_CanaryNoPreVoteRound.cfg | BFS | VIOLATION: Invariant CanaryNoPreVoteRound is violated | 4 distinct, queue 0 | 3 |
| canary-CanaryNoTickRoundWhileCandidate | Update_canary_CanaryNoTickRoundWhileCandidate.cfg | BFS | VIOLATION: Invariant CanaryNoTickRoundWhileCandidate is violated | 206 distinct, queue 166 | 5 |
| canary_CanaryNoGrantedPreVoteResp | Update_canary_CanaryNoGrantedPreVoteResp.cfg | BFS | VIOLATION: Invariant CanaryNoGrantedPreVoteResp is violated | 41 distinct, queue 35 | 4 |
| canary_CanaryNoLeaseRejectedPreVote | Update_canary_CanaryNoLeaseRejectedPreVote.cfg | BFS | VIOLATION: Invariant CanaryNoLeaseRejectedPreVote is violated | 84366 distinct, queue 46349 | 11 |
| canary_CanaryNoNonVoterCandidate | Update_canary_CanaryNoNonVoterCandidate.cfg | BFS | VIOLATION: Invariant CanaryNoNonVoterCandidate is violated | 7388 distinct, queue 3286 | 15 |
| canary_CanaryNoPreVoteElection | Update_canary_CanaryNoPreVoteElection.cfg | BFS | VIOLATION: Action property CanaryNoPreVoteElection is violated | 274 distinct, queue 226 | 5 |
| canary_CanaryNoPreVoteRound | Update_canary_CanaryNoPreVoteRound.cfg | BFS | VIOLATION: Invariant CanaryNoPreVoteRound is violated | 4 distinct, queue 0 | 3 |
| canary_CanaryNoRepeatedRoundOtherConfig | Update_canary_CanaryNoRepeatedRoundOtherConfig.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 1562395 distinct, queue 868539 | 14 |
| canary_CanaryNoRoundClearedByFollowing | Update_canary_CanaryNoRoundClearedByFollowing.cfg | BFS | VIOLATION: Action property CanaryNoRoundClearedByFollowing is violated | 763 distinct, queue 579 | 6 |
| canary_CanaryNoTickRoundWhileCandidate | Update_canary_CanaryNoTickRoundWhileCandidate.cfg | BFS | VIOLATION: Invariant CanaryNoTickRoundWhileCandidate is violated | 119 distinct, queue 97 | 5 |
| mc-membership-INVALIDATED-prelogfix | MC-membership.cfg | BFS | exit 143 |  |  |
| mc-membership | MC-membership.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 8743435 distinct, queue 2622839 | 24 |
| mc-standard-INVALIDATED-prelogfix | MC.cfg | BFS | exit 143 |  |  |
| mc-standard-sim | MC.cfg | simulation | no violation (simulation budget: LIMITED_COVERAGE) | 26194968 states, 249092 traces |  |
| mc-standard | MC.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 15076494 distinct, queue 8332562 | 19 |
| probe-P1 | scratch/probe-P1.cfg | BFS | VIOLATION: Invariant P1 is violated | 6062 distinct, queue 2894 | 10 |
| probe-P2 | scratch/probe-P2.cfg | BFS | VIOLATION: Invariant P2 is violated | 718 distinct, queue 464 | 7 |
| probe-P3 | scratch/probe-P3.cfg | BFS | VIOLATION: Invariant P3 is violated | 319 distinct, queue 224 | 6 |
| probe-P4 | scratch/probe-P4.cfg | BFS | VIOLATION: Invariant P4 is violated | 2333 distinct, queue 1239 | 9 |
| probe-P5 | scratch/probe-P5.cfg | BFS | no violation (state space exhausted) | 46592 distinct, queue 0 | 18 |
| probe-P6 | scratch/probe-P6.cfg | BFS | no violation (state space exhausted) | 46592 distinct, queue 0 | 18 |
| trace-append_joint_membership | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-commit_membership | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-establish_leader | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-grant_greater_vote | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_elect_multi | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_elect_single_voter | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_cleared_by_vote_request | Trace.cfg | BFS | no violation (state space exhausted) | 3 distinct, queue 0 | 3 |
| trace-pre_vote_req_grant | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_req_lease_reject | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_req_stale_log | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_resp_no_round | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_resp_quorum | Trace.cfg | BFS | no violation (state space exhausted) | 3 distinct, queue 0 | 3 |
| trace-pre_vote_resp_reject_greater_log | Trace.cfg | BFS | no violation (state space exhausted) | 3 distinct, queue 0 | 3 |
| trace-reject_stale_log | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-restart_follower | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-stale_pre_vote_after_leader | Trace.cfg | BFS | no violation (state space exhausted) | 14 distinct, queue 0 | 12 |
| trace-start_election | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| upd-discharge | Update_discharge.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 6470776 distinct, queue 3809506 | 15 |
| upd-focused-cont1 | Update_focused_cont1.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 9459668 distinct, queue 6244512 | 13 |
| upd-focused-cont2 | Update_focused_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 7219986 distinct, queue 4797280 | 13 |
| upd-focused | Update_focused.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 565967 distinct, queue 409577 | 10 |
| upd-full-cont1-sim | Update_full_cont1.cfg | simulation | VIOLATION: Invariant CandidateGrantsWithinFrozenVoters is violated | 61787 states, 679 traces |  |
| upd-full-cont1 | Update_full_cont1.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 8861373 distinct, queue 5079289 | 14 |
| upd-full-cont2-sim | Update_full_cont2.cfg | simulation | no violation (simulation budget: LIMITED_COVERAGE) | 28603396 states, 312813 traces |  |
| upd-full-cont2 | Update_full_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 10765210 distinct, queue 6136315 | 16 |
| upd-full | Update_full.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 343978 distinct, queue 232642 | 10 |
| upd-hunt-default-grant-cont2 | Update_hunt_default_grant_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 7413970 distinct, queue 3937828 | 13 |
| upd-hunt-default-grant | Update_hunt_default_grant.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 402065 distinct, queue 262451 | 10 |
| upd-hunt-nonvoter-cont | Update_hunt_nonvoter_elect_cont.cfg | BFS | VIOLATION: Invariant CandidateGrantsWithinFrozenVoters is violated | 22143 distinct, queue 9206 | 18 |
| upd-hunt-nonvoter | Update_hunt_nonvoter_elect.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 715 distinct, queue 213 | 10 |
| upd-hunt-repeat-round-cont-sim | Update_hunt_repeat_round_cont.cfg | simulation | VIOLATION: Invariant CandidateGrantsWithinFrozenVoters is violated | 1209588 states, 18580 traces |  |
| upd-hunt-repeat-round-cont | Update_hunt_repeat_round_cont.cfg | BFS | VIOLATION: Invariant PreVoteGrantsWithinFrozenVoters is violated | 8817426 distinct, queue 5403649 | 18 |
| upd-hunt-repeat-round | Update_hunt_repeat_round.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 36404 distinct, queue 20856 | 11 |
| upd-hunt-stale-round-consequence | Update_hunt_stale_round_consequence.cfg | BFS | VIOLATION: Action property LeaderNotPreemptedByTimerPreVote is violated | 36288 distinct, queue 14840 | 13 |
| upd-hunt-stale-round | Update_hunt_stale_round.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 5161 distinct, queue 2505 | 10 |
| upd-open-cont1 | Update_open_cont1.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 8739467 distinct, queue 5694632 | 14 |
| upd-open-cont2 | Update_open_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 7149034 distinct, queue 4766416 | 13 |
| upd-open | Update_open.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 365126 distinct, queue 267683 | 11 |
