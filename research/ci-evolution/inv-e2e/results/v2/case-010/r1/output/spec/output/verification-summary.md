# Verification summary — case-010 incremental (baseline f8533cd -> update b16ba71)

## Disposition

- Chapter 1: **MODEL_CHANGE_REQUIRED** (reported as MODEL_UPDATED).
- Trace validation: **PASSED** for the complete fresh new-version suite (4 scenario traces, all base + update invariants, `TraceMatched`), after two repair rounds (`spec/changelog.md`). The reproduction and old-control traces conform fully with invariants disabled, and show the expected violations with them enabled.
- Model checking: all applicable campaigns executed; bounded and time-limited, so results are **LIMITED_COVERAGE**. The only exhaustive run is `MC.cfg` (MCCoreNext, which excludes crashes, exits, and snapshots).
- Findings: **MC-1** (REPRODUCED on the real updated and old implementation; pre-existing sibling the update does not cover), **MC-2** (update-introduced; mechanism observed in real traces; log-gap consequence model-only). The update's own target (SNAP abort) is fixed: no violation in the SNAP-only view for the new code within bounds, violation for the old code, and the diff's test passes on new and fails on old.

## Bounds

3 participants; `MaxEpoch` 2 (full/standard) or 1 (focused); `MaxTxn` 1 or 2; at most 2 learner exits, 1 crash, 1 periodic snapshot, 2 election rounds (MC counters); TLC per-run limit 20-30 min (`-Dtlc2.TLC.stopAfter`) plus an outer `timeout`; state under `/dev/shm/specula-e2e-case-010/` (removed after each run). Logs: `spec/output/mc/`; command per run: `spec/run_tlc.sh <module> <cfg> <name> <minutes> <workers> [sim-depth]`; index with UTC start/end/rc: `spec/output/mc/campaign-index.txt`.

## Campaign results (round 2, final model)

| Run | Mode | Result | Distinct states | Depth / traces | Queue left | Wall |
|---|---|---|---:|---|---:|---|
| MC-standard | BFS | no violation | 344442 | 53 | 0 | 01min 55s |
| update-full | BFS | VIOLATION UpdIdleDbBackedByDisk | 10125272 | 38 | 3166386 | 25min 49s |
| update-focused-new | BFS | VIOLATION OrderedHistories | 725748 | 35 | 228277 | 01min 46s |
| update-focused-txn1 | BFS | VIOLATION UpdIdleDbBackedByDisk | 696003 | 38 | 154901 | 02min 05s |
| update-focused-old | BFS | VIOLATION UpdIdleDbBackedByDisk | 1705036 | 37 | 494923 | 03min 45s |
| update-snapfix-new | BFS | no violation | 11674311 | 44 | 2828500 | 30min 03s |
| update-snapfix-old | BFS | VIOLATION UpdIdleDbBackedByDisk | 1662334 | 37 | 465410 | 04min 13s |
| update-leak-new | BFS | VIOLATION OrderedHistories | 267840 | 35 | 78819 | 53s |
| update-leak-old | BFS | VIOLATION OrderedHistories | 2767843 | 42 | 692859 | 07min 00s |
| e2e-trunc-new | BFS | no violation | 13368016 | 45 | 3346902 | 30min 02s |
| e2e-snap-old | BFS | no violation | 12916748 | 44 | 3170174 | 30min 03s |
| e2e-snap-new | BFS | no violation | 13008887 | 45 | 3133158 | 30min 03s |
| sim-e2e-trunc-new | simulation d<=100 | no violation | 24811910 generated | 49501 traces | - | 20min 01s |
| sim-e2e-snap-old | simulation d<=100 | no violation | 24732397 generated | 49378 traces | - | 20min 01s |
| sim-e2e-snap-new | simulation d<=100 | no violation | 25108172 generated | 50146 traces | - | 20min 01s |

Reading: `update-full` is the complete reference `MCNext` with the update properties, so MC-1 is not a focused-only artifact. `update-focused-old`/`update-snapfix-old` are old-code controls (the update's target bug). `update-leak-old` reaches a pre-existing pre-UPTODATE variant of the leak (see bug report MC-2 attribution). The end-to-end views (`e2e-*`, precursor invariant disabled) did not reach the log-gap depth (about 48) within 30 minutes of BFS or 20 minutes of depth-100 simulation; the end-to-end gap is evidenced by the real traces instead (`trace-e2e-repro-trunc-abort-new.log` state 95; `trace-e2e-diff-sync-after-snap-oldcontrol.log` state 202).

## Reachability canaries and inherited hunts (expected sentinel violations)

| Run | Mode | Result | Distinct states | Depth / traces | Queue left | Wall |
|---|---|---|---:|---|---:|---|
| canary-leak | BFS | VIOLATION UpdLeakUnreachable | 53748 | 23 | 9289 | 12s |
| canary-rejoin | BFS | VIOLATION UpdRejoinUnreachable | 50412 | 23 | 7968 | 10s |
| canary-snap-abort | BFS | VIOLATION UpdSnapAbortUnreachable | 15006 | 17 | 4328 | 04s |
| canary-snap-clear | BFS | VIOLATION UpdSnapClearUnreachable | 15006 | 17 | 4328 | 03s |
| canary-trunc-abort | BFS | VIOLATION UpdTruncAbortUnreachable | 4384102 | 37 | 1038955 | 09min 06s |
| hunt-apply | BFS | VIOLATION ApplyUnreachable | 448 | 30 | 11 | 01s |
| hunt-commit | BFS | VIOLATION CommitUnreachable | 432 | 29 | 18 | 01s |
| hunt-election | BFS | VIOLATION ElectionUnreachable | 17 | 4 | 8 | 01s |
| hunt-recovery | BFS | VIOLATION RecoveryUnreachable | 169 | 22 | 18 | 01s |
| hunt-snapshot | BFS | VIOLATION SnapshotUnreachable | 227 | 22 | 26 | 01s |
| hunt-sync | BFS | VIOLATION SyncUnreachable | 30701 | 19 | 7002 | 10s |

## Open focus and discharge

| Run | Mode | Result | Distinct states | Depth / traces | Queue left | Wall |
|---|---|---|---:|---|---:|---|
| update-open | BFS | no violation | 9926799 | 27 | 1965612 | 20min 01s |
| update-discharge | BFS | no violation | 13122258 | 38 | 4011658 | 20min 02s |

`OpenUpdateNext` = focused Actions plus `EnvUpdate`, a rely that may change only periodic-snapshot bookkeeping and preserves every update-visible variable. `DischargeContext` checks over the complete `MCNext` that every omitted context step (`MCBeginSnapshot`/`MCFinishSnapshot`) satisfies `EnvUpdate`. Both runs: no violation within 20 minutes (LIMITED_COVERAGE). The open run reached depth 27 only, because the rely multiplies branching, so it does not reach the depth-38 MC-1 path; that path is covered by the concrete focused and full runs. Leader crash/restart and global election rounds are outside the focused views by design and are covered by `update-full` (`MCNext`).


## Trace validation

See `spec/validation-handoff.md` (inventory, per-trace results, coverage, non-vacuity controls).

## Process hygiene

No TLC, Maven, or ZooKeeper process was left running. The state directories below `/dev/shm/specula-e2e-case-010/` were deleted after each run. Round-1 results invalidated by the round-2 repair are archived in `spec/output/mc/provisional-r1/`. The `specula` CLI is not installed in this environment, so `specula ci-result` was not run; `spec/final-result.json` was written by hand.
