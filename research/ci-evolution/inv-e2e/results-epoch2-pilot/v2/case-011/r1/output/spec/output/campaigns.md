# Model-checking campaigns (run incr-705b7bab5f0d)

Budget-limited runs are LIMITED_COVERAGE, not proofs. Exact commands are the `# command:` header of each log.

| label (log) | module | cfg | mode | result | states generated | distinct (BFS) / traces (sim) | queue left | BFS depth | exit |
|---|---|---|---|---|---|---|---|---|---|
| `spec/output/canary-CanaryNoCertifiedLeader.log` | Update | Canary_CanaryNoCertifiedLeader.cfg | BFS | VIOLATION Invariant CanaryNoCertifiedLeader | 68709 | 20838 | 13256 | 10 | 12 |
| `spec/output/canary-CanaryNoGreaterLogFromPreVote.log` | Update | Canary_CanaryNoGreaterLogFromPreVote.cfg | BFS | VIOLATION Action property CanaryNoGreaterLogFromPreVote | 4007876 | 895290 | 442757 | 14 | 13 |
| `spec/output/canary-CanaryNoLeaderWithTimerRound.log` | Update | Canary_CanaryNoLeaderWithTimerRound.cfg | BFS | VIOLATION Invariant CanaryNoLeaderWithTimerRound | 336990 | 87774 | 49398 | 10 | 12 |
| `spec/output/canary-CanaryNoPreCandidateDroppedByFollowing.log` | Update | Canary_CanaryNoPreCandidateDroppedByFollowing.cfg | BFS | VIOLATION Action property CanaryNoPreCandidateDroppedByFollowing | 4692 | 1947 | 1429 | 7 | 13 |
| `spec/output/canary-CanaryNoPreCandidateDroppedByFollowing.pre-refinement.log` | Update | Canary_CanaryNoPreCandidateDroppedByFollowing.cfg | BFS | VIOLATION Action property CanaryNoPreCandidateDroppedByFollowing | 6405 | 2472 | 1799 | 7 | 13 |
| `spec/output/canary-CanaryNoPreVoteElection.log` | Update | Canary_CanaryNoPreVoteElection.cfg | BFS | VIOLATION Action property CanaryNoPreVoteElection | 5224 | 2115 | 1528 | 8 | 13 |
| `spec/output/canary-CanaryNoPreVoteElection.pre-refinement.log` | Update | Canary_CanaryNoPreVoteElection.cfg | BFS | VIOLATION Action property CanaryNoPreVoteElection | 4314 | 1746 | 1291 | 7 | 13 |
| `spec/output/canary-CanaryNoPreVoteLeaseReject.log` | Update | Canary_CanaryNoPreVoteLeaseReject.cfg | BFS | VIOLATION Action property CanaryNoPreVoteLeaseReject | 1797945 | 415684 | 210523 | 13 | 13 |
| `spec/output/canary-CanaryNoPreVoteTally.log` | Update | Canary_CanaryNoPreVoteTally.cfg | BFS | VIOLATION Action property CanaryNoPreVoteTally | 13497953 | 2969446 | 1491846 | 15 | 13 |
| `spec/output/canary-CanaryNoSameLeaderIdNewRound.log` | Update | Canary_CanaryNoSameLeaderIdNewRound.cfg | BFS | VIOLATION Invariant CanaryNoSameLeaderIdNewRound | 4594 | 1852 | 1379 | 6 | 12 |
| `spec/output/cex-hunt-PreVoteResponseNeverPanics.log` | Update | MC_hunt_prevote_panic_directed.cfg | BFS | VIOLATION Invariant PreVoteResponseNeverPanics | 3596277 | 678775 | 377296 | 17 | 12 |
| `spec/output/cex-initial-update-full-PreVoteStaleResponseIgnored.log` | Update | Update_full.cfg | BFS | VIOLATION Action property PreVoteStaleResponseIgnored | 19848 | 6986 | 4744 | 9 | 13 |
| `spec/output/cex-initial-update-full-TimerPreVoteElectionFromFollowerState.log` | Update | Update_full_cont1.cfg | BFS | VIOLATION Action property TimerPreVoteElectionFromFollowerState | 7027546 | 1551741 | 764749 | 15 | 13 |
| `spec/output/cex-update-full-PreVoteStaleResponseIgnored.log` | Update | Update_full.cfg | BFS | VIOLATION Action property PreVoteStaleResponseIgnored | 15305 | 5298 | 3667 | 8 | 13 |
| `spec/output/cex-update-full-TimerPreVoteElectionFromFollowerState.log` | Update | Update_full_cont1.cfg | BFS | VIOLATION Action property TimerPreVoteElectionFromFollowerState | 5794723 | 1284574 | 635824 | 14 | 13 |
| `spec/output/discharge-full.cex-envupdate-too-strong.log` | Update | Update_discharge.cfg | BFS | VIOLATION Action property DischargeContext | 3472916 | 781916 | 388881 | 15 | 13 |
| `spec/output/discharge-full.first.log` | Update | Update_discharge.cfg | BFS | VIOLATION Action property DischargeContext | 3472916 | 781916 | 388881 | 15 | 13 |
| `spec/output/discharge-full.log` | Update | Update_discharge.cfg | BFS | no violation; budget-limited | 13502984 | 2955101 | 1474084 | 16 | 0 |
| `spec/output/discharge-full.superseded-form.log` | Update | Update_discharge.cfg | BFS | no violation reported; stopped at budget (exit 143) | 4,889,890 | 1,090,409 | 540,462 | - | 143 |
| `spec/output/discharge-membership.first.log` | Update | Update_discharge_membership.cfg | BFS | no violation; state space exhausted | 2701713 | 299637 | 0 | 29 | 0 |
| `spec/output/discharge-membership.log` | Update | Update_discharge_membership.cfg | BFS | no violation; state space exhausted | 2701713 | 299637 | 0 | 29 | 0 |
| `spec/output/discharge-membership.second.log` | Update | Update_discharge_membership.cfg | BFS | no violation; state space exhausted | 2701713 | 299637 | 0 | 29 | 0 |
| `spec/output/final-update-full-U4.log` | Update | Update_full.cfg | BFS | VIOLATION Action property PreVoteStaleResponseIgnored | 15305 | 5298 | 3667 | 8 | 13 |
| `spec/output/final-update-full-cont1-U5.log` | Update | Update_full_cont1.cfg | BFS | VIOLATION Action property TimerPreVoteElectionFromFollowerState | 5794723 | 1284574 | 635824 | 14 | 13 |
| `spec/output/hunt-leader-abdication-bfs.first.log` | Update | MC_hunt_leader_abdication.cfg | BFS | VIOLATION Action property PreVoteStaleResponseIgnored | 3419 | 1209 | 766 | 7 | 13 |
| `spec/output/hunt-leader-abdication-bfs.log` | Update | MC_hunt_leader_abdication.cfg | BFS | VIOLATION Action property TimerPreVoteElectionFromFollowerState | 615468 | 134059 | 56660 | 15 | 13 |
| `spec/output/hunt-prevote-crash-bfs.log` | Update | MC_hunt_prevote_crash_cont.cfg | BFS | no violation; budget-limited | 53518658 | 10260054 | 4728035 | 17 | 0 |
| `spec/output/hunt-prevote-panic-bfs.aborted.log` | Update | MC_hunt_prevote_panic.cfg | BFS | VIOLATION Action property PreVoteStaleResponseIgnored | 11744 | 3677 | 2549 | 8 | 13 |
| `spec/output/hunt-prevote-panic-bfs.log` | Update | MC_hunt_prevote_panic.cfg | BFS | no violation; budget-limited | 64692262 | 14394202 | 8228051 | 18 | 0 |
| `spec/output/hunt-prevote-panic-directed.log` | Update | MC_hunt_prevote_panic_directed.cfg | BFS | VIOLATION Invariant PreVoteResponseNeverPanics | 3596277 | 678775 | 377296 | 17 | 12 |
| `spec/output/hunt-prevote-panic-sim.log` | Update | MC_hunt_prevote_panic.cfg | simulation | no violation; budget-limited (simulation) | 27605000 | 66223 traces, mean len 37 | n/a | - | 0 |
| `spec/output/hunt-stale-round-bfs.log` | Update | MC_hunt_stale_round.cfg | BFS | VIOLATION Action property PreVoteStaleResponseIgnored | 9086 | 2695 | 1875 | 8 | 13 |
| `spec/output/mc-membership.log` | MC | MC-membership.cfg | BFS | no violation; state space exhausted | 2701713 | 299637 | 0 | 29 | 0 |
| `spec/output/mc-standard-sim.log` | MC | MC.cfg | simulation | no violation; budget-limited (simulation) | 42454459 | 138331 traces, mean len 37 | n/a | - | 0 |
| `spec/output/mc-standard.log` | MC | MC.cfg | BFS | no violation; budget-limited | 89863129 | 19927689 | 11342411 | 20 | 0 |
| `spec/output/update-focused-cont-sim.log` | Update | Update_focused_cont.cfg | simulation | no violation; budget-limited (simulation) | 18428564 | 38145 traces, mean len 58 | n/a | - | 0 |
| `spec/output/update-focused-cont.log` | Update | Update_focused_cont.cfg | BFS | no violation; budget-limited | 99212807 | 19750713 | 10278105 | 17 | 0 |
| `spec/output/update-full-cont1.log` | Update | Update_full_cont1.cfg | BFS | VIOLATION Action property TimerPreVoteElectionFromFollowerState | 7027546 | 1551741 | 764749 | 15 | 13 |
| `spec/output/update-full-cont2-sim.log` | Update | Update_full_cont2.cfg | simulation | no violation; budget-limited (simulation) | 31821106 | 103015 traces, mean len 37 | n/a | - | 0 |
| `spec/output/update-full-cont2.log` | Update | Update_full_cont2.cfg | BFS | no violation; budget-limited | 110248842 | 24331209 | 13339970 | 19 | 0 |
| `spec/output/update-full-cont2.superseded.log` | Update | Update_full_cont2.cfg | BFS | no violation reported; stopped at budget (exit 143) | 34,913,271 | 7,742,734 | 4,057,036 | - | 143 |
| `spec/output/update-full-mixed-cont.log` | Update | Update_full_mixed_cont.cfg | BFS | no violation; budget-limited | 58362524 | 12970525 | 7021260 | 20 | 0 |
| `spec/output/update-full.log` | Update | Update_full.cfg | BFS | VIOLATION Action property PreVoteStaleResponseIgnored | 19848 | 6986 | 4744 | 9 | 13 |
| `spec/output/update-open-cont.log` | Update | Update_open_cont.cfg | BFS | no violation; budget-limited | 94529104 | 24411799 | 16563305 | 14 | 0 |
| `spec/output/update-open-cont.tlc-assignment-error.log` | Update | Update_open_cont.cfg | BFS | no violation reported; stopped at budget (exit 75) | 164 | 135 | 123 | 6 | 75 |
