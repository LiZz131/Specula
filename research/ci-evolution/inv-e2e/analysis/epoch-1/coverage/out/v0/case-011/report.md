# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CanaryNoLeaseRejectedPreVote`, `CanaryNoPreCandidateCancelledByFollowing`, `CanaryNoPreRoundOnLeader`, `CanaryNoPreVoteWin`, `CanaryNoPreVoteWinAfterMembershipChange`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCTickElect / MCExternalPreElect / MCExternalElect / MCStartTransferElection |
| 2 | AffectedActions | MCDeliverPreVoteRequest / MCDeliverPreVoteResponse / MCDeliverVoteRequest / MCDeliverVoteResponse / MCDeliverAppendEntries / MCRefreshServerState / MCRestart |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 |
|---|---|---:|---:|---|---|
| `MC-membership.cfg` | budget used | 3461 | 120.7 | x | x |
| `MC.cfg` | budget used | 2271 | 120.7 | x | x |
| `MC_hunt_prevote_crash.cfg` | budget used | 2634 | 120.6 | x | x |
| `MC_hunt_prevote_inherited_round.cfg` | budget used | 1553 | 120.6 | x | x |
| `MC_hunt_prevote_leader.cfg` | budget used | 1542 | 120.6 | x | x |
| `MC_hunt_prevote_leader_tickonly.cfg` | budget used | 1460 | 120.7 | x | x |
| `MC_hunt_prevote_membership.cfg` | budget used | 2598 | 120.7 | x | x |
| `MC_hunt_prevote_membership_U2.cfg` | budget used | 2696 | 120.6 | x | x |
| `Update-canary-cancel-following.cfg` | budget used | 2305 | 120.6 | x | x |
| `Update-canary-lease-reject.cfg` | budget used | 2093 | 120.7 | x | x |
| `Update-canary-preround-leader.cfg` | budget used | 2184 | 120.6 | x | x |
| `Update-canary-prevote-win.cfg` | budget used | 2056 | 120.6 | x | x |
| `Update-canary-win-after-membership.cfg` | budget used | 3074 | 120.5 | x | x |
| `Update-discharge-seed1.cfg` | budget used | 3216 | 120.6 | x | x |
| `Update-discharge.cfg` | budget used | 1872 | 120.6 | x | x |
| `Update-focused-U2U4.cfg` | budget used | 2927 | 120.5 | x | x |
| `Update-focused-rest.cfg` | budget used | 2700 | 120.2 | x | x |
| `Update-focused.cfg` | budget used | 3429 | 120.3 | x | x |
| `Update-full-U2U4.cfg` | budget used | 2561 | 120.3 | x | x |
| `Update-full-prevote.cfg` | budget used | 2584 | 120.2 | x | x |
| `Update-full-rest.cfg` | budget used | 2485 | 120.2 | x | x |
| `Update-full.cfg` | budget used | 2170 | 120.2 | x | x |
| `Update-open-U2U4.cfg` | budget used | 4049 | 120.2 | x | x |
| `Update-open-rest.cfg` | budget used | 4419 | 120.2 | x | x |
| `Update-open.cfg` | budget used | 4523 | 120.2 | x | x |
