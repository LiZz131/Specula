# Modeling brief coverage — incremental revision (Pre-Vote)

V0 audit preserved in `spec/prior-v0/brief-coverage-v0.md`. **Correction to V0:**
the V0 claim that the three-voter `MC.cfg` covered elections is not supported —
because `LogLE(NoLog(j), NoLog(i))` was FALSE for `i /= j`, no remote vote was
ever granted and no Leader was reachable in the V0 `MC.cfg` space
(`spec/output/prior-v0-vacuity-canary.log`: 640,830 distinct states, invariants
`PriorNoLeader`, `PriorNoGrantedRemoteVote` never violated). V0 leader coverage
came only from the single-voter companion. Repaired as R-5.

## Scenario coverage

| Scenario | Base/MC actions | Enabled configuration(s) | Fresh implementation evidence | Reachability |
|---|---|---|---|---|
| V0-1 Election persistence | `DoElect`, `PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast` | `MC.cfg`, all Update cfgs | `start_election`, `candidate_prevote_then_establish` (silent completions) | canary `CanaryNoLeader` |
| V0-2 Vote-request guards | `HandleVoteRequest` | `MC.cfg`, Update cfgs | `reject_stale_log`, `grant_greater_vote`, `grant_empty_logs`, `prevote_cleared_by_vote_grant` | |
| V0-3 Frozen joint quorum | `HandleVoteResponse`, `IsQuorum` | `MC.cfg`, `MC-membership.cfg`, `Update_full*`, `Update_discharge` | `establish_leader`, `candidate_prevote_then_establish` | |
| V0-4 Establishment / contact | `HandleVoteResponse` wins, `SendAppendEntries`, `HandleAppendEntries` (R-1) | all | `establish_leader`, `prevote_cleared_by_append` | canary `CanaryNoFollowerLog` |
| V0-5 Crash/restart | `Crash`, `Restart` | `MC.cfg`, `MC-membership.cfg`, `Update_full*`, `Update_focused`, `Update_open` | `restart_follower` | |
| U-S1 Pre-Vote gates the term bump | `TickElect`, `PreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`, `DoElect` | all Update cfgs | `prevote_quorum_elect`, `prevote_single_voter`, `prevote_reject_higher_vote` | canaries `CanaryNoPreCandidate`, `CanaryNoGrantedPreVoteResp`, `CanaryNoLeader` |
| U-S2 Higher votes invisible to Pre-Vote | `HandlePreVoteRequest`, `HandlePreVoteResponse`, `HandleAppendEntries`, `Crash` | `MC_hunt_prevote_livelock.cfg`, `Update_full*`, witness closure/control | `prevote_reject_higher_vote`, `prevote_request_branches` | canary `CanaryNoRejectedPreVoteResp`; MC witness |
| U-S3 Pre-candidate survives establishment | `HandleVoteResponse` (wins) + `HandlePreVoteResponse` → `DoElect` | `MC_hunt_prevote_leader_demote.cfg`, `Update_full` | `candidate_prevote_then_establish` | canary `CanaryNoLeaderWithPreCandidate`; MC witness |
| U-S4 Cancellation by old consumers | `HandleAppendEntries`, `HandleVoteRequest`, `HandleVoteResponse`, `RefreshServerState`, `Restart` | all Update cfgs | `prevote_cleared_by_append`, `prevote_cleared_by_vote_grant` | canary `CanaryNoPreCandidateCleared` |
| U-S5 Responder guards | `HandlePreVoteRequest` | all Update cfgs | `prevote_request_branches`, `prevote_request_lease`, `grant_empty_logs` | |
| U-S6 Membership context | `AppendJointConfig`, `AppendUniformConfig`, `CommitMembership` (omitted from focused) | `Update_full*`, `Update_open` (`EnvUpdate`), `Update_discharge` | V0 `append_joint_membership`, `commit_membership` | |

## Property wiring (actual cfg files)

| Property | Defined | Enabled in |
|---|---|---|
| `TypeOK`/`MCTypeOK`/`TraceTypeOK` | base/MC/Trace | every cfg |
| `DurableVoteNotAhead`, `DurableLogNotAhead`, `LeaderRoleHasCommittedSelfVote`, `CandidateRoleHasPendingSelfVote`, `CertifiedLeaderHasFrozenQuorum`, `MembershipAtMostOneOutstanding`, `NoForgedMessageEndpoints` | base | `base.cfg`, `MC.cfg`, `MC-membership.cfg`, `Trace.cfg`, all `Update_*` (except discharge), both hunts |
| `VoteRequestAfterDurable`, `GrantedResponseAfterDurable` | base | `base.cfg`, `MC.cfg`, `MC-membership.cfg`, all `Update_*` (except discharge), both hunts |
| `PreCandidateProbesNextTerm` | Update | `Update_full*`, `Update_focused`, `Update_open`, both hunts |
| `PreVoteQuorumNeverDemotesLeader` | Update | `Update_full`, `Update_focused`, `Update_open`, `MC_hunt_prevote_leader_demote` |
| `NoPermanentPreVoteLivelock` | Update | `Update_full`, `Update_full_cont1`, `Update_focused`, `Update_open`, both hunts |
| `LivelockClosed` | Update | `Update_full*`, `Update_focused`, `MC_hunt_prevote_livelock` |
| `DischargeContext` | Update | `Update_discharge` |
| `TraceConsumed` | Trace | `Trace.cfg` |

Campaign outcomes and coverage numbers: `spec/bug-report.md` and
`validation-summary.json`.
