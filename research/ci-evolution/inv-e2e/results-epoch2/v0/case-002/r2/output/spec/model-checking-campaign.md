# Model-checking campaign record (run incr-13b3a238967b)

Order (incremental guide Part 3): entry gate = all 7 fresh traces passed completion + witness (`trace-validation-inventory.md`) -> standard MC.cfg round -> (1) full update check over complete MCNext -> (2) concrete focused -> (3) open focused + discharge -> (4) Scenario hunts and canaries -> (5) final full check: no reference Action changed after the gate, only the Update.tla rely frame (open/discharge re-run) and a non-semantic property-module refactor, so the standard and full-update results apply to the final artifacts.

Bounds: Server={s1,s2,s3}, Txn={t1,t2}; MaxEpoch 2 (3 in seeded/durability/agreement hunts), MaxCrash 1-2, MaxAbandon 1-3 (see each cfg). Every run had a 30-minute outer bound (`spec/campaign.sh`); states under /dev/shm/specular-e2e-case-002/<run>, removed after each run. A budget-terminated run is LIMITED_COVERAGE, not a proof.

| Campaign | Spec / cfg | Mode | Outcome | Coverage (last report) | Log |
|---|---|---|---|---|---|
| Standard convergence (reference props) | MC.tla / MC.cfg | BFS | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress(28) at 2026-11-26 10:23:17: 71,562,032 states generated (2,801,113 s/min), 16,938,715 distinct states found (633,202 ds/min), 4,562,261 state | `spec/output/mc-standard-bfs.log` |
| Standard convergence follow-up | MC.tla / MC.cfg | simulation depth 150 | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress: 102523026 states checked, 1722478 traces generated (trace length: mean=39, var(x)=1000, sd=32) | `spec/output/mc-standard-sim.log` |
| 1 Full update check (all update props, full MCNext) | Update.tla / Update-full.cfg | BFS | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress(28) at 2026-11-26 10:23:15: 73,608,484 states generated (2,802,870 s/min), 17,502,456 distinct states found (655,427 ds/min), 4,751,457 state | `spec/output/update-full-bfs.log` |
| 1 Full update check follow-up | Update.tla / Update-full.cfg | simulation depth 150 | VIOLATION: Invariant NewLeaderAckFirst is violated (61 states) | Progress: 3381 states checked, 55 traces generated (trace length: mean=52, var(x)=644, sd=25) | `spec/output/update-full-sim.log` |
| 1 Full MCNext hunt U2 | Update.tla / Update-hunt-ackorder.cfg | simulation depth 120 | VIOLATION: Invariant NewLeaderAckFirst is violated (58 states) | Progress: 12523 states checked, 218 traces generated (trace length: mean=55, var(x)=617, sd=25) | `spec/output/update-hunt-ackorder-sim.log` |
| 1 Full MCNext hunt U3 | Update.tla / Update-hunt-npe.cfg | simulation depth 120 | VIOLATION: Invariant SyncCommitHasPendingProposal is violated (60 states) | Progress: 7858 states checked, 136 traces generated (trace length: mean=54, var(x)=652, sd=26) | `spec/output/update-hunt-npe-sim.log` |
| 1 Full MCNext hunt U4 | Update.tla / Update-hunt-split.cfg | simulation depth 120 | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress: 13905416 states checked, 233461 traces generated (trace length: mean=59, var(x)=596, sd=24) | `spec/output/update-hunt-split-sim.log` |
| 1 Full MCNext hunt U1 (stopped after U1 established elsewhere) | Update.tla / Update-hunt-durability.cfg | simulation depth 120 | no violation; stopped early (see name) | Progress: 1706244 states checked, 27199 traces generated (trace length: mean=54, var(x)=664, sd=26) | `spec/output/update-hunt-durability-sim.log` |
| 1 Full MCNext hunt CommittedAgreement (stopped, replaced by seeded) | Update.tla / Update-hunt-agreement.cfg | simulation depth 120 | no violation; stopped early (see name) | Progress: 1773053 states checked, 26794 traces generated (trace length: mean=64, var(x)=603, sd=25) | `spec/output/update-hunt-agreement-sim.log` |
| 1 Full MCNext from seeded states, U1 | Update.tla / Update-seeded-durability.cfg | BFS | VIOLATION: Invariant CommittedQuorumDurable is violated (10 states) | 104038 distinct, 36117 queued, depth 10 | `spec/output/update-seeded-durability-bfs.log` |
| 1 Full MCNext from seeded states, CommittedAgreement | Update.tla / Update-seeded-agreement.cfg | simulation depth 60 | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress: 29470473 states checked, 671829 traces generated (trace length: mean=33, var(x)=388, sd=20) | `spec/output/update-seeded-agreement-sim.log` |
| 2 Concrete focused (all props) | Update.tla / Update-focused.cfg | BFS | VIOLATION: Invariant NewLeaderAckFirst is violated (10 states) | 13922 distinct, 3125 queued, depth 10 | `spec/output/update-focused-bfs.log` |
| 2 Concrete focused U1 | Update.tla / Update-focused-durability.cfg | BFS | VIOLATION: Invariant CommittedQuorumDurable is violated (10 states) | 13804 distinct, 3151 queued, depth 10 | `spec/output/update-focused-durability-bfs.log` |
| 2 Concrete focused U3 | Update.tla / Update-focused-npe.cfg | BFS | VIOLATION: Invariant SyncCommitHasPendingProposal is violated (26 states) | 4089997 distinct, 941972 queued, depth 26 | `spec/output/update-focused-npe-bfs.log` |
| 2 Concrete focused U4 | Update.tla / Update-focused-split.cfg | BFS | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress(29) at 2026-11-26 10:24:37: 41,129,610 states generated (1,802,885 s/min), 9,070,691 distinct states found (366,210 ds/min), 1,645,574 states | `spec/output/update-focused-split-bfs.log` |
| 2 Concrete focused reference props | Update.tla / Update-focused-reference.cfg | BFS | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress(29) at 2026-11-26 10:24:37: 41,758,920 states generated (1,793,306 s/min), 9,189,942 distinct states found (354,548 ds/min), 1,658,336 states | `spec/output/update-focused-reference-bfs.log` |
| 3 Open focused (all props) | Update.tla / Update-open.cfg | BFS | VIOLATION: Invariant CommittedQuorumDurable is violated (10 states) | 123916 distinct, 43394 queued, depth 10 | `spec/output/update-open-bfs.log` |
| 3 Open focused U4 + reference | Update.tla / Update-open-split.cfg | BFS | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress(24) at 2026-11-26 10:55:54: 174,583,424 states generated (5,665,211 s/min), 39,865,496 distinct states found (1,266,639 ds/min), 12,096,274 s | `spec/output/update-open-split-bfs.log` |
| 3 Discharge r1 (rely frame bug) | Update.tla / Update-discharge.cfg | BFS | VIOLATION: Action property DischargeContext is violated (12 states) | 67875 distinct, 33996 queued, depth 12 | `spec/output/update-discharge-bfs-r1-frame-mismatch.log` |
| 3 Discharge (fixed rely) | Update.tla / Update-discharge.cfg | BFS | no violation; 30-min budget reached (LIMITED_COVERAGE) | Progress(22) at 2026-11-26 10:24:13: 46,684,225 states generated (1,830,312 s/min), 11,747,286 distinct states found (432,509 ds/min), 3,403,107 state | `spec/output/update-discharge-bfs.log` |

Reachability canaries (Update.tla, MCSpec full MCNext; a violation is the witness):

| Canary | Result |
|---|---|
| NotLeaderReached | WITNESS depth=4 (`spec/output/canary-NotLeaderReached.log`) |
| NotBroadcastReached | WITNESS depth=17 (`spec/output/canary-NotBroadcastReached.log`) |
| NotDiffReached | WITNESS depth=8 (`spec/output/canary-NotDiffReached.log`) |
| NotRecoveryReached | WITNESS(sim) traceStates=14 (`spec/output/canary-NotRecoveryReached.log`) |
| NotReelectReached | WITNESS(sim) traceStates=26 (`spec/output/canary-NotReelectReached.log`) |
| NotSnapReached | WITNESS(sim) traceStates=28 (`spec/output/canary-NotSnapReached.log`) |
| NotFollowerBroadcastReached | WITNESS(sim) traceStates=47 (`spec/output/canary-NotFollowerBroadcastReached.log`) |
| NotUpdateDurabilityGap | WITNESS(sim) traceStates=52 (`spec/output/canary-NotUpdateDurabilityGap.log`) |
| NotMutationReached | WITNESS(sim) traceStates=52 (`spec/output/canary-NotMutationReached.log`) |
| NotNlLoggedReached | WITNESS(sim) traceStates=58 (`spec/output/canary-NotNlLoggedReached.log`) |
| NotCommitAfterNlReached | WITNESS(sim) traceStates=64 (`spec/output/canary-NotCommitAfterNlReached.log`) |
| NotAckBeforeNlAckReached | WITNESS(sim) traceStates=62 (`spec/output/canary-NotAckBeforeNlAckReached.log`) |
| NotTruncReached | WITNESS(sim) traceStates=70 (`spec/output/canary-NotTruncReached.log`) |

Seeds of FocusedSpec/OpenSpec/SeededFullSpec (Update.tla `FocusedInit`) are reachable in the full model: canary NotUpdateDurabilityGap (full MCNext) and the reference behavior replaying `traces/diff-sync-uncommitted.ndjson` pass through such states (`spec/output/trace-oracle-diff-sync-uncommitted.log`).

Open-spec claim scope: fixed, already-established epoch (EnvUpdate = follower leave/join/register/enter-sync). Discharge (`DischargeContext`) checks every omitted in-scope step of the full model against EnvUpdate or a visible-state stutter; epoch-creating steps are outside the open claim and covered by the full MCNext checks only.
