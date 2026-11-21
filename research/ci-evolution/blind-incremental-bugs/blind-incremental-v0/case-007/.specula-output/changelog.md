# Validation changelog

## Round 0 — source-derived prior

- Performed code-only structural and deep analysis of the exact-old tree.
- Froze Category A event/state mappings and generated base, model-checking, and
  trace-replay modules.
- Confirmed parser-clean modules and a 311-test pristine library baseline.

## Round 1 — implementation trace collection

- Added disabled-by-default probes only to `/work/work-source`.
- Ran eight neutral existing scenarios and retained nonempty NDJSON plus harness
  logs.
- Preserved the complete instrumentation diff relative to the neutral baseline.

## Round 2 — trace replay

- Classified the first replay issue as a spec omission: `CoreHandleProgress` did
  not declare `coreSession` unchanged.
- Reset task-local observation counters on worker spawn to match new task objects.
- Classified core-hook ordering as a trace issue and replaced the racy proposed hook
  with an exact unlogged core transition, eagerly linearized after its causal
  response event.
- Added weak fairness only for finite trace consumption. All eight final replays
  completed with no error.

## Round 3 — ordinary model checking

- Constrained event receipt during an awaited RPC and sends during backoff waits,
  matching the worker's sequential control flow.
- Required core-reserved log work to start at or above known worker/core matching.
- Added `AllowLogReversion` and checked the exact-old default `FALSE`; the enabled
  branch resets matching on a below-boundary conflict.
- Kept the physical sent endpoint separate from the logical reserved endpoint so a
  short read retains the full remainder with the same inflight ID.
- Split independent log/core, snapshot, and stream planes into complete bounded
  runs after a combined run demonstrated an unnecessary Cartesian explosion.
- All ordinary runs completed with all invariants enabled and no error.

No implementation defect was identified. No candidate/fixed revision, history,
issue, or upstream behavioral source was inspected.

