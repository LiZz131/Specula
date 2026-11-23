# case-012 evidence: can each arm's model reach MC-1 (joint entry committed without a joint quorum)?

Decision probes run with TLC on the exported final specs (`results/<arm>/case-012/r1/output/spec`). Each arm gets
`Probe012.tla` (`EXTENDS Update`, which extends `MC`; state predicates and one action property only, no new
actions) and probe cfgs that keep the arm's own constants, `INIT`/`NEXT`, `CONSTRAINT`, `VIEW` (and `SYMMETRY`
where the arm had it) and replace the checked properties with one probe. The probe uses only variables shared by
all three arms: `role`, `committed`, `lastLog`, `logTerm`, `effectiveConfig`, `effectiveMembershipIndex`.

- `ProbeNoJointOvercommit` (state): no leader whose effective membership is joint has committed the joint entry
  (or later) while the nodes that actually hold that index in their log are not a majority of every group.
  Holders come from the logs, not from `matchedIndex`/VecProgress, so the oracle is independent of the mechanism.
- `ProbeCommitHasQuorum` (action): whenever a leader's commit index advances, its holders are a quorum of the
  effective membership before or after the step.
- `ProbeNoJointCommit` (frame canary): no leader in a joint membership has committed the joint entry at all.

| Arm | Cfg | Built from | Result |
|---|---|---|---|
| v0 | `P-J-u1` | own `Update_hunt_u1_consequence.cfg` as is (the cfg that found MC-1) | violated, 11 states (31,126 distinct) |
| v0 | `P-A-u1` | same, action property | violated, 11 states |
| v0 | `P-J-full` | own `Update_full.cfg` as is | violated, 11 states (953,389 distinct) |
| v0 | `P-J-u1-sym` | `P-J-u1` + `SYMMETRY Permutations(Server)` | violated, 12 states |
| v1 | `P-J-full` | own `Update_full.cfg` as is (= constants of `Update_full_cws.cfg`, the MC-1 cfg) | violated, 11 states (88,597 distinct) |
| v1 | `P-J-full-sym` | `P-J-full` + `SYMMETRY Permutations(Server)` | violated, 11 states |
| v2 | `P-F-full` | own `Update_full.cfg` as is, frame canary | violated (frame reachable), 9 states |
| v2 | `P-J-full` | own `Update_full.cfg` as is (with SYMMETRY) | no violation in 30 min (timeout): depth 18, 31.6M distinct states, queue 15M — no result, but every behavior up to depth 17 was covered (v0/v1 hit at 11–12) |
| v2 | `P-J-u1eq` | own `Update_full.cfg` with the budget the v0/v1 counterexample needs (MaxTerm 1, 1 election, 0 crash, 0 loss), no SYMMETRY | two 30-min BFS runs (`P-J-u1eq.run1-killed.log`, `P-J-u1eq.part1.log`): no violation, depth 26, 25.6M distinct, queue shrinking (1.4M) but not finished — no result; every behavior up to depth 25 covered. A checkpoint-recovery continuation (`part2`) was stopped by hand. |

v2 cannot represent MC-1: leader commit is `GreatestQuorumValue(progressConfig, rows)` (`base.tla:169-178`,
used at `:248-250`), an order-free set function whose result is by definition backed by a quorum of rows; the model
has no vector-order state (`UpgradeRow`, `:184-189`, copies values only).

Python (lightweight action check):
- `vecprogress_diff.py [steps] [maxval]`: line-by-line port of `progress/mod.rs:80-232` (VecProgress) and the joint
  quorum set, compared with v2's `GreatestQuorumValue` over all monotone update sequences; also replays the TLC
  counterexample. Output: `vecprogress_diff.out` (first divergence `(1,1),(3,1),(3,2),(2,2)` on `[{1,2,3},{1,2}]`).
- `vecprogress_diff.py --conform <ndjson>...`: replays the arms' recorded real `ProgressUpdate` events on the port.
  Output: `vecprogress_conform.out` (116 events match; 3 mismatches in v2 raw traces where LogIds are serialized as
  index only; two mutated traces rejected).

Files: `<arm>/*.log` are the TLC outputs; `<arm>/*.steps.txt` list each counterexample step with message changes
and the changed variables (`cex_steps.py`). `./run.sh <arm> <cfg> [timeout]` reruns a probe.
