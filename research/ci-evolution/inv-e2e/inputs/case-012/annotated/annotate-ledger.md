# Requirement-evidence ledger

Model: `spec-original/` (OpenRaft replication progress and commit calculation), annotated copy in `spec-annotated/`.
Scope: every name after `INVARIANT(S)` / `PROPERTY(IES)` in any `.cfg`, including commented-out lines. There is no `Update.tla`.
None of the in-scope names is a pure alias (`A == B`). `NotReach*` are negations of the `Reach*` helpers in `base.tla`, and `MCTypeOK` extends `TypeOK`, so each one has its own block.

| Property | File | Status | Evidence types (non-impl first) | Intent (one line) |
|---|---|---|---|---|
| `ElectionSafety` | base.tla | unknown | impl | Two leaders in the same term hold a vote for the same node, so a term never has two different leaders. |
| `ActiveLeaderHasCommittedVote` | base.tla | requirement | contract, comment, history, test, impl | A node in the leader role always holds a quorum-granted (committed) vote. |
| `CommitWithinLocalLog` | base.tla | requirement | comment, doc, history, test, impl | A node's commit index never points past the last entry of its own log. |
| `CommittedLogAgreement` | base.tla | requirement | comment, doc, impl | Any two nodes have entries of the same term at every index up to the smaller of their commit indexes. |
| `CommitWitnessSound` | base.tla | mixed | comment, history, doc, impl | A recorded commit point stays at or below the commit index, stays in the log with its term, and is backed by a quorum of the commit-time membership whose matched positions reach it in that term. |
| `MembershipOrder` | base.tla | requirement | doc, comment, history, test, impl | The committed membership's log index is never greater than the effective membership's log index. |
| `OneOutstandingMembership` | base.tla | requirement | comment, history, doc, contract, impl | While the effective membership entry is beyond the commit index, the membership recorded as committed is a strictly earlier entry. |
| `TypeOK` | base.tla | model-internal | — | Every variable stays in its declared domain and every membership config is well formed. |
| `MCTypeOK` | MC.tla | model-internal | — | `TypeOK` plus every exploration-budget counter stays within its bound. |
| `NotReachLeader` | MC.tla | model-internal | — | Reachability canary, expected to be violated: a leader is reachable. |
| `NotReachCommitWitness` | MC.tla | model-internal | — | Reachability canary, expected to be violated: a commit advance is reachable. |
| `NotReachOutstandingMembership` | MC.tla | model-internal | — | Reachability canary, expected to be violated: an effective-but-uncommitted membership is reachable. |
| `TraceMatched` | Trace.tla | model-internal | — | Trace validation eventually consumes every recorded trace line. |

`CommitWitnessSound` clauses:

| Clause | Status | Origin |
|---|---|---|
| quorum-support | requirement | raft_state.rs:45, core/replication.rs:209-211, raft-essentials.md:8/103/106, 1451f96 (deleted async-raft doc), progress/mod.rs:4, 9915089 |
| entry-retained | requirement | raft-essentials.md:79, :84 |
| commit-not-below-witness | requirement | only the deleted doc line 1451f96:async-raft/src/core/replication.rs:285; at base the rule exists only in code |
| witness-bookkeeping | model-internal | observer records (`witness*`) |

## Counts by status (13 properties)

| Status | Count | Properties |
|---|---|---|
| requirement | 5 | ActiveLeaderHasCommittedVote, CommitWithinLocalLog, CommittedLogAgreement, MembershipOrder, OneOutstandingMembership |
| mixed | 1 | CommitWitnessSound |
| unknown | 1 | ElectionSafety |
| impl-abstraction | 0 | — |
| model-internal | 6 | TypeOK, MCTypeOK, NotReachLeader, NotReachCommitWitness, NotReachOutstandingMembership, TraceMatched |

## Where the status is weakest

- **ElectionSafety (unknown).** The Raft rule "at most one leader in a given term" appears only in the general Raft notes (`raft-essentials.md:25`). Commit a68a9a9 deliberately dropped it for openraft ("in a `term`, it allows to elect more than one leader"), so I did not count it as a requirement of this system. See `concerns.md`.
- **OneOutstandingMembership (requirement).** The sources mean "committed" at the cluster level. Only one commit message (7f34793) ties it to the node's own commit index, and that index is volatile. A scratch TLC run shows the formula breaks after a crash. See `concerns.md`.
- **CommitWitnessSound, clause commit-not-below-witness.** This rests on one deleted doc line from history.
