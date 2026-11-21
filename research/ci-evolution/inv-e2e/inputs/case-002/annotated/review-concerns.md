# Concerns

## Sentences moved out of `note:` lines

**None.** I read every `note:` line in all 16 blocks. Each one describes the evidence search (what was searched, what was found or not found, why a source was not counted) or how a source relates to the intent. None describes the model's actions or helpers, whether the model matches the code, or what might be weaker, stronger, a proxy, wrong, vacuous or a false alarm. So nothing was moved. The annotated model had no reference to `concerns.md`, and the reviewed model has none either.

Notes I looked at most closely and decided to keep as evidence notes:

- **EpochHistoryConsistency:** "The startup check at QuorumPeer.java:1122 compares the last zxid's epoch with currentEpoch, not with acceptedEpoch." This describes the cited source and explains why that `impl` line does not state the intent's acceptedEpoch bound. It is about how the evidence relates to the intent and does not mention the model, so I kept it unchanged.
- **OneActiveLeaderPerEpoch:** the sentence about zookeeperInternals.md:278 describes a doc passage and how it limits the reading of :246. It is about the evidence.
- **PipelinePrefix:** the sentence on "fuzzy" snapshots (zookeeperAdmin.md:2589-2600) says what the quote supports. It is about the evidence.
- **NoIllegalRollback:** "the client guarantees ... are stated at service level, not per server" describes the cited docs. It is about the evidence.

## Reviewer observations about the model (not moved from notes; for the model owner)

These came up while checking that the intents describe the formulas. They are not part of any block.

- **ElectionSafety:** in `base.tla`, `WinElection` is enabled only when `leadersByEpoch[ep] = {}`, and it writes `{candidate}`. No other `Next` action changes `leadersByEpoch`. So in `Spec`/`MCSpec` the invariant holds by construction of that action. Only `Trace.tla` (`ObservedLeadersByEpoch`, which takes a union) can falsify it.
- **EpochHistoryConsistency:** the second conjunct bounds only `LastEpoch(durable[s])`, the epoch of the last fsynced entry, not every entry. This is why the intent was narrowed.
