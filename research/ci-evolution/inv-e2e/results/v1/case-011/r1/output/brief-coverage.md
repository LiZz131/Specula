# Modeling brief coverage

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

# V1 coverage audit (Pre-Vote update)

| Update scenario | Reference/MC actions | Update.tla focus | Enabled cfgs | Fresh implementation evidence |
|---|---|---|---|---|
| U-S1 pre-vote request purity/guards | `HandlePreVoteRequest` (`DeliverPreVoteRequest`) | `AffectedHandlers`, `PreVoteRequestPure` | `Update-full(-noU4)`, `Update-focus(-noU4)`, `Update-open(-noU4)`, `Update-hunt-next-term` | `pre_vote_req_{grant,reject_lease,reject_log,reject_vote}` (all guards, pre == post, 0 commands) |
| U-S2 quorum -> election | `PreElect`, `TickPreElect`, `ExternalPreElect`, `SendPreVoteRequest`, `FinishPreVoteBroadcast`, `HandlePreVoteResponse`, `DoElect` | `AffectedStart`, `AffectedDispatch`, `PreCandidateVoteIsNextTerm`, `PreVoteElectsProbedVote` | same | `pre_elect_{multi,single}`, `pre_vote_resp_quorum`, `pre_vote_resp_joint_accumulate`, `pre_vote_resp_reject_greater_log` |
| U-S3 cancellation by old context | `HandleVoteRequest`, `HandleVoteResponse` (adopt), `HandleAppendEntries`, `RefreshServerState`, `StartElection`, `Restart` | `InteractionActions`, `PreVoteClearingContext` | same + canary `CanaryNoPreVoteCleared` | `pre_vote_superseded_by_{vote_req,append,elect}` (refresh/restart: model + code reading only) |
| U-S4 round x establishment | `TickPreElect` on Candidate, `HandleVoteResponse` (wins), `HandlePreVoteResponse` | `PreVoteNeverDemotesLeader`, `NoStalePreCandidateAtLeader` | `Update-hunt-stale-precandidate`, `Update-full(-U4)`, `Update-focus`, `Update-open` | `candidate_pre_vote_then_leader` (5 events + debug-assert observation) |
| Omitted context: membership evolution | `AppendJointConfig`, `AppendUniformConfig`, `CommitMembership` | `EnvUpdate`, `DischargeContext` | `Update-open(-noU4)`, `Update-discharge(-membership)` | V0 membership traces rerun (`append_joint_membership`, `commit_membership`) |

Property wiring: every update property is enabled in at least one cfg
(`Update-full.cfg`: all five; `-noU4`/`-U4` companions split U4/U5 from
U1-U3 after the MC-1 violation). Unaffected core properties stay enabled in
`MC.cfg`/`MC-membership.cfg` and as controls in the Update cfgs.

Not covered by fresh traces (model/code-review only): runtime tick decision
and rate limit (`handle_tick_election`), runtime response correlation (driven
by the harness rule, not RaftCore), `RefreshServerState` and `Restart`
clearing of a live round, RPC error/timeout handling. The integration tests
`tests/elect/t12_pre_vote.rs` (6 tests) pass on the updated tree and exercise
the runtime paths end-to-end (`spec/output/v1-baseline-elect.log`), but they
emit no traces.

## V1 campaign results (summary)

| Property | Result | Where |
|---|---|---|
| `PreVoteNeverDemotesLeader` (U4) | **VIOLATED** (MC-1) | `Update-hunt-stale-precandidate.cfg` (16 states), `Update-full-U4.cfg` (13 states, complete MCNext) |
| `NoStalePreCandidateAtLeader` (U5) | **VIOLATED** (MC-1 precursor) | `Update-full.cfg`, `Update-focus.cfg`, `Update-open.cfg` |
| `PreCandidateVoteIsNextTerm`, `PreVoteElectsProbedVote`, `PreVoteRequestPure` | no violation, budget-limited | `Update-full-noU4`, `Update-focus-noU4`, `Update-open-noU4`, `Update-hunt-next-term` (BFS + simulation) |
| `DischargeContext` | no violation, budget-limited | `Update-discharge`, `Update-discharge-membership` |
| V0 reference properties | no violation, budget-limited | `MC.cfg`, `MC-membership.cfg` (BFS + simulation) |

Full table: `spec/output/v1-campaign-table.md`.
