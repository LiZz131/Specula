# Validation changelog

## Round 1 — Trace validation

- [fix-spec] `HandleAppendEntries`: represented zero-entry Append messages so
  the exact-old leader commit broadcasts replay faithfully, in addition to the
  bounded one-entry append case.
- [fix-trace] State capture: encoded empty read queues as `[]` instead of JSON
  null so the sequence mapping is total.
- [pass] `quorum_read.ndjson`: all 28 records consumed; 29 distinct states.
- [pass] `quorum_loss.ndjson`: all 15 records consumed; 16 distinct states.
  `TraceMatched` and all enabled safety invariants held for both traces.

## Round 1 — Model checking

- [fix-config] Symmetry: changed MC constants from strings to model values so
  `Permutations(Server)` is valid. Trace constants remain exact Go strings.
- [fix-spec] Ready publication contract (Case B): gated ordinary message
  delivery on sender-side durable HardState/log. This removed an impossible
  pre-persistence crash/restart election counterexample without changing
  `ElectionSafety`.
- [fix-config] Disabled deadlock checking for counter-bounded terminal states;
  safety invariant checking remains enabled.

## Round 2 — Convergence and coverage

- [pass] Revalidated the final trace adapter after model changes.
- [pass] Exhausted `MC_complete_core.cfg`, `MC_hunt_s1_election.cfg`, and
  `MC_hunt_s3_quorum.cfg` without a neutral invariant violation.
- [coverage] Preserved timeout-bounded main, replication, and ReadIndex logs.
- [coverage] Split expected reachability violations into `Reach_*.cfg` and
  `reach-*.log`, separate from safety hunting results.

## Result

Trace validation passed for both collected executions. Bounded model checking
found zero model-checking bugs; overall coverage remains limited by explicit
state, action, environment, and timeout bounds.
