# Model observations moved out of `note:` lines

**None were moved.**

I read every `note:` line in `/work/spec-annotated/` against rule 5. None describes how the model's actions or helpers behave or whether the model matches the code. None calls the formula weaker, stronger, a proxy, vacuous or a false alarm, and none says what might be unmodelled or wrong. No block mentioned `concerns.md`, so no reference had to be removed.

| Property | note checked | sentences moved |
|---|---|---|
| ActiveLeaderUniqueness | search of docs and Leader.java history; passages not counted | 0 |
| AcceptedEpochGECurrentEpoch | no inequality stated; startup check impl-only; history searches | 0 |
| OrderedHistories | clause support; warn-only gap checks counted as impl | 0 |
| CommittedPrefixAgreement | delivery → commit reading of the total-order guarantee | 0 |
| NormalAckHasDurabilityEvidence | class comment not counted; history search | 0 |
| ApplyHasCommitCertificate | zookeeperAdmin.md logging passage not counted | 0 |
| SyncEntryJustified | history searches for ZabState; no LOOKING rule found | 0 |
| SnapshotPublishedValid | only non-impl source is the data-directory text; history search | 0 |
| MonotoneUnlessRecovery | history searches for truncation and snapshot | 0 |

The model-internal blocks (TypeOK, MCTypeOK, the six `*Unreachable` canaries, TraceMatched) have no `note:` line.

The notes I extended during review stay within the evidence-only rule. They say what was searched, what was found but not counted and why, and how the remaining evidence relates to the intent. They add no statement about the model.
