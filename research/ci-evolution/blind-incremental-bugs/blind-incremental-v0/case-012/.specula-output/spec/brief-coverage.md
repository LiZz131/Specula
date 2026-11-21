# Modeling brief coverage self-audit

## Scenario coverage

| Brief scenario | Base/MC actions | Hunting config | Trace evidence |
|---|---|---|---|
| 1. Acknowledged progress and commit | `SendAppendEntries`, `DeliverAppendEntries`, `HandleUpdateMatched`, `ProgressUpdateValue` | `MC_hunt_s1_progress.cfg` | `progress.ndjson`, `greatest_majority.ndjson`, `quorum.ndjson` |
| 2. Effective membership | `ProposeMembership`, atomic membership promotion in `HandleUpdateMatched`/delivery | `MC_hunt_s2_membership.cfg` | `leader_membership_append.ndjson`, `membership_update.ndjson`, joint quorum/calculation traces |
| 3. Follower commit cap | `DeliverAppendEntries`, `FollowerCommitEntries`, conflict response | `MC_hunt_s3_follower_commit.cfg` | `follower_commit.ndjson` |
| 4. Ordinary elections | `StartElection`, `GrantVote` | `MC_hunt_s4_election.cfg` | `election.ndjson` |

## Invariant wiring

| Brief invariant | Defined | MC wrapper | Enabled |
|---|---|---|---|
| TypeOK | `base.tla` | `MCTypeOK` | every cfg |
| ElectionSafety | `base.tla` | direct | MC and hunts 1/2/3/4 |
| ActiveLeaderHasCommittedVote | `base.tla` | direct | MC and hunt 4 |
| CommitWithinLocalLog | `base.tla` | direct | MC and hunts 1/2/3 |
| CommittedLogAgreement | `base.tla` | direct | MC and hunts 1/3 |
| CommitWitnessSound | `base.tla` | direct | hunts 1/2 (intentionally commented in convergence MC.cfg) |
| MembershipOrder | `base.tla` | direct | MC and hunt 2 |
| OneOutstandingMembership | `base.tla` | direct | hunt 2 (intentionally commented in convergence MC.cfg) |

## §6.1 question coverage and non-vacuity evidence

| Question | Trigger setup | Oracle | Config/evidence |
|---|---|---|---|
| MC-PRIOR-1 | election, append, send/deliver/ack with optional loss | witness quorum + committed agreement | hunt 1 completed at 30,034 distinct states; `mc-reach-commit-final.log` reaches a witness |
| MC-PRIOR-2 | propose symmetric joint/uniform configurations | membership order/outstanding guard | hunt 2 completed at 80,705 distinct states; `mc-reach-membership-final.log` reaches an outstanding effective membership |
| MC-PRIOR-3 | AppendEntries delivery with leader commit and bounded local last | local-log bound/agreement | hunt 3 completed at 12,831 distinct states; its `MCNext` delivery branch has positive coverage |
| MC-PRIOR-4 | competing ordinary elections with crash/recovery | election safety/committed-vote bit | hunt 4 completed at 30,606 distinct states with positive crash/recover coverage; `mc-reach-leader-final.log` reaches a leader |

No invariant is `TRUE`, a TypeOK alias, or guarded off in all affected configs. The final main and four hunt runs all report `Model checking completed. No error has been found.` with zero states left. Reachability runs intentionally check negated reach predicates and produce the expected counterexamples; those logs are evidence only and are not model failures. Conflict-rejection and negative-ack branches remain unexercised in the converged tight bounds and are explicitly part of the overall limited-coverage classification.

## Bound disclosure

- Converged main: 3 servers, term bound 1, index bound 0, one election and one client append, no membership/fault introduction; 12,831 distinct states.
- Scenario hunts independently enable membership, one message loss, or up to three elections plus one crash/recovery as needed. Each is exhaustive only within its own configuration.
- `MC_scale.cfg` uses term/index bound 2 and broader action/fault budgets. Its preserved 600-second run explored 10,347,332 distinct states without a reported invariant violation but retained 6,580,486 queued states, so it is evidence only—not a completed check.
- These state-space and environment bounds are `LIMITED_COVERAGE`, never proof.
