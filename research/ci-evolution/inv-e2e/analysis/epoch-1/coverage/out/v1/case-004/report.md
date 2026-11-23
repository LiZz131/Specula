# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CanaryAbsentElect`, `CanaryCrashBeforeSaveVote`, `CanaryNonVoterCandidate`, `CanaryOldLeaderSuperseded`, `CanaryTransferLeaderCommits`, `CanaryTransferVoterLeader`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCTransferLeader |
| 2 | AffectedActions | MCElect |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 |
|---|---|---:|---:|---|---|
| `MC.cfg` | budget used | 5161 | 120.4 | x | x |
| `Update_canary_CanaryAbsentElect.cfg` | budget used | 5010 | 120.3 | x | x |
| `Update_canary_CanaryCrashBeforeSaveVote.cfg` | budget used | 5714 | 120.4 | x | x |
| `Update_canary_CanaryNonVoterCandidate.cfg` | budget used | 4735 | 120.3 | x | x |
| `Update_canary_CanaryOldLeaderSuperseded.cfg` | budget used | 3240 | 120.4 | x | x |
| `Update_canary_CanaryTransferLeaderCommits.cfg` | budget used | 6342 | 120.3 | x | x |
| `Update_canary_CanaryTransferVoterLeader.cfg` | budget used | 5726 | 120.4 | x | x |
| `Update_discharge.cfg` | budget used | 5564 | 120.4 | x | x |
| `Update_focused.cfg` | budget used | 5498 | 120.4 | x | x |
| `Update_focused_voter.cfg` | budget used | 5706 | 120.3 | x | x |
| `Update_full.cfg` | budget used | 6032 | 120.4 | x | x |
| `Update_full_ElectionInitiatorIsVoter.cfg` | budget used | 5456 | 120.3 | x | x |
| `Update_full_NoCorePanic.cfg` | budget used | 3256 | 120.4 | x | x |
| `Update_full_voter.cfg` | budget used | 5002 | 120.3 | x | x |
| `Update_hunt_U1_absent.cfg` | budget used | 4846 | 120.4 | x | x |
| `Update_hunt_U1_absent_nodsb.cfg` | budget used | 5291 | 120.4 | x | x |
| `Update_hunt_U3_voter.cfg` | budget used | 9522 | 120.2 | x | x |
| `Update_hunt_U4_crash.cfg` | budget used | 13681 | 120.2 | x | x |
| `Update_open.cfg` | budget used | 10897 | 120.2 | x | x |
| `Update_open_voter.cfg` | budget used | 11044 | 120.2 | x | x |
