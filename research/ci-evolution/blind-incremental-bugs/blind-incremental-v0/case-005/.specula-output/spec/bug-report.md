# Bug Report — ZooKeeper Zab exact-old V0

## Summary

- Scenarios trace-validated: 5 retained executions of the neutral old-source
  startup, election, mutation, follower synchronization, shutdown, restart,
  recovery, and post-recovery mutation scenario
- Model-checking findings: 0
- Canonical configs run: `base.cfg`, `MC.cfg`
- Hunting configs run: none; this task is a validation back-edge, not an
  incident hunt

No exact-old implementation bug was established. The deterministic replay
failures were trace numeric-representation, marker-scheduling, and
specification-fidelity defects. The repairs changed no production behavior
outside disabled-by-default instrumentation.

## Not Reproduced

| Scenario | Config | Distinct states | Result |
|---|---|---:|---|
| Fault-free election/sync/broadcast | `base.cfg` | 779,347 | Natural bounded BFS completion; no violation |
| Bounded crash/restart | `MC.cfg` | 404 | Natural bounded BFS completion; no violation |
| Broader fault/client exploration | retained repair logs | open frontier | Limited evidence only; not a proof |

These are bounded results, not an unbounded correctness proof.
