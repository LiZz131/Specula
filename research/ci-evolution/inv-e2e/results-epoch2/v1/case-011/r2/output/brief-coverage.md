# Modeling brief coverage (V0 prior + Pre-Vote update)

This is a V0 prior audit, not an incident hunt. There are no model-checkable findings or target campaigns by experiment design.

## Scenario coverage

| Modeling-brief scenario | Base/MC actions | Enabled configuration | Fresh implementation evidence |
|---|---|---|---|
| Election persistence and ordered dispatch | `StartElection`, `PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast` | `MC.cfg`, `MC-membership.cfg` | `start_election.ndjson` observes `SaveVote` and `SendVote` pending together; `TraceConsumed` passed |
| Ordered vote-request guards | `HandleVoteRequest`, lease/log/vote predicates | `MC.cfg` | `reject_stale_log.ndjson` and `grant_greater_vote.ndjson`; both fully consumed |
| Frozen joint quorum | `HandleVoteResponse`, `IsQuorum`, `leaderConfig`, `leaderGrants` | both MC configs; `CertifiedLeaderHasFrozenQuorum` enabled | `establish_leader.ndjson`; companion MC coverage evaluates the certified-leader antecedent in 118,452 node states |
| Effective/committed membership split | `AppendJointConfig`, `CommitMembership`, `AppendUniformConfig`, `RefreshServerState` | `MC-membership.cfg` non-vacuity companion | append and commit traces consumed; TLC reports 2,508 joint-append and 9,288 uniform-append successor evaluations |
| Delayed persistence / message delivery | `votePersistPending`, `replyPending`, `logFlushPending`, message set, send/deliver/drop actions | `MC.cfg` | command-pending flags in election, vote-grant, establishment, and membership traces |
| Crash/restart | `Crash`, `Restart` | both MC configs | `restart_follower.ndjson` consumed; crash action coverage is nonzero |

## Safety-property wiring

| Property | Defined | Enabled |
|---|---|---|
| `TypeOK` / `MCTypeOK` / `TraceTypeOK` | `base.tla`, `MC.tla`, `Trace.tla` | all configs |
| `DurableVoteNotAhead` | `base.tla` | `base.cfg`, `MC.cfg`, `MC-membership.cfg`, `Trace.cfg` |
| `DurableLogNotAhead` | `base.tla` | all configs |
| `VoteRequestAfterDurable` | `base.tla` | both MC configs; trace ordering observed via pending commands |
| `GrantedResponseAfterDurable` | `base.tla` | both MC configs; strict trace response is retained behind `replyPending` |
| `LeaderRoleHasCommittedSelfVote` | `base.tla` | all configs |
| `CandidateRoleHasPendingSelfVote` | `base.tla` | all configs |
| `CertifiedLeaderHasFrozenQuorum` | `base.tla` | all configs |
| `MembershipAtMostOneOutstanding` | `base.tla` | all configs |
| `NoForgedMessageEndpoints` | `base.tla` | all configs |
| `TraceConsumed` | `Trace.tla` | `Trace.cfg` |

## Preserved non-vacuity evidence

- Every one-line trace run generated two distinct trace states, reached cursor 2, checked temporal properties, and reported no error. Logs are `spec/output/trace-*.log`.
- The primary three-voter `MC.cfg` run completed with 5,273,983 generated states, 640,830 distinct states, depth 24, and zero states left.
- `MC-membership.cfg` retains the same three-node universe but begins with a one-voter effective configuration. It completed with 1,558,889 generated states, 181,185 distinct states, depth 28, and nonzero coverage for leader, joint-membership, uniform-membership, commit, crash, and restart paths.
- TLC expression coverage shows nontrivial antecedents: granted response checks reached 12 node-message evaluations, leader-role implications reached 152,826 leader-node evaluations, and frozen-quorum implications reached 118,452 certified-leader-node evaluations in the membership companion run.

## Honest limits

Coverage is `LIMITED_COVERAGE`: three modeled nodes, term at most 2 (3 for captured traces), log index at most 4, at most two election starts and membership appends, one crash, one message drop, and bounded message cardinality. The trace batch contains seven deterministic, single-transition exact-old scenarios; it does not cover standalone runtime completion events, uniform append, append-RPC receipt, leadership-transfer lease bypass, or established-leader restoration. No fairness or liveness guarantee is claimed. TLC fingerprint collision estimates and all run bounds remain in the logs.



---

## Update coverage (Pre-Vote revision, run incr-315482ff25a1)

### Scenario -> spec/MC/Update/trace

| Update Scenario | Reference actions | Update.tla focus | cfgs | Fresh trace evidence |
|---|---|---|---|---|
| U-1 Pre-Vote probe | `PreElect`, `TickPreElect`, `ExternalPreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse{Tally,Reject,Stale}` | `AffectedActions` (`PreElectActions`, `PreVoteMessageActions`) | `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg`, canaries `CanaryNoPreVoteGrant/Reject` | `pre_elect_follower`, `pre_elect_single_voter`, `pre_vote_req_grant`, `pre_vote_req_reject_lease`, `pre_vote_req_reject_log`, `pre_vote_req_grant_empty_logs`, `pre_vote_resp_reject_greater_log` |
| U-2 Round lifetime vs. elections/leadership | `HandleVoteResponse` (wins keeps / adopt drops), `HandleVoteRequest`, `HandleAppendEntries`, `RefreshServerState`, `Restart`, `DoElect` | `InteractionActions`; `PreVoteElectionPremiseCurrent`, `PreVoteNeverDisplacesLeader`, `EstablishedLeaderHasNoInheritedPreVote` | `Update_full.cfg`, `Update_focused.cfg`, `Update_hunt_stale_round.cfg`, canaries `CanaryNoLeaderWithPreCandidate`, `CanaryNoPreCandidateDroppedByFollow` | `pre_vote_after_establish` (3 events), `pre_candidate_cleared_by_vote` (2 events) |
| U-3 Quorum feeds the real election | `HandlePreVoteResponseElect` -> `DoElect`; `PreElect` self quorum | `PreVoteMessageActions`; reference properties stay enabled | all update cfgs; canaries `CanaryNoPreVoteElect`, `CanaryNoPreVoteElectFromFollower` | `pre_vote_resp_quorum`, `pre_elect_single_voter`, `pre_vote_after_establish` e3 |
| U-5 Round identity across rounds from the same vote | `HandlePreVoteResponseNonMember`, `ExternalPreElect`, `AppendJointConfig`, `CommitMembership`, `AppendUniformConfig` | `PreVoteMessageActions`; `PreVoteGrantFromRoundMember`, `NoPanicOnStalePreVoteGrant` | `Update_hunt_stale_membership.cfg`, `Update_hunt_stale_membership_leader.cfg`; also enabled in full/focused/open cfgs | not traceable (RaftCore panic); integration reproduction `spec/repro/MC-2-repro-*.log` |
| U-4 Trigger/flag/transport | `TickElect` guard, `TickPreElect`, `ExternalPreElect`, `DropMessage` | `PreElectActions` | `TickPreVoteModes = {FALSE, TRUE}` in every cfg | tick/flag branch not traceable at engine level (runtime-only); engine `pre_elect` observed |

### Property wiring (update)

| Property | Defined | Enabled |
|---|---|---|
| `PreVoteElectionPremiseCurrent` | `Update.tla` | `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg` (PROPERTIES) — violated: MC-1 |
| `PreVoteNeverDisplacesLeader` | `Update.tla` | same cfgs (PROPERTIES) |
| `PreVoteElectionPremiseCurrentNonLeader` | `Update.tla` | `Update_*_continue.cfg` (MC-1 filtered) |
| `EstablishedLeaderHasNoInheritedPreVote` | `Update.tla` | `Update_hunt_stale_round.cfg` |
| `PreCandidateTermUnbumped`, `PreVoteMessagesWellFormed` | `Update.tla` | every Update cfg |
| `PreVoteGrantFromRoundMember`, `NoPanicOnStalePreVoteGrant` | `Update.tla` | stale-membership hunts, full/focused/open cfgs — violated: MC-2 |
| `DischargeContext` | `Update.tla` | `Update_discharge.cfg`, `Update_discharge_3voter.cfg` |
| reference invariants (incl. unaffected control `CertifiedLeaderHasFrozenQuorum`) | `base.tla`/`MC.tla` | `MC.cfg`, `MC-membership.cfg`, every Update cfg |

### Non-vacuity

- All six reachability canaries were violated under `MCSpec` on the final suite (logs `spec/output/mc-canary-*.log`).
- Standard-run expression coverage (`spec/output/mc-MC-standard.log`, final suite): Pre-Vote quorum-elect,
  reject, stale, query and round-creation bodies all evaluated (hundreds of thousands to millions of times);
  `Tally` needs a joint config or >= 4 voters and is reached in `MC-membership.cfg` and the discharge runs.
- Discharge: every omitted action fired thousands of times in both discharge seeds.
- The V0 3-voter `MC.cfg` could not elect any leader (absent-log `LogLE` defect, repaired); leader paths
  in the 3-voter configuration are now reachable (canary `CanaryNoLeaderWithPreCandidate` reaches a
  Leader holding a round).
- Trace field mutations: 6/6 rejected (`spec/evidence/trace-mutations/summary.txt`).

### Honest limits (update)

`LIMITED_COVERAGE`: three nodes; `MaxTerm = 2`; at most 2 election starts, 2 Pre-Vote starts, 2
membership appends, 1 crash, 1 drop, 5 in-flight messages; BFS budget-limited (30 min/run) with
simulation follow-up. No fairness/liveness is claimed. The runtime-only parts (tick timing, the
in-flight-round rate limiter, the default-grant network implementation, transport errors) are
abstracted as nondeterminism or message loss.
