| Log | Config | Mode | Outcome | Depth/level | States generated | Distinct (or traces) | Queue left |
|---|---|---|---|---|---|---|---|
| v1-mc-canary-CanaryNoCandidateWithPreCandidate.log | Canary-CanaryNoCandidateWithPreCandidate.cfg | BFS | VIOLATED CanaryNoCandidateWithPreCandidate | 5 | 330 | 146 | 123 |
| v1-mc-canary-CanaryNoGrantedPreVoteResp.log | Canary-CanaryNoGrantedPreVoteResp.cfg | BFS | VIOLATED CanaryNoGrantedPreVoteResp | 5 | 1092 | 422 | 346 |
| v1-mc-canary-CanaryNoLeaderWithPreCandidate.log | Canary-CanaryNoLeaderWithPreCandidate.cfg | BFS | VIOLATED CanaryNoLeaderWithPreCandidate | 9 | 621014 | 124652 | 85399 |
| v1-mc-canary-CanaryNoPreCandidate.log | Canary-CanaryNoPreCandidate.cfg | BFS | VIOLATED CanaryNoPreCandidate | 3 | 12 | 8 | 4 |
| v1-mc-canary-CanaryNoPreGrantCounted.log | Canary-CanaryNoPreGrantCounted.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 12 | 8,362,546 | 1,497,400 | 929,673 |
| v1-mc-canary-CanaryNoPreVoteCleared.log | Canary-CanaryNoPreVoteCleared.cfg | BFS | VIOLATED CanaryNoPreVoteCleared | 6 | 7134 | 2122 | 1668 |
| v1-mc-canary-CanaryNoPreVoteElection.log | Canary-CanaryNoPreVoteElection.cfg | BFS | VIOLATED CanaryNoPreVoteElection | 6 | 6103 | 1761 | 1374 |
| v1-mc-canary-CanaryNoRejectedPreVoteResp.log | Canary-CanaryNoRejectedPreVoteResp.cfg | BFS | VIOLATED CanaryNoRejectedPreVoteResp | 7 | 18819 | 5033 | 3813 |
| v1-mc-canary-stale-CanaryNoCandidateWithPreCandidate.invalidated-pre-LogLE-repair.log | Canary-stale-CanaryNoCandidateWithPreCandidate.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-canary-stale-CanaryNoLeaderWithPreCandidate.invalidated-pre-LogLE-repair.log | Canary-stale-CanaryNoLeaderWithPreCandidate.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-canary-stale-CanaryNoPreVoteElection.invalidated-pre-LogLE-repair.log | Canary-stale-CanaryNoPreVoteElection.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-hunt-next-term-bfs.log | Update-hunt-next-term.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 16 | 89,765,937 | 14,681,835 | 8,047,891 |
| v1-mc-hunt-next-term-sim.log | Update-hunt-next-term.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 54547915 | 82706 traces | - |
| v1-mc-hunt-stale-precandidate-bfs.invalidated-pre-LogLE-repair.log | Update-hunt-stale-precandidate.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-hunt-stale-precandidate-bfs.log | Update-hunt-stale-precandidate.cfg | BFS | VIOLATED PreVoteNeverDemotesLeader | 17 | 733252 | 130627 | 41108 |
| v1-mc-standard-MC-membership-sim.log | MC-membership.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 28289354 | 67593 traces | - |
| v1-mc-standard-MC-membership.log | MC-membership.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 23 | 51,586,862 | 7,409,768 | 2,183,815 |
| v1-mc-standard-MC-sim.log | MC.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 63077927 | 120551 traces | - |
| v1-mc-standard-MC.invalidated-pre-LogLE-repair.log | MC.cfg | BFS | exit 143 | 14 | 11,539,991 | 2,024,311 | 1,233,132 |
| v1-mc-standard-MC.log | MC.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 18 | 86,445,598 | 14,509,828 | 8,102,817 |
| v1-mc-update-discharge-membership.log | Update-discharge-membership.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 22 | 35,828,085 | 5,306,658 | 1,692,091 |
| v1-mc-update-discharge.log | Update-discharge.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 14 | 27,557,744 | 4,719,931 | 2,777,377 |
| v1-mc-update-focus-noU4-sim.log | Update-focus-noU4.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 37202308 | 259484 traces | - |
| v1-mc-update-focus-noU4.log | Update-focus-noU4.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 16 | 89,911,165 | 14,764,031 | 8,151,223 |
| v1-mc-update-focus.log | Update-focus.cfg | BFS | VIOLATED NoStalePreCandidateAtLeader | 11 | 557775 | 117667 | 79609 |
| v1-mc-update-full-U4.log | Update-full-U4.cfg | BFS | VIOLATED PreVoteNeverDemotesLeader | 14 | 42616910 | 7142666 | 4133068 |
| v1-mc-update-full-noU4-sim.log | Update-full-noU4.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 36908544 | 70581 traces | - |
| v1-mc-update-full-noU4.log | Update-full-noU4.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 16 | 87,438,132 | 14,537,701 | 8,118,243 |
| v1-mc-update-full.log | Update-full.cfg | BFS | VIOLATED NoStalePreCandidateAtLeader | 12 | 636096 | 128774 | 86525 |
| v1-mc-update-open-noU4-sim.log | Update-open-noU4.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 50365249 | 363307 traces | - |
| v1-mc-update-open-noU4.log | Update-open-noU4.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 13 | 109,553,145 | 24,358,892 | 18,668,447 |
| v1-mc-update-open.log | Update-open.cfg | BFS | VIOLATED NoStalePreCandidateAtLeader | 10 | 53949946 | 12423337 | 9758679 |
