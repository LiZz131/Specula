# Validation report — incremental update c780d355

(The exact-old V0 report is archived at `spec/output/v0-archive/validation-report-v0.md`.)

## Validation handoff (Part 2)

- **Source**: artifact `c780d355cfeae6ee6be52c50c1f0bd7d30c6657a` (update),
  instrumented copy `build/work-source` + `harness/patches/instrumentation.patch`.
- **Harness command**: `harness/run.sh` (setup, apply, six scenarios, fresh
  traces); `harness/validate.sh` (SANY + TLC replay of every fresh trace with
  `TraceMatched`, evidence oracles, mutated-trace controls);
  `harness/repro.sh` (reproduction/controls on update and baseline).
- **Harness provenance**: V0 patch reused unchanged (applied cleanly, no
  drift); v2 adds only update-local probes/fields/scenarios
  (`harness/INSTRUMENTATION.md`).
- **Fresh traces**: `traces/INVENTORY.md` (six traces, 174 records total).
  Prior scenarios `quorum_read`, `quorum_loss` were rerun on the new
  implementation; archived exact-old traces are superseded
  (`traces/v0-archive/`).
- **Final trace regression** (`spec/output/trace-validation-summary.log`): all
  six fresh traces replay fully (depth = records + 1) with `TraceMatched`
  checked, every V0 invariant, and the update properties
  `UpdPendingMatchesQueue`/`UpdReadStateOnlyAtLeader` (plus
  `UpdReadAckFresh`/`UpdReadIndexLinearizable` on the five traces without a
  stale acknowledgement).
- **Update coverage**: affected events observed in fresh traces —
  release/free (`HandleHeartbeatResponse`), re-registration
  (`ClientReadIndex`), forwarded request/response (`ForwardReadIndex`,
  `ClientReadIndex`→`HandleReadIndexRequest`, `HandleReadIndexResponse`),
  role-change reset (`CheckQuorum`, `Campaign`, `BecomeLeader`,
  `HandleVoteRequest`), and the high-risk interaction (stale acknowledgement
  after re-registration with a newer-term commit, `stale_ack_reuse`).
- **Non-vacuity**: replay of the fresh traces on the exact-old model fails at
  the release record and at the step-down record
  (`spec/evidence/old-model-replay/`); five mutated copies are rejected at the
  mutated record (`traces/mutants/MUTANTS.md`).
- **Gap**: with three servers the first peer acknowledgement completes every
  quorum, so captured `acks` lists are always empty at observation points;
  acknowledgement effects are validated through release, queue, pending and
  ReadState comparisons.
- **Semantic spec files changed by validation**: no behavioral change; the
  stale-ack scenario was extended with a Ready publication (harness-only) and
  traces were regenerated and revalidated.

## Model checking (Part 3)

Entry gate: the complete fresh trace suite passed before any campaign
(Validation handoff above). All TLC state directories were under
`/dev/shm/specula-e2e-case-006/` and removed after each run; logs are in
`spec/output/mc-*.log`, counterexamples in `spec/output/cex/` (decoded step
tables `*.steps.md`). Runner: `spec/run_tlc.sh` (TLC `stopAfter` budget plus
an outer `timeout`). Note: TLC prints "Model checking completed" when its
`stopAfter` budget ends; runs with a non-empty queue are classified below as
`LIMITED_COVERAGE`, not as exhausted.

### Campaign order and outcomes

1. **Standard convergence** — `MC.cfg` (V0 properties on the updated
   reference) exhausted its state space with no violation; `MC_complete_core.cfg`
   exhausted with numbers identical to V0 (that cfg has no read actions).
   No Case A/B repair was needed, so the trace/MC loop converged in one round.
2. **Full update check** — `Update_full.cfg` over the complete `MCNext`:
   BFS budget-limited at depth 21 without a violation; **simulation over the
   same complete `MCNext` violated `UpdReadAckFresh` from Init (47 states,
   forwarded-read variant)**. `Update_full_rest.cfg` (all other properties)
   found no violation within budget (BFS and simulation).
3. **Concrete focused** — `Update_focused.cfg` violated `UpdReadAckFresh`
   (19 states); `Update_focused_rest.cfg` found no other violation within
   budget (BFS and simulation).
4. **Open and discharge** — `Update_open.cfg` violated `UpdReadAckFresh`
   (19 states, no environment step involved); `Update_open_rest.cfg` checked
   the remaining properties and `EnvWithinRely` within budget.
   `Update_discharge.cfg` checked `DischargeContext` (omitted ClientProposal,
   Crash, Restart steps satisfy `EnvRely`) over the complete `MCSpec` without
   violation within budget; a negative control with a too-strong rely is
   violated at depth 5 (`spec/evidence/discharge-control/`), so the action
   property is live.
5. **Scenario hunts** — U2 `Update_hunt_stale_ack.cfg`: `UpdReadAckFresh`
   violated (21 states, BFS-shortest). U3 `Update_hunt_linearizable.cfg`: BFS
   (depth 27) and 30-minute simulation found no violation within budget (the
   consequence needs ~35 steps under persist-before-send); the
   **phase-guarded subset `Update_hunt_linearizable_directed.cfg` violated
   `UpdReadIndexLinearizable` (35 states)**. U4 `Update_hunt_forwarded.cfg`:
   `UpdReadAckFresh` violated (21 states, same mechanism via a deduplicated
   request's heartbeat); `Update_hunt_forwarded_rest.cfg` found no other
   violation within budget. Inherited V0 hunts s1-s5 reran on the updated
   reference without violation (s1, s3 exhausted; s2, s4, s5 budget-limited).
6. **Reachability canaries** — all update canaries (`HuntReadFreed`,
   `HuntReadReuse`, `HuntReuseServed`, `HuntStaleAck`,
   `HuntForwardedFreedRead`, `HuntReadLeaderSteppedDown`) and all V0 canaries
   (`HuntLeader`, `HuntCommit`, `HuntQuorumCheck`, `HuntReadyRead`,
   `HuntReadResponse`) were witnessed, so every update Scenario is reachable
   and no property is credited vacuously.
7. **Full-reference admission** — every focused/directed/simulation
   counterexample used for MC-1 replays step by step under the complete
   `MCNext` (`spec/admit/admit-*-under-MCNext.log`).
8. **Final full check** — no semantic repair followed the campaigns; the final
   trace regression (`harness/validate.sh`) was rerun on the final artifacts
   and passed; earlier MC results apply to the final model (base/MC unchanged
   since they ran; `Update.tla` only gained the `U3Next` hunt lens).

### Counterexample classification

All violations are **Case C** (real implementation behavior) for MC-1: the
spec follows the code paths (`read_only.go:52-109`, `raft.go:915-932`), the
property is backed by contract/test evidence (`spec/invariant-evidence.json`
E2/E3), and the same execution was produced by the real implementation
(`traces/stale_ack_reuse.ndjson`, `spec/output/repro.log`).

### Coverage limits

- Budget-limited runs are `LIMITED_COVERAGE`; no run is a proof.
- The inherited `MCView` excludes fault counters (V0 design). TLC therefore
  keeps one representative per abstract state regardless of remaining fault
  budget, which can hide counter-dependent continuations even in exhausted
  runs; this is why the full BFS did not reproduce the focused depth-19 path
  that the full `MCNext` admits.
- Bounds: 3 servers, `ReadContexts` = {ctx1}, MaxTerm ≤ 2, MaxLogLen ≤ 3,
  read/heartbeat/Ready/fault counters as in each cfg.

### Campaign table (generated from the logs by `spec/tools/summarize_mc.py`)

| Run | Config | Mode | Outcome | States | Depth | Time |
|---|---|---|---|---|---|---|
| hunt_v0_s1_election | `MC_hunt_s1_election.cfg` | bfs | no violation; state space exhausted | 71,848 gen / 18,550 distinct / 0 queued | 18 | 10s |
| hunt_v0_s2_replication | `MC_hunt_s2_replication.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 7,132,750 gen / 1,697,199 distinct / 970,719 queued | 17 | 10min 02s |
| hunt_v0_s3_quorum | `MC_hunt_s3_quorum.cfg` | bfs | no violation; state space exhausted | 25,861 gen / 4,912 distinct / 0 queued | 20 | 10s |
| hunt_v0_s4_readindex | `MC_hunt_s4_readindex.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 6,221,314 gen / 1,217,620 distinct / 824,871 queued | 19 | 10min 03s |
| hunt_v0_s5_forwarded_read | `MC_hunt_s5_forwarded_read.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 6,122,364 gen / 1,310,561 distinct / 708,637 queued | 22 | 10min 01s |
| mc_complete_core | `MC_complete_core.cfg` | bfs | no violation; state space exhausted | 109,936 gen / 26,255 distinct / 0 queued | 23 | 23s |
| mc_standard | `MC.cfg` | bfs | no violation; state space exhausted | 22,496,273 gen / 4,291,336 distinct / 0 queued | 31 | 13min 49s |
| reach_update_forwarded_freed | `Reach_update_forwarded_freed.cfg` | bfs | VIOLATION: Invariant HuntForwardedFreedRead is violated. | 4,500 gen / 1,406 distinct / 710 queued | 17 | 03s |
| reach_update_freed | `Reach_update_freed.cfg` | bfs | VIOLATION: Invariant HuntReadFreed is violated. | 3,203 gen / 1,075 distinct / 536 queued | 16 | 01s |
| reach_update_leader_stepdown | `Reach_update_leader_stepdown.cfg` | bfs | VIOLATION: Invariant HuntReadLeaderSteppedDown is violated. | 3,000 gen / 1,030 distinct / 469 queued | 16 | 04s |
| reach_update_reuse | `Reach_update_reuse.cfg` | bfs | VIOLATION: Invariant HuntReadReuse is violated. | 4,494 gen / 1,408 distinct / 707 queued | 17 | 04s |
| reach_update_reuse_served | `Reach_update_reuse_served.cfg` | bfs | VIOLATION: Invariant HuntReuseServed is violated. | 20,463 gen / 5,721 distinct / 2,929 queued | 18 | 07s |
| reach_update_stale_ack | `Reach_update_stale_ack.cfg` | bfs | VIOLATION: Invariant HuntStaleAck is violated. | 82,265 gen / 22,953 distinct / 11,610 queued | 21 | 15s |
| reach_v0_s1_leader | `Reach_s1_leader.cfg` | bfs | VIOLATION: Invariant HuntLeader is violated. | 1,750 gen / 651 distinct / 410 queued | 7 | 04s |
| reach_v0_s2_commit | `Reach_s2_commit.cfg` | bfs | VIOLATION: Invariant HuntCommit is violated. | 141,802 gen / 35,802 distinct / 17,176 queued | 12 | 19s |
| reach_v0_s3_quorum | `Reach_s3_quorum.cfg` | bfs | VIOLATION: Invariant HuntQuorumCheck is violated. | 180 gen / 72 distinct / 24 queued | 9 | 03s |
| reach_v0_s4_ready_read | `Reach_s4_ready_read.cfg` | bfs | VIOLATION: Invariant HuntReadyRead is violated. | 1,289,277 gen / 251,992 distinct / 157,355 queued | 17 | 02min 04s |
| reach_v0_s5_forwarded_read | `Reach_s5_forwarded_read.cfg` | bfs | VIOLATION: Invariant HuntReadResponse is violated. | 59,168 gen / 15,246 distinct / 7,951 queued | 16 | 12s |
| upd_discharge | `Update_discharge.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 20,304,646 gen / 4,909,615 distinct / 2,928,560 queued | 19 | 20min 03s |
| upd_focused | `Update_focused.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 7,687,404 gen / 1,751,697 distinct / 992,380 queued | 19 | 04min 27s |
| upd_focused_rest | `Update_focused_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 40,816,616 gen / 8,737,524 distinct / 4,908,095 queued | 23 | 20min 03s |
| upd_focused_rest_sim | `Update_focused_rest.cfg` | sim | no violation; LIMITED_COVERAGE (time budget) | 19,321,257 states; 145,543 traces | - | 20min 01s |
| upd_full | `Update_full.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 40,359,915 gen / 9,298,689 distinct / 5,440,409 queued | 21 | 20min 02s |
| upd_full_rest | `Update_full_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 31,314,432 gen / 7,522,045 distinct / 4,541,004 queued | 19 | 20min 02s |
| upd_full_rest_sim | `Update_full_rest.cfg` | sim | no violation; LIMITED_COVERAGE (time budget) | 17,636,381 states; 107,551 traces | - | 20min 01s |
| upd_full_sim | `Update_full.cfg` | sim | VIOLATION: Invariant UpdReadAckFresh is violated. | 3,129 states; 21 traces | - | 04s |
| upd_hunt_forwarded | `Update_hunt_forwarded.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 414,826 gen / 99,013 distinct / 57,679 queued | 21 | 32s |
| upd_hunt_forwarded_rest | `Update_hunt_forwarded_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 32,484,511 gen / 6,905,928 distinct / 4,136,422 queued | 27 | 20min 02s |
| upd_hunt_linearizable | `Update_hunt_linearizable.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 35,496,927 gen / 8,948,688 distinct / 4,150,285 queued | 27 | 20min 02s |
| upd_hunt_linearizable_directed | `Update_hunt_linearizable_directed.cfg` | bfs | VIOLATION: Invariant UpdReadIndexLinearizable is violated. | 6,483,193 gen / 1,363,514 distinct / 147,723 queued | 36 | 02min 53s |
| upd_hunt_linearizable_sim | `Update_hunt_linearizable.cfg` | sim | no violation; LIMITED_COVERAGE (time budget) | 54,550,274 states; 335,383 traces | - | 30min 01s |
| upd_hunt_stale_ack | `Update_hunt_stale_ack.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 76,816 gen / 21,691 distinct / 10,875 queued | 22 | 09s |
| upd_open | `Update_open.cfg` | bfs | VIOLATION: Invariant UpdReadAckFresh is violated. | 21,865,705 gen / 4,960,978 distinct / 2,861,236 queued | 19 | 19min 36s |
| upd_open_rest | `Update_open_rest.cfg` | bfs | no violation; LIMITED_COVERAGE (time budget) | 44,063,666 gen / 9,714,673 distinct / 5,549,063 queued | 20 | 20min 02s |
