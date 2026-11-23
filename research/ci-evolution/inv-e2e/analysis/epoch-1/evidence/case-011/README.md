# case-011 evidence: can each arm's model reach bugs B and C?

Decision probes run with TLC on the exported final specs (`results/<arm>/case-011/r1/output/spec`). Each arm gets
`Probe011.tla` (`EXTENDS MC`; state predicates only, no new actions) and probe cfgs that keep the arm's own
constants, `SPECIFICATION`, `CONSTRAINT` and `VIEW` and replace the checked properties with one probe.

- `ProbeNoB`: a granted Pre-Vote response that matches the current round's probe, from a node outside the round's
  frozen quorum set, can be delivered. The implementation then calls `Candidate::grant_by` and panics
  (`proposer/candidate.rs:107`).
- `ProbeNoC`: a node that is no longer a voter of its effective membership can deliver a Pre-Vote response that
  raises its term (Pre-Vote quorum -> `elect()` without a voter check, `engine_impl.rs:535-539`).

| Arm | Cfg | Built from | Result |
|---|---|---|---|
| v1 | `P-B-tgt` | own `MC.cfg`, crash/drop 0, elections 1 (a subset of `MC.cfg`) | B reached, depth 18 |
| v1 | `P-B-MC` | own `MC.cfg` as is | no result in 20 min (depth 16) |
| v0 | `P-B-tgt` | own `MC.cfg`, crash/drop 0, `MaxElectionCount = 2` | not reached in 30 min (depth 20, 28M states) |
| v0 | `P-B-tgt3` | same with `MaxElectionCount = 3` | B reached, depth 17 |
| v0 | `P-B-MC` | own `MC.cfg` as is | no result in 20 min |
| v2 | `P-B-ctl-op` | own `MC_hunt_U4c_prevote_panic_operator.cfg` (positive control) | B reached, depth 16 |
| v2 | `P-B-ctl` | own `MC_hunt_U4_prevote_stale_round.cfg` (timer rounds) | no result in 20 min; v2 narrowed timer rounds |
| v1 | `P-C-asrun-membership` | own `MC-membership.cfg` as is | C reached, 12 states |
| v2 | `P-C-asrun-membership` | own `MC-membership.cfg` as is | C reached, 11 states |
| v1 / v2 | `P-C-tgt` | one initial voter, elections 1, membership 2 | C reached |
| v1 / v2 | `P-C-MC` / `P-C-Update` | own main cfg as is | no result in 20 min |
| v0 | `P-C-ctl` | own `MC_hunt_prevote_membership.cfg` (positive control) | C reached, depth 13 |

In v0 every election-type action (tick elect, external elect, external pre-elect, transfer) consumes the same
`MaxElectionCount`, and no node starts as leader; B needs a leader (for the membership change) plus two Pre-Vote
rounds. Every v0 cfg that allows membership changes has `MaxElectionCount <= 2`.

Files: `<arm>/*.log` are the TLC outputs; `<arm>/*.steps.txt` list each counterexample step with its action,
message changes and the Pre-Vote variables (`cex_steps.py`). `./run.sh <arm> <cfg> [timeout]` reruns a probe.
