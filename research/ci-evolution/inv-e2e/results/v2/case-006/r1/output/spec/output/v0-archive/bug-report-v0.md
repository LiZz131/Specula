# Bug report — exact-old etcd Raft V0

## Summary

- Scenarios tested: 5 (election, replication, quorum checking, local ReadIndex,
  forwarded ReadIndex)
- Model-checking bugs found: 0
- Standard configs: `MC.cfg`, `MC_complete_core.cfg`
- Target configs: `MC_hunt_s1_election.cfg` through
  `MC_hunt_s5_forwarded_read.cfg`

The expected invariant violations in `Reach_*.cfg` are deliberately negated
scenario flags and are non-vacuity witnesses, not bugs. The exact-old stale
pending ReadIndex map entry is a code-derived behavior documented in the
modeling brief and trace; it is not a model-checking finding and is therefore
not entered in `findings.json`.

## Not Reproduced

| Scenario/config | Coverage | Result |
|---|---|---|
| Complete small core / `MC_complete_core.cfg` | 109,936 generated; 26,255 distinct; depth 23; exhausted | No violation |
| Election / `MC_hunt_s1_election.cfg` | 71,848 generated; 18,550 distinct; depth 18; exhausted | No violation |
| Quorum / `MC_hunt_s3_quorum.cfg` | 25,861 generated; 4,912 distinct; depth 20; exhausted | No violation |
| Broad / `MC.cfg` | 2-minute outer bound; last report 1,633,425 generated / 426,837 distinct at depth 17 | No violation observed; limited coverage |
| Replication / `MC_hunt_s2_replication.cfg` | 20-second outer bound; periodic statistics preserved | No violation observed; limited coverage |
| Local ReadIndex / `MC_hunt_s4_readindex.cfg` | 20-second outer bound; periodic statistics preserved | No violation observed; limited coverage |
| Forwarded ReadIndex / `MC_hunt_s5_forwarded_read.cfg` | 20-second outer bound; periodic statistics preserved | No violation observed; limited coverage |

## Spec adjustments during convergence

The pre-Ready delivery counterexample was classified as a model/integration
ordering error (Case B) and corrected using the exact-old Node persist-before-
send contract. The corrected trace and model configurations were rerun. No
faithful safety property was removed or weakened to obtain a green result.
