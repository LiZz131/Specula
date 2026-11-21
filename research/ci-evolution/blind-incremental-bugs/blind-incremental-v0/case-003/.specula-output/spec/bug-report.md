# Bug Report — CometBFT exact-old state execution and recovery

## Summary

- Scenarios tested: 3
- Model-checking bugs found: 0
- Configs run: `MC.cfg`, `MC_hunt_scenario1_params.cfg`,
  `MC_hunt_scenario2_durability.cfg`, `MC_hunt_scenario3_recovery.cfg`
- Coverage status: limited by the finite height/parameter/crash domain and the
  selected exact-old runtime scenarios; this is not a proof.

No known incident was targeted. No invariant violation survived validation,
and therefore no implementation defect is asserted by this V0 prior.

## Not Reproduced

| Scenario | Config | Search evidence | Result |
|---|---|---|---|
| Parameter validation and installation | `MC_hunt_scenario1_params.cfg` | BFS: 183 distinct states, diameter 18; simulation: 80,000,001 states, 800,000 traces, depth 100 | No violation within bounds |
| Ordered durable boundaries | `MC_hunt_scenario2_durability.cfg` | BFS: 1,719 distinct states, diameter 27 | No violation within bounds |
| Recovery height matrix | `MC_hunt_scenario3_recovery.cfg` | BFS: 3,892 distinct states, diameter 33 | No violation within bounds |
| Combined standard invariants | `MC.cfg` | BFS: 5,126 distinct states, diameter 33 | No violation within bounds |

The intentional violations in `output/reach-*.log` are reachability witnesses,
not bugs: each configuration negates a coverage marker solely to make TLC print
a concrete path to the corresponding behavior.

