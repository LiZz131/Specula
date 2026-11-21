# Specula V0 verification summary

## Result

- Baseline: immutable exact-old commit `955ebf13f9c4acf88240775db2b51832c9cbb6a9`.
- Trace validation: **LIMITED_COVERAGE**. All eight fresh implementation traces individually matched:
  each run consumed the complete NDJSON trace and satisfied the `TraceMatched` temporal property;
  this was real trace validation, not a parse-only check. The status remains limited because the
  finite scenario set bounds the implementation environment and schedules observed.
- Model checking: **LIMITED_COVERAGE**. TLC completed the configured finite state space without an
  invariant violation: 1,562,585 generated states, 286,148 distinct states, queue empty, depth 25.
- Source tests after instrumentation: 198 passed, 0 failed.

These results are a bounded pre-update prior. They are neither proof nor a claim about executions
outside the exact-old code, the captured scenarios, or the configured model bounds.

## Trace-first order and evidence

The harness first ran exact-old `Engine` calls in `/work/work-source` and wrote 20 fresh events to
eight nonempty NDJSON files. Those traces were validated before ordinary bounded model checking.
After the model/spec debugging loop, every trace was collected again and replayed against the final
`Trace.tla`:

| Trace | Events | Final TLC log |
|---|---:|---|
| election | 4 | `trace-election.log` |
| vote request | 2 | `trace-vote-request.log` |
| follower append | 2 | `trace-follower-append.log` |
| learner membership | 2 | `trace-learner-membership.log` |
| joint membership | 2 | `trace-joint-membership.log` |
| uniform membership | 2 | `trace-uniform-membership.log` |
| partial replication | 4 | `trace-partial-replication.log` |
| restart | 2 | `trace-restart.log` |

Each final log contains both `Finished checking temporal properties` and
`Model checking completed. No error has been found.` The validator checks all captured strong-state
fields, including votes and durability, roles, log IDs, commit/I/O indices, effective and committed
membership, candidate/granter state, leader progress, accepted index, and emitted command kinds.

## Model-check bounds

`MC.cfg` uses three servers, initial voters `{1,2}`, maximum term/index 2, and bounds of one election,
one append, one membership append, two acknowledgements, one crash, and one stale response. Canonical
node identities remove symmetric schedules. Twelve safety/type invariants were evaluated in every
one of the 286,148 reachable states.

All substantive action families were non-vacuous except `MCUniform`: the one-membership bound permits
the joint transition but not a subsequent joint-to-uniform transition. That exact-old transition is
instead exercised by the dedicated real `uniform-membership.ndjson` trace. This explicit gap is why
the model-check result remains `LIMITED_COVERAGE`.

## Mismatch classification during convergence

No mismatch was classified as an implementation defect. The preserved iteration logs document four
model-side corrections:

1. `model-check-iteration-01-invariant-mismatch.log` — **invariant mismatch**. The first
   `CandidateGrantSound` formulation assumed candidate state and retained leader state were mutually
   exclusive. Exact-old code permits both objects to coexist, so the invariant was restricted to
   the active `Leader` role.
2. `model-check-iteration-02-spec-abstraction.log` — **spec abstraction error**. The model counted a
   leader's newly appended local entry as matched before local log I/O. Self progress was changed to
   follow the real persisted/flushed boundary.
3. `model-check-iteration-03-spec-abstraction.log` — **spec abstraction error**. A generic peer
   acknowledgement could advance self progress before flush. Self acknowledgement was excluded;
   `FlushLog` now advances self match.
4. `model-check-iteration-04-spec-abstraction.log` — **spec abstraction error**. Restart retained
   volatile remote match progress even when recovered durable logs were shorter. Restart now rebuilds
   the whole progress row from recovered state.

The two later exploratory configurations were intentionally stopped when their queues continued to
grow; their logs are `model-check-iteration-05-expanded-bounds-interrupted.log` and
`model-check-iteration-06-bounds-interrupted.log`. They reported no violation before interruption and
are not counted as completed checks. The final bounded run is preserved in `model-check.log`.

## Reproducibility and isolation

- Harness entry point: `../../harness/run.sh` from this directory, or the absolute path under the
  suite root.
- Instrumentation patch: `../../harness/instrumentation.patch`; `git apply --check` succeeds against
  the immutable exact-old tree.
- Build and harness runs used the already-installed Rust/Cargo 1.95.0 toolchain explicitly. The
  environment's default toolchain update path was unavailable, so this is an environment limitation,
  not evidence about other compiler versions; the selected toolchain completed all 198 library tests.
- All build/test/TLC work used bounded outer `timeout` invocations.
- TLC state was placed below `/dev/shm/specula-v0-case-004/` and removed after the runs.
- The immutable `/work/source` tree remains at the baseline commit with a clean worktree.
