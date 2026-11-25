# Brief coverage (updated for the Pre-Vote revision)

Generated from the actual cfg files (`spec/*.cfg`). V0 audit content is superseded by this table; V0 limits still apply where noted.

## Scenario coverage

| Scenario | Model actions | Targeting cfg(s) | Fresh implementation evidence |
|---|---|---|---|
| V0-1..5 (election persistence, vote guards, frozen joint quorum, delayed responses, crash/restart) | V0 actions (+ pre-candidate clearing) | MC.cfg, MC-membership.cfg, Update_full.cfg | 7 regenerated V0 traces + grant_vote_empty_logs |
| U1 Pre-Vote round lifecycle | PreElect, TickPreVote, ExternalPreElect, HandlePreVoteRequest, HandlePreVoteResponse{Grant,Elect,Reject,Ignored} | Update_full/focused/open.cfg, MC_hunt_prevote_stale_round.cfg | prevote_start, prevote_tick_start, prevote_req_*, prevote_resp_*, prevote_joint_grant_then_elect |
| U2 stale round outlives own win | HandleVoteResponse(wins) + HandlePreVoteResponseElect | MC_hunt_prevote_stale_round.cfg, MC_hunt_prevote_leader_object.cfg, Update_full.cfg | stale_prevote_after_win; real-runtime repro (spec/output/repro-MC-1-new.log) |
| U3 frozen pre-candidate membership vs current membership | PreElect, AppendJoint/UniformConfig, CommitMembership, RefreshServerState, HandlePreVoteResponseElect | MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg | prevote_joint_grant_then_elect (joint quorum); leader-side membership change is MC-only |
| U4 old actions cancel the round | HandleVoteRequest, HandleVoteResponse(adopt), HandleAppendEntries, RefreshServerState, Restart, DoElect | Update_full.cfg, Update_focused.cfg | prevote_cleared_by_heartbeat, _by_vote_grant, _by_higher_vote_resp |
| U5 default pre_vote RPC grant; single-voter shortcut | DefaultPreVoteRpcGrant, PreElect quorum branch | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_single_voter.cfg, MC-membership.cfg | prevote_single_voter (default RPC is network-layer: MC only) |

## Property wiring

| Property | Defined in | Enabled in |
|---|---|---|
| `MCTypeOK` | MC.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_discharge.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `TypeOK` | base.tla | base.cfg |
| `DurableVoteNotAhead` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `DurableLogNotAhead` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `VoteRequestAfterDurable` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `GrantedResponseAfterDurable` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `LeaderRoleHasCommittedSelfVote` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `CandidateRoleHasPendingSelfVote` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `CertifiedLeaderHasFrozenQuorum` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `MembershipAtMostOneOutstanding` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `NoForgedMessageEndpoints` | base.tla | MC-membership.cfg, MC.cfg, MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Trace.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg, base.cfg |
| `PreVoteRoundNotOutlivedByOwnLeadership` | Update.tla | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `PreVoteElectionByVoter` | Update.tla | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `PreVoteElectionAtProbedVote` | Update.tla | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `PreVoteRequestIsPure` | Update.tla | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `PreVoteStartIsPure` | Update.tla | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `PreVoteGrantFromTrackedVoter` | Update.tla | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `LeaderObjectVoteNotBehind` | Update.tla | MC_hunt_prevote_default_rpc.cfg, MC_hunt_prevote_leader_object.cfg, MC_hunt_prevote_membership.cfg, MC_hunt_prevote_single_voter.cfg, MC_hunt_prevote_stale_round.cfg, Update_focused.cfg, Update_full.cfg, Update_open.cfg |
| `DischargeFlushLog` | Update.tla | Update_discharge.cfg |
| `TraceConsumed` | Trace.tla | Trace.cfg |

Notes:
- `PreVoteRequestIsPure` and `PreVoteStartIsPure` hold by the reference actions' frames; they are kept as falsifiable oracles (observational step recognizers, separating states in `spec/invariant-evidence.json`), but their implementation evidence comes from trace validation (`ValidatePost` compares every captured field; mutants m06/m08 rejected). They are not counted as independent MC coverage.
- `PreVoteElectionByVoter` has status `unknown` (only implementation guards found); a violation is recorded as unresolved, not as a defect.
- `LeaderObjectVoteNotBehind` is also reachable through an operator `trigger().elect(false)` on a Leader in both revisions; `MC_hunt_prevote_leader_object.cfg` (no non-Pre-Vote elections) isolates the update path.
- Reachability canaries (`Update_canary_*.cfg`) are expected to be violated: 5/5 witnessed (`spec/output/canaries-round1.status`).
- `*_filtered.cfg` variants add `ACTION_CONSTRAINT KnownFindingsFilter` (prunes transitions into a state violating `LeaderObjectVoteNotBehind`, i.e. the two analyzed counterexamples MC-1 and CR-PRE-1) and comment out the two properties those counterexamples violate; every other property stays enabled. They exist to keep hunting after the first finding (validation-workflow "filter the known counterexample").
- Non-vacuity: expression coverage of the key update branches in the standard runs is in `spec/output/coverage-keylines-std.log` (e.g. Pre-Vote quorum→elect 1,659,101 evaluations and leader establishment 5,544,365 in `MC.cfg`); the default-RPC branch is exercised only by `MC_hunt_prevote_default_rpc*.cfg`.
- `MC_hunt_prevote_{membership,single_voter}_filtered_nog.cfg` additionally disable `PreVoteElectionByVoter` (D-2, unresolved) and `PreVoteGrantFromTrackedVoter` (MC-2) after their counterexamples were recorded, so the hunts could continue; all other properties stay enabled.
- No liveness property is claimed (no fairness assumption is grounded in the source).
