# Model observations moved out of `note:` lines

**None were moved.** Every `note:` sentence in `spec-annotated/` describes the evidence search only: what was searched, what was not found, why a source was not counted, and how quotes relate to the intent. None describes how the model's actions or helpers behave, whether the model matches the code, or what might be wrong, unmodelled, vacuous or a false alarm.

No `note:` line, and no other comment in the model, mentioned `concerns.md` (checked with `grep -i concerns` over `spec-annotated/` and `spec-reviewed/`), so there was nothing to remove.

## Notes checked

| Property | Note content (summary) | Verdict |
|---|---|---|
| ElectionSafety | raft-essentials.md:25/:54 not counted, because of a68a9a9 and leader_id.rs:7-11. The deleted 58f2491 rule. Search terms and history commands. cluster-controls.md:13 and fixtures/mod.rs:724 not counted. | evidence only; kept |
| CommitWithinLocalLog | The guide, change-log and raft-essentials quotes are follower-scoped; engine_impl.rs:356 names no role; no quote states the rule for the leader. | evidence only; kept |
| CommittedLogAgreement | No quote states pairwise agreement directly; it follows from the quotes. | evidence only; kept |
| CommitWitnessSound | Search terms and history searches; the deleted 1451f96 doc is the only commit-monotonicity statement. The reviewer appended its own history searches. | evidence only; kept and extended |
| MembershipOrder | The quotes order entries by position, not by index. The reviewer added why guide :18 was not counted. | evidence only; kept and extended |
| OneOutstandingMembership | "Committed" is used in the cluster sense; 7f34793 is the only tie to the node's commit index; the commit index is volatile; no quote covers restart. The reviewer added why six quotes were not counted. | evidence only; kept and extended |

The model-internal blocks (TypeOK, MCTypeOK, NotReachLeader, NotReachCommitWitness, NotReachOutstandingMembership, TraceMatched) have no `note:` line.

The `clause witness-bookkeeping` line in CommitWitnessSound gives a model-internal reason ("observer state with no source counterpart"). It is a `clause` line, which by format carries a status and a reason, not a `note:` line, so it was left in place.
