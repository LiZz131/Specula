# Model-checking summary (run incr-315482ff25a1)

All runs: `harness/run-model-check.sh <Spec> <cfg> <label> <minutes> <workers> [-simulate -depth 80]`
(outer `timeout`, `-Dtlc2.TLC.stopAfter`, `-deadlock` i.e. deadlock checking off, `-coverage 10`, states under
`/dev/shm/specular-e2e-case-011/<label>-<pid>`, removed on exit). Every exploration stopped at its time budget
with a non-empty queue unless it found a violation: **LIMITED_COVERAGE — no exhaustive pass is claimed.**

## Final suite (after the last reference repair)

Campaign order: standard `MC.cfg` + `MC-membership.cfg` → full update (`Update_full*.cfg`) → concrete focused
(`Update_focused_continue.cfg`) → open (`Update_open_continue.cfg`, rely v3) + discharge (`Update_discharge*.cfg`)
→ scenario hunts and canaries → simulation follow-ups for every non-exhausted BFS.

| log | cfg | mode | outcome | coverage | duration |
|---|---|---|---|---|---|
| mc-MC-membership-sim.log | MC-membership.cfg | simulation | no violation; simulation time budget | 25173103 states checked, 307953 traces, mean length 63 | 30min 01s |
| mc-MC-membership.log | MC-membership.cfg | BFS | no violation; stopped at time budget | 2474412 distinct / 14839262 generated, queue 956430, depth 19 | 30min 02s |
| mc-MC-standard-sim.log | MC.cfg | simulation | no violation; simulation time budget | 14854152 states checked, 124824 traces, mean length 63 | 30min 02s |
| mc-MC-standard.log | MC.cfg | BFS | no violation; stopped at time budget | 8457002 distinct / 48718739 generated, queue 4838027, depth 17 | 30min 02s |
| mc-canary-CanaryNoLeaderWithPreCandidate.log | Update_canary_CanaryNoLeaderWithPreCandidate.cfg | BFS | VIOLATION invariant CanaryNoLeaderWithPreCandidate | 173495 distinct / 856786 generated, queue 119601, depth 9 | 02min 44s |
| mc-canary-CanaryNoPreCandidateDroppedByFollow.log | Update_canary_CanaryNoPreCandidateDroppedByFollow.cfg | BFS | VIOLATION action property CanaryNoPreCandidateDroppedByFollow | 203 distinct / 530 generated, queue 170, depth 4 | 05s |
| mc-canary-CanaryNoPreVoteElect.log | Update_canary_CanaryNoPreVoteElect.cfg | BFS | VIOLATION action property CanaryNoPreVoteElect | 305 distinct / 817 generated, queue 259, depth 4 | 05s |
| mc-canary-CanaryNoPreVoteElectFromFollower.log | Update_canary_CanaryNoPreVoteElectFromFollower.cfg | BFS | VIOLATION action property CanaryNoPreVoteElectFromFollower | 305 distinct / 817 generated, queue 259, depth 4 | 05s |
| mc-canary-CanaryNoPreVoteGrant.log | Update_canary_CanaryNoPreVoteGrant.cfg | BFS | VIOLATION invariant CanaryNoPreVoteGrant | 45 distinct / 76 generated, queue 40, depth 3 | 04s |
| mc-canary-CanaryNoPreVoteReject.log | Update_canary_CanaryNoPreVoteReject.cfg | BFS | VIOLATION invariant CanaryNoPreVoteReject | 230 distinct / 573 generated, queue 195, depth 4 | 05s |
| mc-hunt-stale-membership-leader.log | Update_hunt_stale_membership_leader.cfg | BFS | VIOLATION invariant PreVoteGrantFromRoundMember | 1622613 distinct / 6856210 generated, queue 971025, depth 16 | 11min 49s |
| mc-hunt-stale-membership-sim.log | Update_hunt_stale_membership.cfg | simulation | no violation; simulation time budget | 8368814 states checked, 86571 traces, mean length 48 | 30min 01s |
| mc-hunt-stale-membership.log | Update_hunt_stale_membership.cfg | BFS | VIOLATION invariant PreVoteGrantFromRoundMember | 1640132 distinct / 7146998 generated, queue 984347, depth 16 | 12min 06s |
| mc-hunt-stale-round.log | Update_hunt_stale_round.cfg | BFS | VIOLATION invariant EstablishedLeaderHasNoInheritedPreVote | 173644 distinct / 857593 generated, queue 119691, depth 9 | 02min 00s |
| mc-update-discharge-3voter.log | Update_discharge_3voter.cfg | BFS | no violation; stopped at time budget | 1188370 distinct / 5347004 generated, queue 632428, depth 15 | 30min 02s |
| mc-update-discharge.log | Update_discharge.cfg | BFS | no violation; stopped at time budget | 2196042 distinct / 12974914 generated, queue 885917, depth 19 | 30min 02s |
| mc-update-focused-continue-sim.log | Update_focused_continue.cfg | simulation | no violation; simulation time budget | 25816436 states checked, 241580 traces, mean length 58 | 30min 01s |
| mc-update-focused-continue.log | Update_focused_continue.cfg | BFS | no violation; stopped at time budget | 3761251 distinct / 21151533 generated, queue 2228935, depth 13 | 30min 02s |
| mc-update-full-continue-sim.log | Update_full_continue.cfg | simulation | VIOLATION invariant PreVoteGrantFromRoundMember | 11446507 states checked, 96264 traces, mean length 54 | 10min 23s |
| mc-update-full-continue.log | Update_full_continue.cfg | BFS | no violation; stopped at time budget | 5468696 distinct / 31527657 generated, queue 3171093, depth 15 | 30min 02s |
| mc-update-full-continue2-sim.log | Update_full_continue2.cfg | simulation | no violation; simulation time budget | 33653890 states checked, 282949 traces, mean length 54 | 30min 00s |
| mc-update-full.log | Update_full.cfg | BFS | VIOLATION action property PreVoteElectionPremiseCurrent | 1461455 distinct / 7992205 generated, queue 914606, depth 12 | 14min 05s |
| mc-update-open-continue-sim.log | Update_open_continue.cfg | simulation | no violation; simulation time budget | 27903317 states checked, 162682 traces, mean length 58 | 30min 01s |
| mc-update-open-continue-v2rely-follower-artifact.log | Update_open_continue.cfg | BFS | VIOLATION invariant PreVoteGrantFromRoundMember | 109780 distinct / 441014 generated, queue 101086, depth 8 | 30s |
| mc-update-open-continue.log | Update_open_continue.cfg | BFS | no violation; stopped at time budget | 4108477 distinct / 24921148 generated, queue 3164442, depth 11 | 30min 03s |

Notes:
- `mc-update-open-continue-v2rely-follower-artifact.log`: open-only violation through rely v2 (a follower's voter
  set changed without AppendEntries); not admitted by the full reference; rely tightened to v3 (see changelog).
- Violations of `PreVoteElectionPremiseCurrent` / `EstablishedLeaderHasNoInheritedPreVote` are MC-1; violations of
  `PreVoteGrantFromRoundMember` are MC-2 (`spec/bug-report.md`). `Update_*_continue*.cfg` filter known
  counterexamples and keep all other properties enabled.
- Canary violations are reachability witnesses (expected).
- Discharge non-vacuity: omitted actions `MCAppendJointConfig`, `MCAppendUniformConfig`, `MCCommitMembership`,
  `MCFlushLog` each fired thousands of times in both discharge seeds (coverage sections of the logs).

## Superseded runs (earlier model revisions; not credited)

- `spec/output/superseded/`: runs before the `LogLE` repair (V0 3-voter vacuity) and a discharge run with rely v1/v2.
- `spec/output/pre-nonmember-repair/`: runs before the `HandlePreVoteResponseNonMember` repair (first MC-1 find,
  first open runs, first canaries/hunt).

| log | cfg | mode | outcome | coverage | duration |
|---|---|---|---|---|---|
| pre-nonmember-repair/mc-MC-membership.log | MC-membership.cfg | BFS | no violation; stopped at time budget | 2803625 distinct / 16949365 generated, queue 1063084, depth 19 | 30min 03s |
| pre-nonmember-repair/mc-MC-standard-sim.log | MC.cfg | simulation | rc=143 | 15713516 states checked, 132285 traces, mean length 54 | - |
| pre-nonmember-repair/mc-MC-standard.log | MC.cfg | BFS | no violation; stopped at time budget | 15489514 distinct / 91421365 generated, queue 8575977, depth 17 | 30min 03s |
| pre-nonmember-repair/mc-hunt-stale-round.log | Update_hunt_stale_round.cfg | BFS | VIOLATION invariant EstablishedLeaderHasNoInheritedPreVote | 166880 distinct / 815512 generated, queue 115285, depth 9 | 02min 10s |
| pre-nonmember-repair/mc-update-discharge-3voter.log | Update_discharge_3voter.cfg | BFS | no violation; stopped at time budget | 2600017 distinct / 11301436 generated, queue 1474225, depth 17 | 30min 02s |
| pre-nonmember-repair/mc-update-discharge.log | Update_discharge.cfg | BFS | no violation; stopped at time budget | 4431435 distinct / 28993732 generated, queue 1514082, depth 23 | 30min 02s |
| pre-nonmember-repair/mc-update-focused-continue.log | Update_focused_continue.cfg | BFS | rc=143 | - | - |
| pre-nonmember-repair/mc-update-focused.log | Update_focused.cfg | BFS | VIOLATION action property PreVoteElectionPremiseCurrent | 1477019 distinct / 7869671 generated, queue 917864, depth 13 | 06min 21s |
| pre-nonmember-repair/mc-update-full-continue-sim.log | Update_full_continue.cfg | simulation | rc=143 | 7530705 states checked, 63390 traces, mean length 54 | - |
| pre-nonmember-repair/mc-update-full-continue.log | Update_full_continue.cfg | BFS | no violation; stopped at time budget | 8074187 distinct / 46383258 generated, queue 4613094, depth 15 | 30min 02s |
| pre-nonmember-repair/mc-update-full.log | Update_full.cfg | BFS | VIOLATION action property PreVoteElectionPremiseCurrent | 1776116 distinct / 9677151 generated, queue 1080504, depth 13 | 03min 20s |
| pre-nonmember-repair/mc-update-open-run1-rely-artifact.log | Update_open.cfg | BFS | VIOLATION invariant DurableLogNotAhead | 2270591 distinct / 10785874 generated, queue 2035011, depth 9 | 06min 21s |
| pre-nonmember-repair/mc-update-open-sim.log | Update_open.cfg | simulation | VIOLATION action property PreVoteElectionPremiseCurrent | 15078 states checked, 76 traces, mean length 54 | 03s |
| pre-nonmember-repair/mc-update-open.log | Update_open.cfg | BFS | no violation; stopped at time budget | 12124855 distinct / 63097779 generated, queue 10607203, depth 10 | 30min 03s |
