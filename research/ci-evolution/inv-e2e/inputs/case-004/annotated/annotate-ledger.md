# Requirement-evidence ledger

One row per annotated property (one `REQ-EVIDENCE` block each). Evidence types are listed strongest-first as they appear in the block.

| Property | File | Status | Evidence types | Intent |
|---|---|---|---|---|
| `TypeOK` | base.tla | model-internal | — | Every model variable stays inside its declared domain (type correctness of the model state). |
| `IOOrder` | base.tla | requirement | doc, comment, history, test, impl | On every node, the applied index never exceeds the saved committed index, and flushed <= submitted <= accepted <= last log index. |
| `CommitWithinAccepted` | base.tla | requirement | doc, history, test, impl | On every node, the committed log index never exceeds the node's accepted log index. |
| `MembershipOrder` | base.tla | requirement | comment, doc, test, impl | On every node, the committed membership config is never later in the log than the effective membership config. |
| `MembershipWellFormed` | base.tla | mixed (non-empty: requirement, node-domain: model-internal) | comment, contract, test, impl | Every node's effective membership is a joint of one or more voter configs, none of them empty, over known node ids. |
| `LearnersExcluded` | base.tla | requirement | contract, comment, impl | On every node, no node is both a learner and a voter of the effective membership. |
| `CandidateGrantSound` | base.tla | requirement | comment, doc, test, impl | A node in the Leader role holds a committed vote for itself, and its leadership was granted by a quorum. |
| `LeaderVoteCommitted` | base.tla | requirement | comment, history, test, impl | A node in the Leader role has leader state and a committed vote. |
| `MatchWithinLeaderLog` | base.tla | mixed (leader-progress: requirement, non-leader-records: model-internal) | doc, comment, impl | A leader never records any replication target, or itself, as matching beyond the leader's own last log index. |
| `DurableStateBounded` | base.tla | requirement | history, contract, doc, comment, impl | On every node, the saved committed index never points past the persisted log, and the persisted vote is never greater than the current vote. |
| `CurrentTermCommit` | base.tla | requirement | comment, doc, test, impl | On a leader, the entry at the commit index never has a term greater than the leader's current vote term. |
| `CommittedLogAgreement` | base.tla | requirement | doc, comment, impl | Any two nodes hold the same entry (same term and leader node) at every log index up to the smaller of their commit indexes. |
| `TraceMatched` | Trace.tla | model-internal | — | Trace replay eventually consumes every line of the recorded Engine trace, i.e. trace validation runs to completion. |
| `MCTypeOK` | MC.tla | alias → TypeOK | — | Alias of `TypeOK`; see that row. |
| `MCIOOrder` | MC.tla | alias → IOOrder | — | Alias of `IOOrder`; see that row. |
| `MCCommitWithinAccepted` | MC.tla | alias → CommitWithinAccepted | — | Alias of `CommitWithinAccepted`; see that row. |
| `MCMembershipOrder` | MC.tla | alias → MembershipOrder | — | Alias of `MembershipOrder`; see that row. |
| `MCMembershipWellFormed` | MC.tla | alias → MembershipWellFormed | — | Alias of `MembershipWellFormed`; see that row. |
| `MCLearnersExcluded` | MC.tla | alias → LearnersExcluded | — | Alias of `LearnersExcluded`; see that row. |
| `MCCandidateGrantSound` | MC.tla | alias → CandidateGrantSound | — | Alias of `CandidateGrantSound`; see that row. |
| `MCLeaderVoteCommitted` | MC.tla | alias → LeaderVoteCommitted | — | Alias of `LeaderVoteCommitted`; see that row. |
| `MCMatchWithinLeaderLog` | MC.tla | alias → MatchWithinLeaderLog | — | Alias of `MatchWithinLeaderLog`; see that row. |
| `MCDurableStateBounded` | MC.tla | alias → DurableStateBounded | — | Alias of `DurableStateBounded`; see that row. |
| `MCCurrentTermCommit` | MC.tla | alias → CurrentTermCommit | — | Alias of `CurrentTermCommit`; see that row. |
| `MCCommittedLogAgreement` | MC.tla | alias → CommittedLogAgreement | — | Alias of `CommittedLogAgreement`; see that row. |

## Counts by status

| Status | Count | Properties |
|---|---|---|
| requirement | 9 | `IOOrder`, `CommitWithinAccepted`, `MembershipOrder`, `LearnersExcluded`, `CandidateGrantSound`, `LeaderVoteCommitted`, `DurableStateBounded`, `CurrentTermCommit`, `CommittedLogAgreement` |
| mixed | 2 | `MembershipWellFormed`, `MatchWithinLeaderLog` |
| impl-abstraction | 0 | — |
| unknown | 0 | — |
| model-internal | 2 | `TypeOK`, `TraceMatched` |
| alias pointer (MC.tla) | 12 | `MCTypeOK`, `MCIOOrder`, `MCCommitWithinAccepted`, `MCMembershipOrder`, `MCMembershipWellFormed`, `MCLearnersExcluded`, `MCCandidateGrantSound`, `MCLeaderVoteCommitted`, `MCMatchWithinLeaderLog`, `MCDurableStateBounded`, `MCCurrentTermCommit`, `MCCommittedLogAgreement` |

Total blocks: 25 (13 property definitions with full blocks + 12 one-line alias pointers).

Clause breakdown of the `mixed` properties:

- `MembershipWellFormed`: clause `non-empty` (cfg # {} and every child # {}) = requirement; clause `node-domain` (cfg ⊆ SUBSET Server) = model-internal.
- `MatchWithinLeaderLog`: clause `leader-progress` (match recorded by a leader) = requirement; clause `non-leader-records` (match on nodes that are not leaders) = model-internal.

## Least certain classifications

- **`DurableStateBounded` (requirement).** The saved-committed clause is not stated by any single source. It is inferred from 942ec78b (re-apply up to the saved committed id on startup), `storage/v2.rs:34-35` (serialized log-store writes) and `log_pointers.md:34` (`committed ≤ submitted`). `log_pointers.md:30` ("`committed` ≤ `flushed` does not have to hold") concerns the in-memory value. The vote clause is likewise derived: vote monotonicity plus "persists it if `input_vote >= my_vote`".
- **`LeaderVoteCommitted` (requirement).** The committed-vote part is stated in several comments. The "has leader state" part rests on a commit message (36d2c115), the `proposer/leader.rs:18-27` doc and one test; no code comment states it.
- **`MembershipWellFormed` (mixed).** "At least one config" comes only from the `get_joint_config` doc (`membership.rs:124`), and `Membership::default()` is empty.
- **`CommittedLogAgreement` (requirement).** The evidence comes from protocol-level docs (raft-essentials, extended-membership proof, log_replication). No Openraft test asserts cross-node agreement directly.
