| Run (log `spec/output/<run>.log`) | cfg | Purpose | Outcome | Coverage | Time |
|---|---|---|---|---|---|
| `mc-standard-round3` | `MC.cfg` | standard convergence round (final reference) | no violation; budget-limited BFS | 290,764,287 gen / 40,710,696 distinct, depth 28, queue 9,739,774 | 1801s |
| `mc-standard-sim` | `MC.cfg` | standard model, simulation depth 100 | no violation; budget-limited simulation | 55157322 states / 546930 traces, mean length 71 | 1800s |
| `update-full-c1-final` | `Update_full.cfg` | C1 full MCNext, all update properties | VIOLATION: ElectOnlyByVoter | 1048 gen / 446 distinct, depth 12 | 2s |
| `update-full-c1-panic-final` | `Update_full_NoCorePanic.cfg` | C1 oracle isolation U2 | VIOLATION: NoCorePanic | 24218 gen / 6936 distinct, depth 14 | 3s |
| `update-full-c1-nonvoterleader-final` | `Update_full_ElectedLeaderWasVoter.cfg` | C1 oracle isolation U5 (after R8) | no violation; budget-limited BFS | 239,110,966 gen / 33,881,195 distinct, depth 27, queue 8,783,686 | 1801s |
| `update-full-u7` | `Update_full_LeaderVoteNotSuperseded.cfg` | C1 U7 with transfer inputs | VIOLATION: LeaderVoteNotSuperseded | 265 gen / 61 distinct, depth 11 | 4s |
| `update-preexisting-u7` | `Update_preexisting_LeaderVoteNotSuperseded.cfg` | U7, transfers disabled (pre-existing path) | VIOLATION: LeaderVoteNotSuperseded | 1202 gen / 294 distinct, depth 11 | 4s |
| `update-full-residual-c1b` | `Update_full_residual.cfg` | C1b full MCNext, remaining properties | no violation; budget-limited BFS | 129,911,888 gen / 19,139,667 distinct, depth 24, queue 6,239,390 | 1802s |
| `update-full-residual-sim` | `Update_full_residual.cfg` | C1b simulation depth 100 | no violation; budget-limited simulation | 38158301 states / 378377 traces, mean length 75 | 1801s |
| `update-focused-c2-allprops` | `Update_focused.cfg` | C2 concrete focused, all update properties | VIOLATION: ElectOnlyByVoter | 566 gen / 315 distinct, depth 11 | 2s |
| `update-focused-residual-c2` | `Update_focused_residual.cfg` | C2 concrete focused, remaining properties | no violation; budget-limited BFS | 108,143,135 gen / 20,362,156 distinct, depth 27, queue 4,717,733 | 1801s |
| `update-open-c3-allprops` | `Update_open.cfg` | C3a open focused (EnvUpdate), all update properties | VIOLATION: ElectOnlyByVoter | 4684 gen / 562 distinct, depth 11 | 3s |
| `update-open-residual-c3a` | `Update_open_residual.cfg` | C3a open focused, remaining properties | no violation; budget-limited BFS | 196,395,740 gen / 14,500,220 distinct, depth 21, queue 6,047,262 | 1801s |
| `update-discharge-c3b` | `Update_discharge.cfg` | C3b discharge of EnvUpdate | no violation; budget-limited BFS | 93,376,911 gen / 14,045,829 distinct, depth 22, queue 4,987,155 | 1801s |
| `hunt-transfer-learner-bfs` | `MC_hunt_transfer_learner.cfg` | hunt U-S1 learner target | VIOLATION: ElectOnlyByVoter | 647 gen / 270 distinct, depth 11 | 2s |
| `hunt-transfer-voter-bfs` | `MC_hunt_transfer_voter.cfg` | hunt U-S3 voter targets, BFS | no violation; budget-limited BFS | 131,014,874 gen / 21,769,338 distinct, depth 22, queue 11,102,725 | 1801s |
| `hunt-transfer-voter-sim` | `MC_hunt_transfer_voter.cfg` | hunt U-S3 voter targets, simulation | no violation; budget-limited simulation | 100357887 states / 990676 traces, mean length 64 | 1801s |
| `hunt-transfer-membership-bfs` | `MC_hunt_transfer_membership.cfg` | hunt U-S4 membership, BFS | no violation; budget-limited BFS | 151,375,212 gen / 23,274,024 distinct, depth 23, queue 9,335,647 | 1801s |
| `hunt-transfer-membership-sim` | `MC_hunt_transfer_membership.cfg` | hunt U-S4 membership, simulation | no violation; budget-limited simulation | 110582921 states / 1096322 traces, mean length 64 | 1801s |
| `canary-AbsentElect` | `Update_canary_AbsentElect.cfg` | reachability canary (violation expected) | no violation; budget-limited BFS | 14,266,472 gen / 2,560,995 distinct, depth 19, queue 1,418,980 | 361s |
| `canary-AbsentElect-witness` | `Update_canary_AbsentElect_witness.cfg` | reachability canary (violation expected) | VIOLATION: CanaryAbsentElect | 2216059 gen / 402205 distinct, depth 24 | 72s |
| `canary-CommitAfterTransfer` | `Update_canary_CommitAfterTransfer.cfg` | reachability canary (violation expected) | no violation; budget-limited BFS | 14,970,606 gen / 2,573,175 distinct, depth 19, queue 1,274,742 | 360s |
| `canary-CommitAfterTransfer-witness` | `Update_canary_CommitAfterTransfer_witness.cfg` | reachability canary (violation expected) | VIOLATION: CanaryCommitAfterTransfer | 62324 gen / 11835 distinct, depth 22 | 5s |
| `canary-LeaseDisabled` | `Update_canary_LeaseDisabled.cfg` | reachability canary (violation expected) | VIOLATION: CanaryLeaseDisabled | 366 gen / 100 distinct, depth 11 | 2s |
| `canary-NonVoterCandidate` | `Update_canary_NonVoterCandidate.cfg` | reachability canary (violation expected) | VIOLATION: CanaryNonVoterCandidate | 945 gen / 391 distinct, depth 11 | 2s |
| `canary-OldLeaderDeposed` | `Update_canary_OldLeaderDeposed.cfg` | reachability canary (violation expected) | VIOLATION: CanaryOldLeaderDeposed | 42798 gen / 11717 distinct, depth 13 | 5s |
| `canary-OmittedApply` | `Update_canary_OmittedApply.cfg` | reachability canary (violation expected) | VIOLATION: CanaryOmittedApply | 1638249 gen / 329119 distinct, depth 16 | 40s |
| `canary-OmittedStale` | `Update_canary_OmittedStale.cfg` | reachability canary (violation expected) | VIOLATION: CanaryOmittedStale | 303 gen / 87 distinct, depth 10 | 3s |
| `canary-TransferElectedLeader` | `Update_canary_TransferElectedLeader.cfg` | reachability canary (violation expected) | VIOLATION: CanaryTransferElectedLeader | 1525127 gen / 309667 distinct, depth 16 | 35s |
| `canary-TransferGrant` | `Update_canary_TransferGrant.cfg` | reachability canary (violation expected) | VIOLATION: CanaryTransferGrant | 36951 gen / 10263 distinct, depth 13 | 4s |
