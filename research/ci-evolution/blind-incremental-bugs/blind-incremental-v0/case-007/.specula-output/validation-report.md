# Specula V0 validation report — case-007

## Outcome

The exact-old suite is internally consistent under its declared finite bounds.
All eight fresh real-code traces replay to completion against `Trace.tla`, and all
ordinary TLC runs complete with no invariant violation. The outcome is
`LIMITED_COVERAGE`, not proof, because the state spaces and trace scenarios are
finite and several error classes are not observed directly.

## Real implementation traces first

The runnable harness used existing neutral tests in `/work/work-source` with
disabled-by-default probes and a five-minute outer timeout per test. Every test
passed and every NDJSON line passed the harness JSON check.

| Trace | Lines | Principal observations | TLC distinct states |
|---|---:|---|---:|
| `append-success.ndjson` | 6 | queued stream requests and ordered success | 7 |
| `append-conflict.ndjson` | 5 | terminal stream conflict after queued intake | 6 |
| `append-higher.ndjson` | 3 | terminal stream higher vote | 4 |
| `partial-success.ndjson` | 1955 | repeated partial continuation with stable inflight identity | 2918 |
| `unreachable-backoff.ndjson` | 38 | unreachable classification and log backoff begin | 43 |
| `retry-rejoin.ndjson` | 133 | network failures, new work, and eventual success | 167 |
| `isolated-learner.ndjson` | 65 | per-target failure isolation and retry work | 83 |
| `snapshot-success.ndjson` | 13 | conflict-to-snapshot handoff, install, and log continuation | 17 |

The final trace logs are `spec/output/trace-*.log`; each ends with
`Model checking completed. No error has been found.` Trace replay includes weak
fairness only to require consumption of the finite log and its causally queued
internal core step. It does not assert protocol liveness.

## Ordinary bounded model checking

All correctness invariants were enabled in each ordinary configuration. Independent
planes were checked separately to avoid multiplying unrelated state dimensions:

| Configuration | Scope and bounds | Generated | Distinct | Depth | Result |
|---|---|---:|---:|---:|---|
| `MC.cfg` | log/core/session; one target, indexes `-1..1`, two attempts, one work/session input | 248058 | 80511 | 15 | no error |
| `MC_snapshot.cfg` | snapshot/session; one target, two attempts, one snapshot input | 56706 | 13071 | 12 | no error |
| `MC_stream.cfg` | one stream request over indexes `-1..1` | 46 | 11 | 3 | no error |

The preserved logs are `model-check-log-core.log`, `model-check-snapshot.log`, and
`model-check-stream.log`.

## Reachability and non-vacuity

Dedicated runs checked the negations of six witness predicates. Each expected TLC
counterexample reached the positive predicate for append attempt, partial reply,
backoff wait, session rollover, snapshot attempt, and terminal stream result. The
logs are `spec/output/reach-*.log`. These deliberate negated-witness violations are
reachability evidence, not findings.

## Mismatch classification and limits

All debugging mismatches were specification or replay-wrapper issues: missing
unchanged state, task-local counter reset, awaited-RPC/backoff atomicity, core work
range constraints, the default log-reversion assumption, and scheduling of the
unlogged core notification step. No faithful safety property was removed or
weakened to make a run green.

Direct trace coverage does not include timeout or remote transport errors, log
backoff expiry/reset, snapshot error/backoff, or captured core post-state for stale
session drops. The model abstracts full log IDs to indexes and excludes full-cluster
election/log safety, payload bytes, crash recovery, transport internals, and real
time. These are coverage limits, not implementation findings.

