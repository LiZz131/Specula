# Validation repair summary

- Required order: five real trace-validation runs completed before canonical
  base and MC BFS.
- Retained trace results: follower DIFF 15/16 records/states; both follower SNAP
  traces 16/17 each; leader abandonment/restart/recovery 265/266; quorum
  startup/mutation/shutdown 71/72. Every run exited zero, satisfied
  `TraceMatched`, completed naturally, and left zero states queued.
- Canonical base: 52,034,534 generated, 6,354,157 distinct, depth 23, zero states
  queued, no violation.
- Canonical MC: 171,870,841 generated, 21,701,056 distinct, depth 23, zero states
  queued, no violation.
- The inherited broader timeout/open-frontier runs remain in `spec/output/` but
  are classified only as limited evidence in `spec/verification-suite-manifest.json`.
- SANY passed for base, MC, and Trace; the instrumentation patch applies cleanly
  to `/work/source` in dry-run mode.
- A negative replay changed the `AcceptedEpochPersisted` post-state from epoch 1
  to 2 without changing the event projection; `TraceMatched` rejected it with
  exit 13, demonstrating that common post-state validation is not trace-fed.
- Exact commands, timestamps, exit codes, logs, trace digests, field/event
  coverage, and cleanup status are recorded under `spec/output/repair-suite/`.
- Overall disposition: `COMPLETED_WITH_LIMITED_COVERAGE`; the limitation is the
  explicit finite model bound, not an open TLC frontier. No finding was produced.
