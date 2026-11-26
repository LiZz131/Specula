# Bug Report — Apache ZooKeeper Zab exact-old prior

## Summary

- Scenarios tested: 4 scope scenarios across 5 retained implementation traces
- Bugs found: 0
- Canonical configs run: `base.cfg`, `MC.cfg`
- Canonical result: both bounded BFS runs naturally exhausted with zero queued
  states and no safety or temporal-property violation

## Not Reproduced

| Scenario | Config | States explored | Result |
|---|---|---:|---|
| Same-epoch active leader overlap | `MC.cfg` | 21,701,056 distinct | No violation in completed bound |
| Broadcast without completed sync | `MC.cfg` | 21,701,056 distinct | No violation in completed bound |
| Apply without quorum certificate | `MC.cfg` | 21,701,056 distinct | No violation in completed bound |
| Unmarked history rollback | `MC.cfg` | 21,701,056 distinct | No violation in completed bound |

The inherited broader timeout/open-frontier outputs are preserved but are not
counted as proof. Prior deliberately negated reachability invariants are
non-vacuity evidence, not implementation findings.
