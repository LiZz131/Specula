# Incremental CI report

Pre-Vote update modeled (MODEL_UPDATED); harness rebased and 18 fresh traces validated; model checking found one real defect (MC-1), reproduced on the updated implementation: a Pre-Vote round survives leader establishment and the new Leader re-elects itself, tripping the leader-vote assertion.

CI verdict: **FAIL**. Reproduced bugs: 1; other unresolved findings: 0; other dispositions: 1.

[Findings and evidence](confirmed-bugs.md) · [Severity](bug-severity.md)

## Validation limits

- All model checking is bounded (3 nodes, MaxTerm 2, <=2 elections, <=2 Pre-Vote rounds, <=1 crash, <=1 drop, <=5 messages); 30-minute BFS/simulation budgets did not exhaust the state space (LIMITED_COVERAGE).
- Traces are engine-level (real Engine methods, runtime command execution emulated by an explicit RuntimeDrain event); RaftCore tick guards, RPC dispatch, and the PreVoteResponse gate as executed in RaftCore are validated by source review, model checking, and the integration reproduction rather than trace replay.
- Open focused checks are provisional and budget-limited; the discharge obligation passed only within its BFS budget.
- Two prior-model defects were repaired (LogLE on absent logs; leader lease on establishment); prior state counts are not comparable, but with both repairs reverted and Pre-Vote disabled the suite reproduces the prior exhaustive MC.cfg graph exactly.
- The Level 3 timer-path reproduction slows save_vote through a test-storage hook (memstore only); the Level 1 reproduction uses only public APIs.
