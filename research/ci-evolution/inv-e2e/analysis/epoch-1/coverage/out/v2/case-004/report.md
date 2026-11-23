# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CanaryLearnerCandidate`, `CanaryLearnerLeader`, `CanaryLearnerPanic`, `CanaryOldLeaderStepsDown`, `CanaryTransferCommit`, `CanaryTransferCrash`, `CanaryTransferElect`, `CanaryTransferLeaderWon`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCTransferLeader |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 |
|---|---|---:|---:|---|
| `MC.cfg` | budget used | 22369 | 120.7 | x |
| `Update_canary_CanaryLearnerCandidate.cfg` | budget used | 22767 | 120.5 | x |
| `Update_canary_CanaryLearnerLeader.cfg` | budget used | 21488 | 120.3 | x |
| `Update_canary_CanaryLearnerPanic.cfg` | budget used | 22336 | 120.3 | x |
| `Update_canary_CanaryOldLeaderStepsDown.cfg` | budget used | 19404 | 120.8 | x |
| `Update_canary_CanaryTransferCommit.cfg` | budget used | 21154 | 120.6 | x |
| `Update_canary_CanaryTransferCrash.cfg` | budget used | 21641 | 120.6 | x |
| `Update_canary_CanaryTransferElect.cfg` | budget used | 19835 | 120.7 | x |
| `Update_canary_CanaryTransferLeaderWon.cfg` | budget used | 21077 | 120.5 | x |
| `Update_discharge.cfg` | budget used | 21134 | 120.6 | x |
| `Update_focused.cfg` | budget used | 19571 | 120.6 | x |
| `Update_full.cfg` | budget used | 21750 | 120.5 | x |
| `Update_full_controls.cfg` | budget used | 21056 | 120.7 | x |
| `Update_hunt_U1_voter_transfer.cfg` | budget used | 24769 | 120.8 | x |
| `Update_hunt_U2_learner_consequence.cfg` | budget used | 22776 | 120.7 | x |
| `Update_hunt_U2_learner_transfer.cfg` | budget used | 25485 | 120.4 | x |
| `Update_hunt_U2_panic.cfg` | budget used | 24370 | 120.1 | x |
| `Update_open.cfg` | budget used | 27397 | 120.2 | x |
| `Update_open_controls.cfg` | budget used | 27367 | 120.2 | x |
