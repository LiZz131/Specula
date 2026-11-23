# case-004 evidence: one trigger predicate on all three arms, and two cfg-narrowing questions

Decision probes run with TLC on the exported final specs (`results/<arm>/case-004/r1/output/spec`). Each arm gets
`Probe004.tla` (`EXTENDS Update`; state predicates and action properties only, no new actions) and probe cfgs that
keep the arm's own constants, `SPECIFICATION`, `VIEW` and replace the checked properties with one probe. Shared
variables: `up`, `voteTerm`, `voteNode`, `voteCommitted`, `configs`, `learners`, `leader`; the panic flag is the
arm's own (`panicked` in v0/v2, `corePanic` in v1).

- `ProbeNoLearnerElect` (action): a step in which a node that is a learner, not a voter, of its effective membership
  starts an election (`voteNode' = n`, term up). MC-1 trigger (`raft_core.rs:1190-1202` has no voter guard).
- `ProbeNoAbsentElect` (action): same for a node that is neither voter nor learner (removed).
- `ProbeNoPanic`: the arm's RaftCore panic flag (MC-1 consequence, `candidate.rs:92`).
- `ProbeNoRemovedNode`: some live node's effective membership no longer contains a node.
- `ProbeAbsentElectInvisible` (v2 only): a removed node starts an election and v2's `ElectionByVoterOnly` still holds.
- `ProbeNoLeaderSelfElect` (action): a node holding a Leader object starts an election (transfer to itself).
- `ProbeLeaderVoteNotSuperseded`: v0's `LeaderVoteNotSuperseded` (its MC-2 state) on shared variables.

| Arm | Cfg | Built from | Result |
|---|---|---|---|
| v0 / v1 / v2 | `P-LE-MC` | own `MC.cfg` as is | violated, 10 / 11 / 12 states |
| v0 / v1 / v2 | `P-PN-MC` | own `MC.cfg` as is | violated, 12 / 12 / 15 states |
| v2 | `P-RM-MC` | own `MC.cfg` as is (`MembershipLimit = 1`) | timeout 15 min, depth 34, 14.2M distinct, no violation (no result; structurally unreachable: removal needs Joint + Uniform, `MC.tla:162-188`) |
| v2 | `P-RM-ML2` | same, `MembershipLimit = 2` | violated, 23 states |
| v2 | `P-AE-ML2` | same, `MembershipLimit = 2` | violated, 24 states (removed node 1 transfers to itself and elects) |
| v2 | `P-AEI-ML2` | same, `MembershipLimit = 2` | violated, 24 states (`ElectionByVoterOnly` still true after that step) |
| v1 | `P-LS-MC` | own `MC.cfg` as is (`TransferTargets = {2,3}`) | timeout 15 min, depth 23, 19.3M distinct, no violation (no result; structurally unreachable) |
| v1 | `P-LS-T123` / `P-LVNS-T123` | own `MC.cfg`, `TransferTargets = {1,2,3}` | violated, 9 / 9 states |
| v1 | `P-LVNS-U3` | own `Update_hunt_U3_voter.cfg` as is | violated, 9 states |
| v0 | `P-LVNS-MC` | own `MC.cfg` as is (positive control, v0's MC-2) | violated, 9 states |
| v2 | `P-LS-MC` / `P-LVNS-MC` | own `MC.cfg` as is | violated, 10 / 10 states |

Files: `<arm>/*.log` are the TLC outputs; `<arm>/*.steps.txt` list each counterexample step with the changed
variables (`cex_steps.py`). `./run.sh <arm> <cfg> [timeout]` reruns a probe.
