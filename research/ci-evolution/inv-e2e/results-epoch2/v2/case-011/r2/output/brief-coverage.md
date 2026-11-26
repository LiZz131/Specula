# Modeling brief coverage — incremental run incr-4e410cd184be

Prior (V0) coverage is retained below the update section only by reference
(`/work/previous/.specular-output/brief-coverage.md`); every row here was
re-checked against the current files.

## Update scenarios

| Scenario | Affected / interaction actions | Configs | Fresh implementation evidence | Outcome |
|---|---|---|---|---|
| U1 timer round outlives establishment | TickPreElect, HandlePreVoteResponse; ExternalElect, PersistVote, SendVoteRequest, HandleVoteResponse (wins) | `Update_hunt_stale_round*.cfg`, `Update_full*.cfg`, `Update_focused*.cfg`, `Update_open*.cfg`; canaries `CanaryNoTickRoundWhileCandidate`, `CanaryNoPreVoteElection` | `traces/stale_pre_vote_after_leader.ndjson` (5 events, validated; mutations M9/M10 rejected) | MC-1 (REPRODUCED, `spec/confirmation-MC-1.md`) |
| U2 side-effect-free pre-vote | HandlePreVoteRequest, HandlePreVoteResponse (non-deciding), PreElectCore (no quorum) | all Update cfgs (`PreVoteStepsDoNotPersist`, `PreVoteElectionAtProbedVote`); mutants MUT-A/MUT-B prove falsifiability | `pre_vote_req_grant/lease_reject/stale_log`, `pre_vote_resp_reject_greater_log`, `pre_vote_resp_no_round`, `pre_elect_multi` (mutations M1-M8, M12 rejected) | no violation within bounds |
| U3 round completes after removal from voters | HandlePreVoteResponse -> ElectEffects (non-voter branch), AppendJoint/Uniform, CommitMembership, PersistVote, HandleVoteResponse | `Update_hunt_nonvoter_elect*.cfg`, `Update_full_cont1.cfg`; canary `CanaryNoNonVoterCandidate` | runtime reproduction only (membership after pre_elect is not capturable by the engine-level harness; see limits) | MC-2 (REPRODUCED) |
| U4 repeated round, same hypothetical vote | ExternalPreElect x2, HandlePreVoteResponse, membership actions | `Update_hunt_repeat_round*.cfg`; canary `CanaryNoRepeatedRoundOtherConfig` | runtime reproduction | MC-3 (REPRODUCED) |
| U5 network default grant, crash/restart | NetworkDefaultPreVote, Crash, Restart, DropMessage | `Update_hunt_default_grant*.cfg`, `Update_full*.cfg` | restart_follower.ndjson (Restart clears round by construction) | see bug-report campaign table |
| Round cleared by following | HandleVoteRequest (follows), HandleAppendEntries, RefreshServerState, ElectEffects | all Update cfgs; canary `CanaryNoRoundClearedByFollowing` | `pre_vote_cleared_by_vote_request.ndjson` (M11 rejected), `pre_vote_resp_quorum.ndjson` (do_elect clears) | consistent |

## Property wiring

| Property | Defined | Enabled |
|---|---|---|
| reference safety set (TypeOK/MCTypeOK, DurableVoteNotAhead, DurableLogNotAhead, VoteRequestAfterDurable, GrantedResponseAfterDurable, LeaderRoleHasCommittedSelfVote, CandidateRoleHasPendingSelfVote, CertifiedLeaderHasFrozenQuorum, MembershipAtMostOneOutstanding, NoForgedMessageEndpoints) | base.tla / MC.tla | base.cfg, MC.cfg, MC-membership.cfg, every Update_*.cfg (control), Trace.cfg (subset) |
| PreCandidateWellFormed | base.tla | all of the above |
| TickPreVoteRoundNotHeldByLeader | Update.tla | Update_full/focused/open, hunts (filtered only in documented follow-ups) |
| LeaderNotPreemptedByTimerPreVote | Update.tla | same |
| PreVoteGrantsWithinFrozenVoters | Update.tla | same (revised form; see invariant-evidence.json) |
| CandidateGrantsWithinFrozenVoters | Update.tla | same (revised form) |
| PreVoteElectionAtProbedVote, PreVoteStepsDoNotPersist | Update.tla | same |
| DischargeContext | Update.tla | Update_discharge.cfg |
| TraceConsumed | Trace.tla | Trace.cfg |

## Honest limits

- Bounded, budget-limited campaigns (`LIMITED_COVERAGE`): 3 nodes (2 in the
  non-voter hunt), terms <= 2-3, log index <= 3-4, bounded elections, pre-vote
  rounds, membership changes, crashes, drops and message counts.
- Membership learners are not modelled; the non-voter election outcome is the
  union of learner-member and non-member behaviour.
- Follower-side membership changes are not modelled (prior abstraction), so the
  follower variant of U4 is covered only by source analysis.
- Trace capture of the frozen candidate/pre-candidate quorum uses the effective
  membership (private field); no traced scenario mutates membership after the
  round starts.
- Runtime-only effects (RPC ttl, tick period, lease durations) are time
  abstractions; the reproductions exercise them in the real runtime.
