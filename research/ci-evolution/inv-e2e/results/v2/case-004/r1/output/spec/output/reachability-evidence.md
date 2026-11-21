# Reachability and non-vacuity evidence (current run, final model)

## Update canaries (expected violation = witness), `Update_canary_*.cfg`, MCSpec,
## constants = Update_full_controls.cfg (Server {1,2,3}, voters {1,2}, MaxTerm 2, MaxIndex 2)

| Canary | Scenario | Result | Depth | Log |
|---|---|---|---:|---|
| CanaryTransferElect | U1/U4: TransferLeader target starts a new-term election | witnessed | 11 | `mc-Update_canary_CanaryTransferElect.log` |
| CanaryTransferLeaderWon | U1: transfer target becomes Leader | witnessed | 16 | `mc-Update_canary_CanaryTransferLeaderWon.log` |
| CanaryTransferCommit | U1: transfer leader commits an own-term entry | witnessed | 26 | `mc-Update_canary_CanaryTransferCommit.log` |
| CanaryOldLeaderStepsDown | U1: old leader grants the transfer vote and follows | witnessed | 13 | `mc-Update_canary_CanaryOldLeaderStepsDown.log` |
| CanaryTransferCrash | U4: target crashes before its vote is durable | witnessed | 12 | `mc-Update_canary_CanaryTransferCrash.log` |
| CanaryLearnerCandidate | U2: learner campaigns | witnessed | 13 | `mc-Update_canary_CanaryLearnerCandidate.log` |
| CanaryLearnerPanic | U2: learner self-grant panics | witnessed | 16 | `mc-Update_canary_CanaryLearnerPanic.log` |
| CanaryLearnerLeader | U2: learner becomes Leader | **not witnessed** in 7,196,944 distinct states (depth 29, 15-min budget) — consistent with the code: the self grant is queued before any remote grant and panics first | 29 | `mc-Update_canary_CanaryLearnerLeader.log` |

Canaries were run after the self-grant-order MC repair and before the SaveCommit repair; none
of the witnesses uses `SaveCommit` except CanaryTransferCommit's prefix, whose 2-voter quorum
always includes the leader (self match = flushed index), so the SaveCommit guard holds on it.
Round-1 canaries (before the self-grant-order repair) are in `canary-r1-superseded/`.

## Action coverage (TLC `-coverage`, distinct:total at the end of the run)

See `spec/output/model-checking-summary.md` and the coverage blocks in the logs.
`MC-standard` and `Update_full_controls`: every MC action has nonzero distinct coverage except
`MCUniform` (0:0 — `MembershipLimit = 1` permits learner/joint but not joint→uniform, as in V0;
the uniform transition is covered by the fresh `uniform-membership.ndjson` trace) and
`MCRespond` (distinct 0 — it changes only `commands`, which `MCView` excludes; nonzero total).
`MCTransferLeader` ≈ 2.8e5 distinct states in each run.

## Trace reachability

18 fresh traces (8 Engine-level, 10 RaftCore sessions) reach: TransferLeader at voter targets,
at a learner target, at non-targets (followers and the old leader), with a stale `from`;
peers' grants (incl. the old leader stepping down); candidate self and remote grants to
leadership. See `spec/output/validation-handoff.md`.
