| run | cfg | mode | distinct states (sim: generated) | queue | depth | result |
|---|---|---|---|---|---|---|
| hunt-s1-final | MC_hunt_s1_progress.cfg | bfs | 180196 | 0 | 21 | complete (queue 0), no error |
| hunt-s1-r1 | MC_hunt_s1_progress.cfg | bfs | 180196 | 0 | 21 | complete (queue 0), no error |
| hunt-s2-final | MC_hunt_s2_membership.cfg | bfs | 299908 | 0 | 23 | complete (queue 0), no error |
| hunt-s2-r1 | MC_hunt_s2_membership.cfg | bfs | 299908 | 0 | 23 | complete (queue 0), no error |
| hunt-s3-final | MC_hunt_s3_follower_commit.cfg | bfs | 76978 | 0 | 21 | complete (queue 0), no error |
| hunt-s3-r1 | MC_hunt_s3_follower_commit.cfg | bfs | 76978 | 0 | 21 | complete (queue 0), no error |
| hunt-s4-final | MC_hunt_s4_election.cfg | bfs | 183487 | 0 | 22 | complete (queue 0), no error |
| hunt-s4-r1 | MC_hunt_s4_election.cfg | bfs | 183487 | 0 | 22 | complete (queue 0), no error |
| mc-main-final | MC.cfg | bfs | 4234432 | 0 | 31 | complete (queue 0), no error |
| mc-main-r1 | MC.cfg | bfs | 4234432 | 0 | 31 | complete (queue 0), no error |
| mc-scale-final | MC_scale.cfg | bfs | 4700474 | 3243236 | 12 | time-bounded, no error (LIMITED_COVERAGE) |
| mc-scale-r1 | MC_scale.cfg | bfs | 10456449 | 7021625 | 13 | time-bounded, no error (LIMITED_COVERAGE) |
| mc5-u1-divergence-final | MC5_u1_divergence.cfg | bfs | 5673896 | 2558138 | 18 | VIOLATION: CommittedLogAgreement |
| mc5-u1-divergence-r1 | MC5_u1_divergence.cfg | bfs | 6217770 | 2785822 | 18 | VIOLATION: CommittedLogAgreement |
| reach-commit-final | MC_reach_commit.cfg | bfs | 170 | 97 | 7 | VIOLATION: NotReachCommitWitness |
| reach-commit-r1 | MC_reach_commit.cfg | bfs | 151 | 82 | 7 | VIOLATION: NotReachCommitWitness |
| reach-leader-final | MC_reach_leader.cfg | bfs | 5 | 2 | 3 | VIOLATION: NotReachLeader |
| reach-leader-r1 | MC_reach_leader.cfg | bfs | 7 | 0 | 3 | VIOLATION: NotReachLeader |
| reach-membership-final | MC_reach_membership.cfg | bfs | 11 | 5 | 4 | VIOLATION: NotReachOutstandingMembership |
| reach-membership-r1 | MC_reach_membership.cfg | bfs | 14 | 2 | 4 | VIOLATION: NotReachOutstandingMembership |
| upd-discharge-final | Update_discharge.cfg | bfs | 3582846 | 1847951 | 15 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-discharge-r1 | Update_discharge.cfg | bfs | 50 | 34 | 5 | VIOLATION: property |
| upd-discharge-r2 | Update_discharge.cfg | bfs | 12606275 | 5975213 | 17 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-discharge-sim1 | Update_discharge.cfg | sim | 23453449 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-discharge-sim2 | Update_discharge.cfg | sim | 23323948 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-faults-control-final | Update_full_faults_control.cfg | bfs | 5454936 | 3268794 | 14 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-faults-control-r1 | Update_full_faults_control.cfg | bfs | 11,646,038 | 6,712,807 | - | interrupted (tool timeout; superseded by a later run) |
| upd-faults-control-r2 | Update_full_faults_control.cfg | bfs | 15751421 | 8928607 | 16 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-faults-control-sim1 | Update_full_faults_control.cfg | sim | 25711708 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-faults-control-sim2 | Update_full_faults_control.cfg | sim | 21383424 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-focused-control-final | Update_focused_control.cfg | bfs | 3222399 | 1300229 | 18 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-focused-control-r1 | Update_focused_control.cfg | bfs | 12681331 | 3335357 | 22 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-focused-control-sim2 | Update_focused_control.cfg | sim | 11541923 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-focused-cws-final | Update_focused_cws.cfg | bfs | 60579 | 33920 | 11 | VIOLATION: UpdCommitWitnessSound |
| upd-focused-cws-r1 | Update_focused_cws.cfg | bfs | 61584 | 34481 | 11 | VIOLATION: UpdCommitWitnessSound |
| upd-focused-r1 | Update_focused.cfg | bfs | 3390 | 2182 | 8 | VIOLATION: ProgressSortedAboveCommitted |
| upd-full-control-final | Update_full_control.cfg | bfs | 4088404 | 1865933 | 17 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-full-control-r1 | Update_full_control.cfg | bfs | 10,527,238 | 4,104,849 | - | interrupted (tool timeout; superseded by a later run) |
| upd-full-control-r2 | Update_full_control.cfg | bfs | 14487253 | 5303084 | 20 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-full-control-sim1 | Update_full_control.cfg | sim | 23606966 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-full-control-sim2 | Update_full_control.cfg | sim | 19546078 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-full-cws-final | Update_full_cws.cfg | bfs | 88812 | 51557 | 11 | VIOLATION: UpdCommitWitnessSound |
| upd-full-cws-r1 | Update_full_cws.cfg | bfs | 83246 | 48401 | 12 | VIOLATION: UpdCommitWitnessSound |
| upd-full-pcs-final | Update_full_pcs.cfg | bfs | 88812 | 51557 | 11 | VIOLATION: ProgressCommittedSupported |
| upd-full-pcs-r1 | Update_full_pcs.cfg | bfs | 74158 | 43523 | 12 | VIOLATION: ProgressCommittedSupported |
| upd-full-r1 | Update_full.cfg | bfs | 7354 | 5190 | 8 | VIOLATION: OneOutstandingMembership |
| upd-full-r2 | Update_full.cfg | bfs | 4679 | 3080 | 9 | VIOLATION: ProgressSortedAboveCommitted |
| upd-full-sorted-final | Update_full_sorted.cfg | bfs | 5118 | 3457 | 8 | VIOLATION: ProgressSortedAboveCommitted |
| upd-full-sorted-r1 | Update_full_sorted.cfg | bfs | 5132 | 3370 | 9 | VIOLATION: ProgressSortedAboveCommitted |
| upd-hunt-u1deep-r1 | Update_hunt_u1_deep.cfg | bfs | 13344358 | 9096486 | 13 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u1deep-sim1 | Update_hunt_u1_deep.cfg | sim | 4544414 | - | - | VIOLATION: MembershipOrder |
| upd-hunt-u1deep-sim2 | Update_hunt_u1_deep.cfg | sim | 24890153 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u2-final | Update_hunt_u2_uniform.cfg | bfs | 3671354 | 1862129 | 18 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u2-r1 | Update_hunt_u2_uniform.cfg | bfs | 15041824 | 6551564 | 20 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u2-sim1 | Update_hunt_u2_uniform.cfg | sim | 11006702 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u2-sim2 | Update_hunt_u2_uniform.cfg | sim | 13597065 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u3-final | Update_hunt_u3_follower.cfg | bfs | 3584752 | 2019872 | 15 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u3-r1 | Update_hunt_u3_follower.cfg | bfs | 14808879 | 7768916 | 17 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u3-sim1 | Update_hunt_u3_follower.cfg | sim | 16368164 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u3-sim2 | Update_hunt_u3_follower.cfg | sim | 9239965 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u4-final | Update_hunt_u4_election.cfg | bfs | 366862 | 0 | 22 | complete (queue 0), no error |
| upd-hunt-u4-r1 | Update_hunt_u4_election.cfg | bfs | 366862 | 0 | 22 | complete (queue 0), no error |
| upd-hunt-u4-sim1 | Update_hunt_u4_election.cfg | sim | 26499714 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-hunt-u4-sim2 | Update_hunt_u4_election.cfg | sim | 31396820 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-open-control-final | Update_open_control.cfg | bfs | 3890629 | 2001194 | 16 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-open-control-r1 | Update_open_control.cfg | bfs | 12091451 | 5713988 | 17 | time-bounded, no error (LIMITED_COVERAGE) |
| upd-open-control-sim1 | Update_open_control.cfg | sim | 30123082 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-open-control-sim2 | Update_open_control.cfg | sim | 39687309 | - | - | time-bounded, no error (LIMITED_COVERAGE) |
| upd-open-final | Update_open.cfg | bfs | 11109 | 7691 | 8 | VIOLATION: ProgressSortedAboveCommitted |
| upd-open-r1 | Update_open.cfg | bfs | 6210 | 4400 | 8 | VIOLATION: OneOutstandingMembership |
| upd-open-r2 | Update_open.cfg | bfs | 11715 | 8067 | 8 | VIOLATION: ProgressSortedAboveCommitted |
| upd-reach-elected-final | Update_reach_ElectedByVotes.cfg | bfs | 5 | 2 | 3 | VIOLATION: NotReachElectedByVotes |
| upd-reach-elected-r1 | Update_reach_ElectedByVotes.cfg | bfs | 5 | 2 | 3 | VIOLATION: NotReachElectedByVotes |
| upd-reach-jointcommit-final | Update_reach_JointCommit.cfg | bfs | 935 | 665 | 7 | VIOLATION: NotReachJointCommit |
| upd-reach-jointcommit-r1 | Update_reach_JointCommit.cfg | bfs | 935 | 665 | 7 | VIOLATION: NotReachJointCommit |
| upd-reach-leadercommit-final | Update_reach_LeaderProgressCommit.cfg | bfs | 894 | 641 | 7 | VIOLATION: NotReachLeaderProgressCommit |
| upd-reach-leadercommit-r1 | Update_reach_LeaderProgressCommit.cfg | bfs | 894 | 641 | 7 | VIOLATION: NotReachLeaderProgressCommit |
| upd-reach-promotion-final | Update_reach_FollowerPromotion.cfg | bfs | 7515 | 4745 | 9 | VIOLATION: NotReachFollowerPromotion |
| upd-reach-promotion-r1 | Update_reach_FollowerPromotion.cfg | bfs | 7515 | 4745 | 9 | VIOLATION: NotReachFollowerPromotion |
| upd-reach-twoabove-final | Update_reach_TwoAboveCommitted.cfg | bfs | 940 | 668 | 7 | VIOLATION: NotReachTwoAboveCommitted |
| upd-reach-twoabove-r1 | Update_reach_TwoAboveCommitted.cfg | bfs | 940 | 668 | 7 | VIOLATION: NotReachTwoAboveCommitted |
| upd-reach-upgraded-final | Update_reach_UpgradedProgress.cfg | bfs | 13 | 7 | 4 | VIOLATION: NotReachUpgradedProgress |
| upd-reach-upgraded-r1 | Update_reach_UpgradedProgress.cfg | bfs | 13 | 7 | 4 | VIOLATION: NotReachUpgradedProgress |
| v0-control-oneoutstanding-crash | (see log) | bfs | 622 | 420 | 9 | VIOLATION: OneOutstandingMembership |
