# Review decisions

One row per `REQ-EVIDENCE` block in `out/spec-reviewed/` (13 blocks, 13 in-scope properties).
"Old" is the block in `spec-annotated/`; "new" is the block in `spec-reviewed/`.

| Property | Old status | New status | Intent changed | Evidence lines retyped or removed | Reason (one line) |
|---|---|---|---|---|---|
| TypeOK (`base.tla`) | model-internal | model-internal | no | none | Type invariant. The intent matches the formula: every variable is in its domain, plus `ConfigOK` on committed and effective configs. |
| MCTypeOK (`MC.tla`) | model-internal | model-internal | no | none | `TypeOK` plus bounds on the exploration counters. The intent matches the formula. |
| ElectionSafety (`base.tla`) | unknown | unknown | **yes** | none | Dropped "so a term never has two different leaders", because the formula only compares two same-term leaders' votes. Only `impl` evidence. a68a9a9 and leader_id.rs:7-11 justify not counting raft-essentials.md:25. |
| ActiveLeaderHasCommittedVote (`base.tla`) | requirement | requirement | no | none | vote.rs:59 (contract), leader.rs:11, 58f2491 and f882e11 state that a leader holds a committed (quorum-granted) vote. Both tests assert the committed vote together with `ServerState::Leader`. |
| CommitWithinLocalLog (`base.tla`) | requirement | requirement | no | none | engine_impl.rs:356 states "Committed index can not > last_log_id.index" as a role-free rule, not a narration. The guide, change-log, raft-essentials and 2eaab71 back it for followers. The test asserts the cap at the last entry. |
| CommittedLogAgreement (`base.tla`) | requirement | requirement | no | none removed or retyped; 3 arrows narrowed (replication.md:10, raft_state.rs:78, derived-from-async-raft.md:8) | membership_state.rs:16 plus the persistence quotes support pairwise agreement, as the note says. Three arrows claimed more than their quotes say. |
| CommitWitnessSound (`base.tla`) | mixed | mixed | no | none removed or retyped; clause `quorum-support` narrowed and new clause `matched-term-kept: unknown` added | The quotes say matched positions never move back. None says a matched position keeps the committing term, which the `matchedTerm = witnessTerm` conjunct checks. |
| MembershipOrder (`base.tla`) | requirement | requirement | no | removed: `doc source/guide/src/effective-membership.md:18` | That quote says the second-last membership entry is committed, not that the committed record is that entry, as its arrow claimed. The remaining evidence supports the intent. |
| OneOutstandingMembership (`base.tla`) | requirement | requirement | no | retyped comment→impl: `source/openraft/src/core/admin.rs:137`; removed: `membership_state.rs:14`, `storage/helper.rs:98`, `guide/src/effective-membership.md:13`, `guide/src/dynamic-membership.md:134`, `engine/engine_impl.rs:237`, `error.rs:372`; arrow of `membership_state.rs:9` reworded | The removed quotes support propose-after-commit and at-most-one-outstanding, which the formula does not check. admin.rs:137 only restates the condition on :139. membership_state.rs:9 plus 7f34793 support the intent as written. |
| NotReachLeader (`MC.tla`) | model-internal | model-internal | no | none | Reachability canary. Its cfg says it is expected to fail, and the intent matches `~ReachLeader`. |
| NotReachCommitWitness (`MC.tla`) | model-internal | model-internal | no | none | Reachability canary, expected to fail. The intent matches `~ReachCommitWitness` (no recorded witness). |
| NotReachOutstandingMembership (`MC.tla`) | model-internal | model-internal | no | none | Reachability canary, expected to fail. The intent matches the effective-index > committed-index negation. |
| TraceMatched (`Trace.tla`) | model-internal | model-internal | no | none | Trace-validation completeness (`<>(l > Len(TraceLog))`). It is a check about the model and trace, not about the system. |

No `note:` sentence described the model, so none were moved to `concerns.md`; see that file.

## Support analysis per non-`impl` evidence line

For each kept non-`impl` line: the part of the intent that the quote, read literally, supports. "Removed" or "retyped" marks lines that were changed.

### ElectionSafety
- All four evidence lines are `impl`, so there is nothing to support the intent as a requirement.
- The note's sources were checked and are rightly not counted:
  - raft-essentials.md:25 and :54 restate the Raft per-term rules.
  - a68a9a9 (message): "in a `term`, it allows to elect more than one leader" and "A node is able to grant more than one vote within one term".
  - leader_id.rs:7-11: a leader "is actually identified by `(term, node_id)`".
  - The rule "Two committed votes have to be the same" (58f2491:openraft/src/vote/vote.rs:80) was deleted by a68a9a9.
- The formula checks `voteFor[i] = voteFor[j]` for two leaders in the same term. "So a term never has two different leaders" holds only if each leader's vote names itself, and this formula does not check that. The clause was dropped.

### ActiveLeaderHasCommittedVote
- vote.rs:59 (contract): a node is a valid leader only with a committed (quorum-granted) vote. Supports the whole intent.
- leader.rs:11: a node without a committed vote is a candidate in raft terms. Supports "leader ⇒ committed vote".
- raft_state.rs:34: a leader may propose log only once its vote is granted by a quorum. Supports the "quorum-granted" gloss and leader privileges.
- 58f2491 (message): "A Leader has a `Vote` that is committed". Supports the whole intent.
- f882e11 (message): the vote is committed before the node enters leader state. Supports entry into the role.
- handle_vote_resp_test.rs:233 asserts `Vote::new_committed(2, 1)` and `ServerState::Leader`. elect_test.rs:47 asserts `Vote::new_committed(1, 1)` and `ServerState::Leader`. Both are instances of the intent.

### CommitWithinLocalLog
- engine_impl.rs:356 states "Committed index can not > last_log_id.index" as a rule ("can not"), with no role. Supports the whole intent.
- guide/src/replication.md:74 and change-log.md:364: the commit index must point to a log entry consistent with the leader (follower append-entries).
- raft-essentials.md:98: a follower's commitIndex ≤ its last new entry.
- 2eaab71:…/append_entries.rs:56: the commit index must not move past the last known consistent log.
- follower_commit_entries_test.rs:140 asserts `committed == log_id(2, 3)`, the last entry, when the leader's commit is greater.

### CommittedLogAgreement
- membership_state.rs:16: a committed log must be consistent with the leader. Supports each node's committed prefix matching the leader's.
- guide/src/replication.md:10: committed log can always be seen by the next leader. Supports persistence into the next leader's log. Arrow narrowed: "unchanged" and "every later leader" are not in the quote.
- raft-essentials.md:84: only uncommitted follower entries are overwritten. Supports committed entries never being overwritten.
- raft_state.rs:78: a committed log will always be chosen. Supports committed entries being final at their index. Arrow narrowed: "every node keeps" restated the whole intent.
- derived-from-async-raft.md:8: losing a committed entry in append-entries was fixed as a bug. Supports committed entries not being lost. Arrow narrowed: "or replacing" is not in the quote.
- engine_impl.rs:334: committed entries must not become invisible in election. Supports persistence across leaders.
- Pairwise agreement follows from these together, as the note states.

### CommitWitnessSound (mixed)
- raft_state.rs:45, raft-essentials.md:8, 1451f96:…:286 and replication.rs:209: at commit time, the entry is of the leader's term and on a quorum, and replicas matched at another term do not count. Supports clause `quorum-support` at commit time.
- raft-essentials.md:106 and :103: joint quorum, latest configuration. Supports `Quorum(witnessConfig, …)` with the effective config.
- progress/mod.rs:4 and 9915089: matched values never decrease. Supports `matchedIndex ≥ witnessIndex` persisting. They do **not** support `matchedTerm = witnessTerm` persisting: a monotonic log id may move to a later term. Hence the new clause `matched-term-kept: unknown`. History searches found nothing more (see provenance).
- raft-essentials.md:79 and :84: the leader never overwrites or deletes its own entries, and only uncommitted follower entries are overwritten. Supports clause `entry-retained`.
- 1451f96:…:285: the leader's computed commit is never below its previous value. Supports clause `commit-not-below-witness`. The clause text already limits this to the leader and to a deleted doc line. Kept as the annotator recorded it.

### MembershipOrder
- guide/src/effective-membership.md:5, membership_state.rs:18 and 3fd1d8a: the effective membership is the last one. Supports the effective side of the comparison.
- membership_state.rs:9 and :11: "first(committed)" and "second(effective)". Supports the committed record being the earlier of the two.
- update_committed_membership_test.rs:86 asserts committed `(1,2)` and effective `(2,3)` after an update at index 2. An instance.
- guide/src/effective-membership.md:18 was **removed**. "The second last membership log has to be committed" supports no part of the intent: it does not place the committed record relative to the effective one.

### OneOutstandingMembership
- membership_state.rs:9: the record labelled committed must be a committed entry and is the first (earlier) of the two. Supports "the record is never the uncommitted effective entry, and is earlier".
- 7f34793 (message): committedness is checked by comparing the log index with the commit index. Supports "an effective entry beyond the commit index is uncommitted".
- The following were **removed** because they support no part of the intent (they constrain proposals, not which entry is recorded as committed):
  - membership_state.rs:14 and storage/helper.rs:98: at most one uncommitted membership log.
  - guide effective-membership.md:13, dynamic-membership.md:134, engine_impl.rs:237 and error.rs:372: propose only after the previous membership commits.
- admin.rs:137 was **retyped to impl**. "The last membership config is not committed yet." narrates the condition computed on admin.rs:139.
