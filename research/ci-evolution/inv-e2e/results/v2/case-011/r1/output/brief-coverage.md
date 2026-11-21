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

# Update coverage (Pre-Vote revision)

Filled from the actual cfg files in `spec/` (module `Update` for every update/hunt cfg).

## Update Scenarios → artifacts

| Scenario | Actions | Configs | Fresh traces | Outcome |
|---|---|---|---|---|
| U1 side-effect free round | `PreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse` (non-deciding) | `Update-residual.cfg`, `Update-focused-residual.cfg`, `Update-open-residual.cfg` (`PreVoteRoundPersistsNothing`) | prevote_timer_multi, prevote_req_reject_lease, prevote_req_reject_log, prevote_req_grant | see bug-report |
| U2 round outlives own leadership | `TickPreElect` on Candidate, `HandleVoteResponse` (wins), `HandlePreVoteResponse` quorum → `ElectEffects` | `MC_hunt_U2_prevote_leader.cfg`, `Update-full-U2.cfg` (`TimerPreVoteElectsOnlyNonLeader`) | prevote_stale_round_after_leadership | **violated (MC-1)** |
| U3 quorum hands over to election | `HandlePreVoteResponse` quorum, `ElectEffects`, `PersistVote`, `SendVoteRequest` | `Update-residual.cfg` (`PreVoteProbeMatchesElection`, invariant `PreCandidateProbeIsNextTerm`, all prior invariants) | prevote_resp_reject_then_quorum, prevote_external_single_voter | see bug-report |
| U4 round identity by probe only | `ExternalPreElect`/`TickPreElect`, `HandlePreVoteResponse` grant/panic branches, membership actions | `MC_hunt_U4_prevote_stale_round.cfg` (`StalePreVoteResponseIgnored`), `MC_hunt_U4b_prevote_panic.cfg` (`PreVoteResponseNeverPanics`), `Update.cfg` | prevote_round_reuses_probe | **violated (MC-2)** |
| U5 runtime toggle / unimplemented network | `TickElect`/`TickPreElect` under `TickPreVoteModes={FALSE,TRUE}`, fallback grants | `MC_hunt_U5_prevote_fallback.cfg`, `Update*.cfg` (reference modes) | — (network default impl not exercised by engine traces) | see bug-report |
| U6 cancellation / restart | `PreCandidateCleared` in vote request/response/append/refresh/restart | all Update cfgs | prevote_cancelled_by_vote_grant, prevote_round_reuses_probe | traces pass |

## Update properties → enablement

| Property | Defined | Enabled in |
|---|---|---|
| `TimerPreVoteElectsOnlyNonLeader` | `UpdateProps.tla` | `Update.cfg`, `Update-full-U2.cfg`, `MC_hunt_U2_prevote_leader.cfg` |
| `StalePreVoteResponseIgnored` | `UpdateProps.tla` | `Update.cfg`, `MC_hunt_U4_prevote_stale_round.cfg` |
| `PreVoteResponseNeverPanics` | `UpdateProps.tla` | `Update.cfg`, `Update-residual.cfg`, `Update-focused-residual.cfg`, `Update-open-residual.cfg`, `MC_hunt_U4b_prevote_panic.cfg`, `MC_hunt_U4c_prevote_panic_operator.cfg`, `MC_hunt_U5_prevote_fallback.cfg` |
| `PreVoteProbeMatchesElection` | `UpdateProps.tla` | `Update.cfg`, `Update-residual.cfg`, focused/open residual, `MC_hunt_U2`, `MC_hunt_U5` |
| `PreCandidateProbeIsNextTerm` | `UpdateProps.tla` | invariant in every Update/hunt cfg |
| `PreVoteRoundPersistsNothing` | `UpdateProps.tla` | `Update.cfg`, `Update-residual.cfg`, focused/open residual, `MC_hunt_U5` |
| `DischargeContext` | `Update.tla` | `Update-discharge.cfg` |
| prior invariants (all 10) | `base.tla`/`MC.tla` | `MC.cfg` (unchanged list), `Update.cfg`, `Update-residual.cfg`, `Update-focused-residual.cfg` |

## Non-vacuity

Reachability canaries (`UpdateProps.tla`): `CanaryNoCandidate` (multi-voter candidate via Pre-Vote quorum) and
`CanaryNoPreVoteElect` (quorum-elect step) are violated as expected (`spec/output/canary-prevote-elect-*.log`);
the U2/U4 properties have concrete counterexamples; the U4 panic pre-state canaries are in
`spec/output/canary-U4c-*.log` (module `spec/DebugU4.tla`). The prior suite's 3-voter `MC.cfg` could not elect a leader
(LogLE defect, see changelog); after the repair leadership is reachable in `MC.cfg`.

## Honest limits

`LIMITED_COVERAGE`: 3 nodes, `MaxTerm = 2`, `MaxLogIndex = 4`, at most 2 elections / 2–3 Pre-Vote rounds /
2 membership appends / 1 crash / 1 drop, ≤ 5 in-flight messages; BFS runs stop at their 30-minute budget.
Follower-side membership change through replication and timing (timeouts, rate limits) are abstracted.
