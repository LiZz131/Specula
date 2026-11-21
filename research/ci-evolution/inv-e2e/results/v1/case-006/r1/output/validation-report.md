# Validation report — incremental V1 (`update` revision)

## Identity

- Source: artifact commit `c780d355cfeae6ee6be52c50c1f0bd7d30c6657a` (`update`);
  old control `7289d1c5e049933b90a9692bbf508714bee02fce` (`baseline`).
- Disposition: MODEL_CHANGE_REQUIRED (source delta) plus two reference repairs
  (readOnly reset; forwarded-read response handling). See `analysis-report.md`.
- Harness command: `harness/run.sh` (build+scenarios), `harness/validate.sh`
  (SANY + TLC replay). Logs: `spec/output/harness-run.log`,
  `spec/output/harness-run-old-control.log`, `spec/output/trace/`.

## Harness provenance

The V0 patch applied to the update tree without drift (no change in `raft.go`,
`node.go`). Rebased pieces: `apply.sh` (exports a commit of the artifact repo
instead of patching `/work/work-source` at a V0 commit id), `gopath.sh`
(reconstructed V0 overlay), two new probes (`ForwardReadIndex`,
`HandleReadIndexResponse`), read-message ctx capture, three update scenarios,
and a standalone reproduction test. Nothing was replaced.

## Fresh new-revision trace inventory (validation gate)

| Trace | Scenario | Records | SHA-256 | TLC replay | Distinct states |
|---|---|---|---|---|---|
| `traces/quorum_read.ndjson` | prior safe read (US1) | 28 | `327ff748…dda50c9` | PASS (`Trace.cfg`) | 29 |
| `traces/quorum_loss.ndjson` | prior quorum loss | 15 | `4adbdcdf…821af72f` | PASS (`Trace_quorum_loss.cfg`) | 16 |
| `traces/read_reuse.ndjson` | US1/US2/US3/US6 | 28 | `c5cf903c…f34b6` | PASS (`Trace_read_reuse.cfg`) | 29 |
| `traces/stale_read.ndjson` | US4 | 33 | `c8ac0818…f52f1` | PASS (`Trace_stale_read.cfg`) | 34 |
| `traces/read_stepdown.ndjson` | US5 | 35 | `c7526e34…db782` | PASS (`Trace_read_stepdown.cfg`) | 36 |

Every replay consumed all records, completed the `TraceMatched` temporal check,
and held `TraceCanProgress`, all V0 safety invariants, `PendingMatchesQueue`,
and `ReadQueueDistinct`; `quorum_read`, `quorum_loss`, and `read_stepdown` also
held `ReadDeliveryJustifiedFresh` and `ReadIndexFreshness`. No trace or spec
repair was needed during validation (the two reference repairs were made in
Generation from source reading and are confirmed by the sensitivity checks).

Archived traces: `traces/archive-v0/*.ndjson` are the immutable V0 traces of the
old revision — superseded (they encode the stale pending entry the update
removes). Fresh old-revision control traces: `traces/old-control/*.ndjson`.

## Trace fields are consumed (sensitivity)

| Model | Trace | First rejected record | Field |
|---|---|---|---|
| V0 (prior) | new `quorum_read` | 26 `HandleHeartbeatResponse` | pendingCount 0 vs stale 1 |
| V0 | new `read_stepdown` | 16 `CheckQuorum` step-down | readQueue/pendingCount cleared |
| V0 | new `read_reuse` | 14 `ForwardReadIndex` | event absent in V0 |
| V1 | old `quorum_read` | 26 | pendingCount 1 vs 0 |
| V1 | old `read_reuse` | 18 (forwarded release) | pendingCount |
| V1 | old `read_stepdown` | 33 | pendingCount |
| V1 minus reset repair | new `read_stepdown` | 16 | readQueue/pendingCount |

## Update coverage

| Action / effect | Fresh trace evidence | Compared by |
|---|---|---|
| `HandleHeartbeatResponse` release+delete (affected) | all read traces | `ValidateCorePost` pendingCount/readQueue/readCount |
| late ack for released ctx ignored | quorum_read 27, read_reuse 19 | same |
| re-enqueue same ctx (US2) | read_reuse 25, stale_read 31 | same |
| stale ack releases new instance (US3) | read_reuse 26, stale_read 32 | same + `ConsumeReady` |
| newer leader commit before reuse (US4) | stale_read 18-30 | commit/logTerms/role/term |
| reset discards pending read (US5) | read_stepdown 16 | readQueue/pendingCount |
| forwarded release consumed (US6) | read_reuse 14-20, 28 | follower readCount, `ConsumeReady` |

Gaps (not observed in fresh traces; covered by model checking only):
higher-term reset with non-empty readOnly via vote/append/heartbeat;
higher-term `HandleReadIndexResponse`; `BroadcastHeartbeat` and `ReadyAdvance`
(no probe, as in V0); crash/restart and message loss.

## Code observation (divergence evidence)

`TestSpeculaReproStaleReadAfterContextReuse`: update revision FAIL (read index 1
returned although index 3 was committed before the request;
`spec/output/repro/repro-new-update.log`); baseline revision PASS (second
request never served; `spec/output/repro/repro-old-baseline.log`).
`TestRaftFreesReadOnlyMem` passes on the update revision.

## Model checking (incremental campaign)

Order: standard `MC.cfg` round, full update check, concrete focused, open +
discharge, scenario hunts (inherited and update), simulation follow-ups, final
full checks on the final artifacts. Complete inventory (generated from the TLC
logs): `spec/output/mc/campaigns.md`.

| Campaign | Result |
|---|---|
| Standard `MC.cfg` (V1 suite, final artifacts) | EXHAUSTED, no violation: 22,496,273 generated / 4,291,336 distinct, depth 31 (`final_mc_standard.log`; identical before the ghost fix) |
| Full update `Update_full.cfg` over `MCSpec` | no violation within 30 min, LIMITED_COVERAGE (see campaigns.md); simulation follow-up `sim_update_full` found `ReadDeliveryJustifiedFresh` (MC-1, 44 states) |
| Concrete focused `Update_focused.cfg` | `ReadDeliveryJustifiedFresh` violated, 22 states (MC-1) |
| Concrete focused `Update_focused_reset.cfg` | `ReadDeliveryJustifiedFresh` violated, 21 states (MC-1, MsgBeat variant) |
| Open `Update_open.cfg` (EnvUpdate) | no violation, LIMITED_COVERAGE |
| Discharge `Update_discharge.cfg` | no violation of `DischargeContext`, LIMITED_COVERAGE; negative control refuted (non-vacuous) |
| US4 hunts | guided BFS `Update_hunt_us4_guided.cfg`: `ReadIndexFreshness` violated, 37 states (MC-1); unguided focused BFS and full-model simulation: no violation within budget |
| Inherited V0 hunts on V1 | s1, s3, complete-core EXHAUSTED; s2, s4, s5 LIMITED_COVERAGE; all without violation; simulation follow-ups without violation |
| Reachability canaries | all 5 inherited and 4 update canaries reached (US1 depth 17, US2 16, US3 18, US5 15) |

Repairs during model checking: one Case B (ghost correspondence of forwarded
responses, my V1 draft), fixed and followed by full trace regression (5/5 PASS)
and final-artifact reruns. No Case A. One Case C finding (MC-1).
