| Run | Spec / cfg | Purpose | Result | Explored | Depth / traces | Coverage status |
|---|---|---|---|---|---|---|
| `std-MC` | MC / MC.cfg | Standard convergence round (Pre-Vote toggled) | no violation | 23943591 distinct (107950681 generated) | 20 | budget-limited, 13,880,638 queued |
| `std-MC-membership` | MC / MC-membership.cfg | Standard round, one-voter seed | no violation | 299637 distinct (2701721 generated) | 29 | exhausted |
| `std-MC-sim` | MC / MC.cfg (simulation, depth 100) | Standard round simulation follow-up | no violation (time limit reached, exit 0) | 67,987,118 states checked | 144,684 traces (mean len 71) | simulation, budget-limited |
| `upd-full` | Update / Update-full.cfg | Full update check U1–U4 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 597804 distinct (2836314 generated) | 14 | stopped at violation |
| `upd-full-rest` | Update / Update-full-rest.cfg | Full update check U2–U4 | Action property PreVoteElectOnlyByVoter is violated | 4519069 distinct (20782912 generated) | 17 | stopped at violation |
| `upd-full-prevote-rest` | Update / Update-full-prevote.cfg | Full update check U2–U4, Pre-Vote always on | Action property PreVoteElectOnlyByVoter is violated | 5074546 distinct (23312224 generated) | 17 | stopped at violation |
| `upd-full-U2U4` | Update / Update-full-U2U4.cfg | Full update check U2, U4 + invariant | no violation | 13657797 distinct (61720462 generated) | 19 | budget-limited, 7,801,092 queued |
| `upd-full-U2U4-sim` | Update / Update-full-U2U4.cfg (simulation) | Simulation follow-up | no violation (time limit reached, exit 0) | 71,209,078 states checked | 151,666 traces (mean len 71) | simulation, budget-limited |
| `upd-focused` | Update / Update-focused.cfg | Concrete focused U1–U4 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 2587022 distinct (12943709 generated) | 15 | stopped at violation |
| `upd-focused-rest` | Update / Update-focused-rest.cfg | Concrete focused U2–U4 | no violation | 16357101 distinct (89327648 generated) | 18 | budget-limited, 8,452,747 queued |
| `upd-focused-U2U4` | Update / Update-focused-U2U4.cfg | Concrete focused U2, U4 | no violation | 12918826 distinct (69457997 generated) | 16 | budget-limited, 6,802,140 queued |
| `upd-open` | Update / Update-open.cfg | Open focused (EnvUpdate) U1–U4 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 749257 distinct (3426563 generated) | 14 | stopped at violation |
| `upd-open-rest` | Update / Update-open-rest.cfg | Open focused U2–U4 | Action property PreVoteElectOnlyByVoter is violated | 1385309 distinct (5911429 generated) | 16 | stopped at violation |
| `upd-open-U2U4` | Update / Update-open-U2U4.cfg | Open focused U2, U4 | no violation | 25392291 distinct (94371529 generated) | 17 | budget-limited, 17,262,195 queued |
| `upd-discharge` | Update / Update-discharge.cfg | Discharge EnvUpdate (3 voters) | no violation | 8095012 distinct (36484203 generated) | 17 | budget-limited, 4,527,198 queued |
| `upd-discharge-sim` | Update / Update-discharge.cfg (simulation) | Discharge simulation follow-up | no violation (time limit reached, exit 0) | 55,677,335 states checked | 118,577 traces (mean len 71) | simulation, budget-limited |
| `upd-discharge-seed1` | Update / Update-discharge-seed1.cfg | Discharge EnvUpdate (one-voter seed) | no violation | 299637 distinct (2701721 generated) | 29 | exhausted |
| `hunt-prevote-leader` | Update / MC_hunt_prevote_leader.cfg | Hunt U1 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 60921 distinct (285556 generated) | 14 | stopped at violation |
| `hunt-prevote-leader-tickonly` | Update / MC_hunt_prevote_leader_tickonly.cfg | Hunt U1, timer-only | Action property PreVoteNeverDemotesEstablishedLeader is violated | 93292 distinct (473990 generated) | 16 | stopped at violation |
| `hunt-prevote-inherited-round` | Update / MC_hunt_prevote_inherited_round.cfg | Hunt U1 precondition | Invariant PreVoteRoundNotInheritedByLeader is violated | 12046 distinct (50642 generated) | 12 | stopped at violation |
| `hunt-prevote-membership` | Update / MC_hunt_prevote_membership.cfg | Hunt U3/U2 with membership | Action property PreVoteElectOnlyByVoter is violated | 2919 distinct (10170 generated) | 14 | stopped at violation |
| `hunt-prevote-membership-U2` | Update / MC_hunt_prevote_membership_U2.cfg | Hunt U2/U4 with membership | no violation | 9665167 distinct (74774917 generated) | 28 | budget-limited, 1,950,934 queued |
| `hunt-prevote-crash` | Update / MC_hunt_prevote_crash.cfg | Hunt U2/U4/U5 with crash and loss | no violation | 21908449 distinct (127377112 generated) | 18 | budget-limited, 9,173,513 queued |
| `hunt-prevote-crash-sim` | Update / MC_hunt_prevote_crash.cfg (simulation) | Simulation follow-up | no violation (time limit reached, exit 0) | 78,250,844 states checked | 185,157 traces (mean len 71) | simulation, budget-limited |
| `canary-prevote-win` | Update / Update-canary-prevote-win.cfg | Canary (expected violation) | Action property CanaryNoPreVoteWin is violated | 719 distinct (1546 generated) | 6 | stopped at violation |
| `canary-lease-reject` | Update / Update-canary-lease-reject.cfg | Canary (expected violation) | Action property CanaryNoLeaseRejectedPreVote is violated | 150772 distinct (670550 generated) | 12 | stopped at violation |
| `canary-cancel-following` | Update / Update-canary-cancel-following.cfg | Canary (expected violation) | Action property CanaryNoPreCandidateCancelledByFollowing is violated | 1497 distinct (3815 generated) | 9 | stopped at violation |
| `canary-preround-leader` | Update / Update-canary-preround-leader.cfg | Canary (expected violation) | Invariant CanaryNoPreRoundOnLeader is violated | 67651 distinct (287704 generated) | 13 | stopped at violation |
| `canary-win-after-membership` | Update / Update-canary-win-after-membership.cfg | Canary (expected violation) | Action property CanaryNoPreVoteWinAfterMembershipChange is violated | 3642 distinct (11424 generated) | 13 | stopped at violation |
| `fixcheck-MC_hunt_prevote_leader` | fixcheck / MC_hunt_prevote_leader.cfg | Control: MC-1 fix in model | no violation | 10439775 distinct (64638957 generated) | 24 | budget-limited, 3,776,121 queued |
| `fixcheck-MC_hunt_prevote_leader_tickonly` | fixcheck / MC_hunt_prevote_leader_tickonly.cfg | Control: MC-1 fix in model | no violation | 10059601 distinct (66906946 generated) | 25 | budget-limited, 3,498,484 queued |
| `fixcheck-MC_hunt_prevote_membership` | fixcheck / MC_hunt_prevote_membership.cfg | Control: MC-1 fix only | Action property PreVoteElectOnlyByVoter is violated | 3024 distinct (10150 generated) | 12 | stopped at violation |
| `fixcheck-Update-full-rest` | fixcheck / Update-full-rest.cfg | Control: MC-1 fix only | Action property PreVoteElectOnlyByVoter is violated | 5332203 distinct (24423763 generated) | 18 | stopped at violation |
| `fixcheck2-MC_hunt_prevote_membership` | fixcheck2 / MC_hunt_prevote_membership.cfg | Control: MC-1 + MC-2 fixes | no violation | 9358078 distinct (73547137 generated) | 28 | budget-limited, 1,848,002 queued |
| `fixcheck2-Update-full` | fixcheck2 / Update-full.cfg | Control: MC-1 + MC-2 fixes, U1–U4 | no violation | 15666582 distinct (70769165 generated) | 19 | budget-limited, 8,968,223 queued |
| `fixcheck2-Update-full-rest` | fixcheck2 / Update-full-rest.cfg | Control: MC-1 + MC-2 fixes, U2–U4 | no violation | 18880325 distinct (85086051 generated) | 19 | budget-limited, 10,894,836 queued |
