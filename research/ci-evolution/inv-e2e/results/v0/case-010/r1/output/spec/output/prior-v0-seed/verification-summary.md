# Specula V0 verification summary

## Disposition

- Trace validation: **PASSED** for both fresh implementation traces.
- Ordinary model checking: **LIMITED_COVERAGE**. No checked-property violation was reported before the required ten-minute timeout, but the state graph was not exhausted.
- Implementation findings: none. Preserved failures were classified as invocation, invariant-shape, or spec-transition mismatches in `debug-classification.md`.

These results are evidence for the immutable exact-old prior only. They are neither proof nor an incremental/new-revision result.

## Inputs and build

- Pristine and working baselines: neutral commit `6250c9811a44ed94c825bb5a7cb80fd7b4b883a3`.
- Pristine status after all work: clean; no source file under `/work/source` was modified.
- Baseline reactor package: success (`baseline-build.log`).
- Instrumented build and both harness invocations: success; one test, zero failures/errors/skips in each harness log.
- Available runtime: OpenJDK 21; the exact-old Maven build targets Java 8 bytecode and succeeded. No behavioral dependency came from outside `/work`.

## Trace validation

| Trace | Real scenario | Events | TLC result | Non-vacuity |
|---|---|---:|---|---|
| `traces/election-ordered.ndjson` | election, sync, create, setData, orderly shutdown | 76 | no error; 77/77 distinct states exhausted, depth 77 | `TraceMatched` required and satisfied |
| `traces/restart-catchup.ndjson` | create, full restart/re-election, lagging follower, live-quorum setData, follower DIFF catch-up | 131 | no error; 132/132 distinct states exhausted, depth 132 | `TraceMatched` required and satisfied |

Across both files, all 207 NDJSON lines have `tag="trace"` and a populated event name, node, and common state. The inventory includes 10 election completions, 9 accepted-epoch writes, 10 current-epoch writes, 7 learner sync completions, 4 proposals, 12 queue and 12 flush observations, 8 normal ACKs, 4 global commits, 8 follower commits, 12 applies, 3 begun/published snapshots, and 10 recovery loads. Every emitted event name has a consuming `TraceNext` case.

## Ordinary TLC exploration

`MC.cfg` fixes three participants, `MaxEpoch=2`, `MaxTxn=1`, two election rounds including the initial round, at most one crash, and at most one snapshot. It checks:

- `MCTypeOK`
- `ActiveLeaderUniqueness`
- `AcceptedEpochGECurrentEpoch`
- `OrderedHistories`
- `CommittedPrefixAgreement`
- `NormalAckHasDurabilityEvidence`
- `ApplyHasCommitCertificate`
- `SyncEntryJustified`
- `SnapshotPublishedValid`
- temporal action property `MonotoneUnlessRecovery`

The final breadth-first run used four workers and state under `/dev/shm/specula-v0-case-010/`. At the last progress record it had generated 87,677,294 transitions, found 12,585,282 distinct states, reached depth 32, and retained 4,142,500 states on the frontier. The outer `timeout 10m` returned 124. TLC reported no checked-property violation before termination; because the frontier was nonempty, the result is not a pass/proof.

`MC-wide.cfg` preserves the wider two-transaction bound. Its intermediate exploration logs are retained, but it is not used to claim greater coverage.

## Reachability and non-vacuity

Each hunt intentionally checks a false `*Unreachable` sentinel; the expected invariant counterexample is positive reachability evidence, not a safety failure.

| Witness | Expected sentinel violation | Depth | Distinct states at discovery |
|---|---|---:|---:|
| election completion | `ElectionUnreachable` | 4 | 72 |
| epoch formation plus learner sync completion | `SyncUnreachable` | 16 | 135,537 |
| durability-backed quorum commit | `CommitUnreachable` | 27 | 1,126 |
| apply after certified commit | `ApplyUnreachable` | 28 | 1,174 |
| begun and published snapshot | `SnapshotUnreachable` | 3 | 3 |
| crash then database reload | `RecoveryUnreachable` | 3 | 40 |

The canonical commit/apply hunts remove unrelated fault/snapshot branches but call the same base and MC transition operators as ordinary checking. The real traces independently reach two ordered transactions and restart/catch-up behavior.

## Cleanup

All TLC state directories below `/dev/shm/specula-v0-case-010/` were deleted after logs were preserved. No TLC, Maven test, ZooKeeper quorum, or harness process was left running.

