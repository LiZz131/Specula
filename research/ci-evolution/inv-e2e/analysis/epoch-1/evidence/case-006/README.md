# case-006 evidence: one stale-read predicate on three models; r1 -> r2; ack-source helper drift

Decision probes run with TLC on the exported final specs (`results/<arm>/case-006/r1/output/spec`). Each arm gets
`Probe006.tla` (`EXTENDS Update`; state predicates only, no new or changed actions) and probe cfgs that keep the
source cfg's constants, `SPECIFICATION`, `CONSTRAINT`, `SYMMETRY` and `VIEW` and replace the checked properties.
No constant was changed in any probe cfg.

## Probes

- `ProbeNoStale` (all arms): a leader released a read whose index is below the largest index committed anywhere
  when the request was registered. Each arm stores that watermark at registration from the inherited
  `commitHistory` ghost: v0 `r.bound` (`readReleases`), v1 `r.floor` (`readReleases`), v2 `sr.gcommit`
  (`servedReads`); the three operators are the same definition.
- `ProbeNoStaleFresh` (v0): a stale release whose `freshAcks` (responses generated after the request was
  registered, v0's r2 notion) still reach a quorum -- i.e. a stale read that the relaxed r2 property would miss.
- Ack-source helper drift (all arms), for every in-flight `MsgReadIndexResp`: OLD source = the leader's current
  pending entry (old model `base.tla:481-487`); NEW source = a matching release record (each arm's
  `HandleReadIndexResponse`). `ProbeNewImpliesOld`: NEW has a quorum, OLD does not. `ProbeOldImpliesNew`: OLD has
  a quorum, NEW does not. `ProbeNewAlwaysHolds`: NEW lacks a quorum.

## Results

| Arm | Cfg | Built from | Result |
|---|---|---|---|
| v0 | `P-stale-ctl2` | own `MC_hunt_s6_linearizable_guided_v2.cfg` (the cfg of v0's own 37-state finding) | stale read reached, 37 states (4.2M distinct, 7 min) |
| v0 | `P-stale-ctl-noview` | own `MC_hunt_s6_linearizable_guided_noview.cfg` | 30 min, depth 39, 12.6M distinct: no result |
| v1 | `P-stale-guided` | own `Update_hunt_us4_guided.cfg` | reached, 35 states (2.9M distinct) |
| v2 | `P-stale-directed` | own `Update_hunt_linearizable_directed.cfg` | reached, 36 states (1.6M distinct) |
| v1 | `P-stale-MC` | own `MC.cfg` (`MaxReadLimit = 1`) | **exhaustive, not reachable** (4,291,336 distinct, depth 31) |
| v2 | `P-stale-MC` | own `MC.cfg` (`MaxReadLimit = 1`) | **exhaustive, not reachable** (4,291,336 distinct, depth 31) |
| v0 | `P-stalefresh-ctl` | same as `P-stale-ctl2` | **exhaustive, not reachable** (10,144,436 distinct, depth 50) |
| v0/v1/v2 | `P-hd-newold` | inherited `MC_hunt_s5_forwarded_read.cfg` (identical in the three arms) | violated in each arm at 16 states: a plain forwarded read; the leader already deleted its pending entry, so the OLD source yields `{}` |
| v0/v1/v2 | `P-hd-oldnew` | same | no violation within the 20-minute budget (not exhaustive), see below |

`P-hd-oldnew` (20-minute budget each):

| Arm | Result |
|---|---|
| v0 | no violation; stopped at depth 27 (every state to depth 26 expanded, 13.3M distinct) |
| v1 | no violation; stopped at depth 27 (14.3M distinct) |
| v2 | no violation; stopped at depth 26 (every state to depth 25 expanded, 14.0M distinct) |

Files: `<arm>/*.log` TLC outputs; `<arm>/*.steps.txt` counterexample steps (`cex_steps.py`; actions show as
`MCNext`/`U3Next` because those are conjunctions, read the message and variable changes).
`./run.sh <arm> <cfg> [timeout]` reruns a probe.
