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

