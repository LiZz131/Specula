# case-002 evidence: can each arm's model reach the COMMIT-after-NEWLEADER NPE?

Decision probes run with TLC on the exported final specs (`results/<arm>/case-002/r1/output/spec`). Each arm gets
`Probe002.tla` (`EXTENDS MC` for v1/v2, `EXTENDS Update` for v0 because its hunt cfgs use `Update`'s guidance
constraints; state predicates only, no new or changed actions) and probe cfgs that keep the arm's own constants,
`SPECIFICATION`, `SYMMETRY` and `CONSTRAINT` and replace the checked properties with one probe. Every constant
that differs from the source cfg is named in the cfg's first line and below.

## Probes

- `ProbeNoNPE` (all arms): a learner has handled NEWLEADER and sent its ACK, its `packetsNotCommitted` buffer is
  empty, and a COMMIT can be consumed now. The implementation then runs
  `pif = packetsNotCommitted.peekFirst(); if (pif.hdr...` (`Learner.java:645-646`) with `pif == null`.
  - v1: `syncJustified /\ nlAckSent /\ syncBuf = <<>> /\ ENABLED ReceiveSyncCommit(m)`;
  - v0: `syncStage = "nlAcked" /\ pnc = <<>> /\ Head(lq).type = "COMMIT"` (next packet of the stream);
  - v2: no action consumes a COMMIT during synchronization (`ReceiveCommit` requires `phase = "broadcast"`), so
    the probe is a state: a COMMIT in flight to a learner still in SYNCHRONIZATION that has sent its ACK, for an
    entry of its pre-NEWLEADER stream (`recovered`). `ProbeNoCommitWindow` drops the last conjunct.
- `ProbeOldSnap` (v0): the PipelinePrefix snapshot clause as it stood before v0's turn [302]
  (`snapshot ⊑ applied ∨ (phase = sync ∧ snapshot ⊑ recovered)`); its violation is v0's "Case A".
- `ProbeAdmittedSnapInLog` (v0): in states admitted by [302] but rejected by the old clause, the snapshot is a
  prefix of the forced log (`durable`).
- `Tr-OAL.cfg` (v0, v2): the shipped `Trace.cfg` with the trace-only `OneActiveLeaderPerEpoch` variant replaced
  by the original formula; replayed on every trace in `output/traces/*.ndjson` (`tr-summary.txt`).

## Results

| Arm | Cfg | Built from | Result |
|---|---|---|---|
| v1 | `P-npe-MC` | own `MC.cfg` as is | **NPE state reached, depth 38** (30.6M distinct, 23 min) |
| v1 | `P-npe-tgt` | `MC.cfg` with `MaxEpoch=1`, crash/drop/snapshot 0 (subset; the cfg of notes case-002.md §5.4) | reached, depth 38 (1.34M, 49 s) |
| v0 | `P-npe-ctl` | own `Update-hunt-npe.cfg` as is (positive control) | reached, depth 33 (1.52M); v0's `NoSyncException` fired at 34 = this state + the NPE step |
| v0 | `P-npe-MC` | own `MC.cfg` as is (unguided) | stopped by hand after 8.5 min at depth 26 (5.6M): no result |
| v2 | `P-window-MC` | own `MC.cfg` as is (`CanonicalDepthBound` 23, `TimeBudget`) | exhaustive to depth 23 (6.96M): not even the commit window |
| v2 | `P-window-tgt` | `MC.cfg` with `MaxEpoch=1`, faults 0, depth/time constraints dropped | commit window reached, depth 32 (a proposal made after broadcast: safe order) |
| v2 | `P-npe-tgt` | same as `P-window-tgt` | **exhaustive (2.74M, depth 49): NPE state not reachable** |
| v0 | `P-pp-old-MC` | own `MC.cfg` as is | old clause violated at depth 28 (10.9M, 15 min) = Case A of [298] |
| v0 | `P-pp-old-c1` | `MC.cfg` with drop/snapshot 0 (subset) | violated at depth 28 (10.1M) |
| v0 | `P-pp-old-c0` | `MC.cfg` with crash/drop/snapshot 0 (subset) | no violation; 20-min budget, depth 34 reached (every state to depth 33 expanded, 12.2M): Case A needs the crash |
| v0 | `P-pp-adm-c1` | same as `P-pp-old-c1` | no violation; 20-min budget, depth 29 reached (every state to depth 28 expanded, 13.0M, Case A itself is at depth 28) |
| v0 / v2 | `Tr-OAL` | shipped `Trace.cfg`, original `OneActiveLeaderPerEpoch` | only `update-diff-sync-consistency` violates (v0 state 118, v2 state 107), same implementation state in both: s1 LEADING in `election` phase with stale `acceptedEpoch = 2` while s2 leads epoch 2 in `broadcast` |

v1's own final BFS of `MC.cfg` (`results/v1/case-002/r1/output/spec/output/mc-Z1-MC-bfs.log`) reached depth 42
(42.7M distinct) before its time budget, so it expanded every state up to depth 41, including this depth-38
trigger state; nothing fired because the model has no error state and no property for it.

Files: `<arm>/*.log` are TLC outputs (the two `tr-Tr-OAL-*` logs are trimmed to the last two states);
`<arm>/*.steps.txt` list each counterexample step with its action, message changes and selected variables
(`cex_steps.py`; v0 actions show as `MCNext` because v0's `MCNext` is a conjunction, read the variable changes).
`./run.sh <arm> <cfg> [timeout]` reruns a probe; `JSON=<trace> MODULE=Trace ./run.sh <arm> Tr-OAL` reruns a replay.
