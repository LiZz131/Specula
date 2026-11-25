# Modeling brief coverage (incremental run, Pre-Vote update)

Coverage is `LIMITED_COVERAGE`: finite three-node universe, bounded terms, log
indices, election/Pre-Vote starts, membership appends, crashes, drops, and
message cardinality. No fairness or liveness claim. TLC run outcomes and bounds
are in `spec/output/*.log` and the campaign table of `spec/bug-report.md`.

## Scenario coverage

| Scenario | Base/MC actions | Enabled configuration | Fresh implementation evidence |
|---|---|---|---|
| V0-1 Election persistence | `DoElectCore`, `PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast` | `MC.cfg`, `MC-membership.cfg`, all Update cfgs | `start_election`, `elect_cancels_pre_vote` |
| V0-2 Ordered vote-request guards | `HandleVoteRequest` | `MC.cfg`, Update cfgs | `reject_stale_log`, `grant_greater_vote`, `vote_req_cancels_pre_vote` |
| V0-3 Frozen joint quorum | `HandleVoteResponse`, `IsQuorum` | `MC-membership.cfg`, `MC_hunt_prevote_membership.cfg` | `establish_leader`, `pre_vote_joint_config` |
| V0-4 Delayed responses, establishment, contact | `HandleVoteResponse`, `SendAppendEntries`, `HandleAppendEntries` | `MC.cfg` | `establish_leader`, `candidate_pre_round_survives_leadership` |
| V0-5 Crash/restart | `Crash`, `Restart` | all MC configs, `MC_hunt_prevote_restart.cfg` | `restart_follower`, `restart_drops_pre_round` |
| U1 Timer Pre-Vote gates term increase | `TickPreElect`, `TickElect`, `PreElect`, `HandlePreVoteResponse` | `Update-full-enabled.cfg`, `MC_hunt_prevote_term.cfg`, `MC_hunt_prevote_leader.cfg` | `pre_elect`, `pre_elect_single_voter`, `pre_vote_round` |
| U2 Round lifecycle vs real election/leadership | `TickPreElect`, `HandleVoteResponse`, `HandlePreVoteResponse`, `PersistVote` | `MC_hunt_prevote_leader.cfg`, `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg`; canary `Canary-leader-tick-round.cfg` | `candidate_pre_round_survives_leadership`, `leader_pre_vote_win`; repro tests |
| U3 Responder guards / read-only | `HandlePreVoteRequest`, `ExpireLease` | all Update cfgs; canaries `Canary-LeaseRejectedPreVote.cfg`, `Canary-rejected-resp.cfg` | `pre_vote_req_lease_reject`, `_log_reject`, `_vote_reject`, `_grant` |
| U4 Cancellation and recovery | `PreClearIf` in `DoElectCore`, `HandleVoteRequest`, `HandleVoteResponse`, `HandleAppendEntries`, `RefreshServerState`, `Restart` | `MC_hunt_prevote_restart.cfg`, Update cfgs; canaries `Canary-PreVoteCancelledByFollowing.cfg`, `Canary-PreVoteAfterRestart.cfg` | `vote_req_cancels_pre_vote`, `elect_cancels_pre_vote`, `restart_drops_pre_round`, `pre_vote_stale_resp` |
| U5 Frozen Pre-Vote quorum vs membership | `PreElect`, `AppendJointConfig`, `AppendUniformConfig`, `CommitMembership`, `EnvUpdate` | `MC_hunt_prevote_membership.cfg`, `Update-open.cfg`, `Update-discharge.cfg`; canary `Canary-joint-round.cfg` | `pre_vote_joint_config` |

## Property wiring

| Property | Defined | Enabled |
|---|---|---|
| `TypeOK` / `MCTypeOK` / `TraceTypeOK` | base / MC / Trace | every cfg |
| `DurableVoteNotAhead`, `DurableLogNotAhead`, `VoteRequestAfterDurable`, `GrantedResponseAfterDurable`, `LeaderRoleHasCommittedSelfVote`, `CandidateRoleHasPendingSelfVote`, `CertifiedLeaderHasFrozenQuorum`, `MembershipAtMostOneOutstanding`, `NoForgedMessageEndpoints` | base | `MC.cfg`, `MC-membership.cfg`, all Update and hunt cfgs (Trace.cfg: subset) |
| `TickPreVoteNeverDeposesLeader` (U2) | Update | `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg`, `MC_hunt_prevote_leader.cfg` |
| `SelfTermIncreaseNeedsPreVoteQuorum` (U1) | Update | `Update-full-enabled.cfg`, `MC_hunt_prevote_leader.cfg`, `MC_hunt_prevote_term.cfg` |
| `PreVoteRequestIsReadOnly`, `PreElectLeavesVoteUnchanged` (U1/U3) | Update | all Update and hunt cfgs |
| `PreVoteProbeIsNextTerm`, `PreVoteTrackerWellFormed` (U2/U4/U5) | Update | all Update and hunt cfgs (`PreVoteTrackerWellFormed` disabled only in `Update-full-noU2-noMC2.cfg` after MC-2) |
| MC-1 / MC-2 counterexamples | `spec/output/*_violation.out` | `MC_hunt_prevote_leader.cfg`, `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg`; `MC_hunt_prevote_stale_grant_tight.cfg`, `Update-full-noU2.cfg` (simulation) |
| `DischargeContext` | Update | `Update-discharge.cfg` |
| Canaries (`CanaryNo*`, expected violations) | Update | `Canary-*.cfg` |
| `TraceConsumed` | Trace | `Trace.cfg` |

## Non-vacuity

Reachability is established by the eight canary runs (all produced witnesses, 4-11 states:
Pre-Vote election, Leader holding a timer round, lease rejection, rejected response,
greater-log hint, cancellation by following, restart, joint round) listed in the
campaign table of `spec/bug-report.md`; the MC-1/MC-2 counterexamples additionally
witness the U2 and U5 interactions. The V0 primary configuration was
found vacuous for elections (no Leader reachable, `spec/output/v0-vacuity-noleader.log`);
after the `LogEq` repair the standard configuration reaches Leaders (canary
`Canary-leader-tick-round.cfg` and the MC-1 counterexample).

## Honest limits

- Trace scenarios are deterministic engine-level runs; runtime timer guards, IO
  completion, network delivery, AppendEntries receipt and membership-driven
  refresh are not traced (as in V0).
- CR-1 (Pre-Vote term stall) is outside the model's log abstraction and is
  supported only by code review and an engine-level simulation.
- No liveness property is model-checked.
