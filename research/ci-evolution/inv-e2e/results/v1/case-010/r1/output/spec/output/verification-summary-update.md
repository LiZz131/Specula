# Verification summary — incremental case-010 (`baseline` f8533cd -> `update` b16ba71)

Disposition: **MODEL_CHANGE_REQUIRED** (reported as MODEL_UPDATED). All model-checking results are bounded (3 servers; `MaxTxn` 1-2; `MaxEpoch` 1-2; <=1 crash; 1-2 counted learner exits; <=2 election rounds; <=1 periodic snapshot). Budget-terminated runs are **LIMITED_COVERAGE**, never proof.

## Validation handoff

- Source: artifact HEAD `b16ba7105238d46b0d51e3cc5d92ce9fe16de834` (clean before instrumentation, `spec/output/new-source-head.txt`); old-revision control tree `artifact-old` at `f8533cd` (git worktree; test-only copy of the update's new `QuorumPeerMainTest.java`).
- Harness: prior patch applied cleanly to the new source (kept as `harness/patches/instrumentation-v0-prior.patch`), rebased and densified into `harness/patches/instrumentation.patch` (schema v3). Command: `SPECULA_TRACE_RUN_ID=<id> harness/run.sh` (build + 5 scenarios, each under `timeout 20m`). Old-revision control: `harness/run-old-control.sh` (`harness/patches/instrumentation-old-control.patch`).
- Provenance gap in the prior run: its stateful (schema v2) emitter that produced `traces/*-stateful.ndjson` was not preserved (`harness/src` was empty; the preserved patch emits schema v1). The emitter was rebuilt; v2 shadow fields were replaced by real observations where possible.
- Retained fresh new-version traces (final probe version `v3d`): `traces/election-ordered-v3d.ndjson` (80 events), `traces/restart-catchup-v3d.ndjson` (141), `traces/upd-snap-exit-diff-v3d.ndjson` (273, the update's own test), `traces/upd-serving-exit-v3d.ndjson` (120), `traces/upd-snap-complete-v3d.ndjson` (151, forced SNAP). All pass `Trace.cfg` with `PROPERTIES TraceMatched` and all core + update invariants on the final model (`spec/output/trace-*-v3d.log`). Earlier captures `*-v3`, `*-v3b`, `*-v3c` are superseded intermediate captures (probe ordering races fixed in v3c/v3d: atomic state-write+emit, atomic `setPeerState`); they remain as evidence of the repairs.
- Archived V0 traces (4): replay on common fields against the new reference (`spec/output/archived-trace-*.log`, earlier candidate) — disposition: retained as archived old-version evidence, not part of the gate.
- Old-revision control traces: `traces/old-control/upd-snap-exit-diff-oldctl.ndjson` replays under `Trace-prior.cfg` (PRIOR) up to event 166 where `ExitedLearnerMemoryBackedByLog` fails (expected), and under `Trace-prior-core.cfg` through the restart where the model's `durable` = `<<11>>` equals the real recovered history `[11]`, then the client-visible gap violates `OrderedHistoriesV1` at the DIFF re-join (expected). `traces/old-control/upd-serving-exit-oldctl.ndjson` replays completely under PRIOR (no leaked processor).
- Update coverage (fresh traces): `LearnerShutdown` variants `full=true/dbInit=false` (SNAP exit), `served=true/leakedNow=true` (serving exit, leaked processor), `ReloadDatabase`, `LoadSyncSnapshot`, NEWLEADER sync snapshot (`FinishSyncSnapshot`), DIFF re-join, restart recovery checked against the real recovered WAL. Not observed (timing): `TruncateLog`, `ApplySyncCommit`, leaked flush of queued writes — covered by MC only. Inventory: `spec/output/trace-inventory.md` (v3 capture; event set identical in v3d).
- Code observations (both revisions, same probes): the update's test `testDiffSyncAfterSnap` fails on the old revision ("node 0 should exist", `spec/output/harness/old-control-upd-snap-exit-diff-oldctl.log`) and passes on the new one; serving-follower exit leaks `SyncThread` on the new revision only (`spec/output/harness/upd-serving-exit-v3.surefire-output.txt` vs `spec/output/harness/old-control-upd-serving-exit-*SpeculaTraceScenarioTest-output.txt`).
- Validation changed semantic spec files: yes (see `spec/changelog.md`).

## Model checking (final model)

Complete table: `spec/output/final-campaign-table.md`. Superseded runs on earlier candidates are kept in `spec/output/` (non-`final-`/`f2-` names) and `spec/output/superseded/`.

| Campaign | Config | Outcome |
|---|---|---|
| Standard convergence | `MC.cfg` (MC module) | complete, no violation (65,206 states, depth 46) |
| Full reference | `MC-full.cfg` | no violation; LIMITED_COVERAGE (11.7M states, BFS level 38) |
| Full update properties | `Update-full.cfg` | no violation; LIMITED_COVERAGE (5.5M states, level 34) |
| Full residual (+simulation) | `Update-full-residual.cfg` | no violation; LIMITED (11.1M states, level 34); simulation 190,471 traces, no violation |
| Concrete focused | `Update-focused.cfg` | `OrderedHistoriesV1` (durable replay-order conjunct) = MC-1/MC-3 class |
| Focused residual | `Update-focused-residual.cfg` | no violation; LIMITED (7.4M states, level 26) |
| Open focused | `Update-open.cfg` | `OrderedHistoriesV1` = MC-1/MC-3 class |
| Open residual (+simulation) | `Update-open-residual.cfg` | no violation; LIMITED (7.3M states, level 21); simulation 117,503 traces, no violation |
| Discharge of the rely | `Update-discharge.cfg` (`DischargeContext` over `MCNext`) | no violation; LIMITED (5.6M states, level 33) |
| UPD-1 SNAP fix | `Update-hunt-snap.cfg` | complete, no violation (144,904 states, depth 46) |
| UPD-1 PRIOR controls | `Update-control-prior*.cfg` | `ExitedLearnerMemoryBackedByLog` (depth 17), `RecoverableHistoryComplete` (depth 25): old bug |
| UPD-2 TRUNC | `Update-hunt-trunc*.cfg`, `Update-control-prior-trunc*.cfg` | U1/U2 violated in UPDATED and PRIOR: MC-2 |
| UPD-3 leak | `Update-hunt-leak-*.cfg` | U2 (17), U4 (15), U3 (19) violated: MC-1 |
| UPD-3 PRIOR controls | `Update-control-prior-leak*.cfg` | U2: complete, no violation (238,362 states, depth 45); U3/U4 violated: MC-3 |
| Reachability canaries | `Update-canary-*.cfg` (8) | all witnessed (steady state depth 31; SNAP exit 17; reload 9; DIFF after reload 13; committed recoverable after SNAP exit 19; TRUNC exit 16; serving exit 2; leaked flush after re-sync 9) |
| Inherited hunts | `MC-{election,sync,commit,apply,snapshot,recovery}-hunt.cfg` | all sentinels witnessed (depths 4/18/25/26/20/20) |
| Inherited complete schedules | `MC-recovery-complete.cfg`, `MC-snapshot-complete.cfg` | complete, no violation |
| Evidence oracles | `Evidence-*.cfg` | separating states for property decisions (`spec/invariant-evidence.json`) |

Classification of every non-sentinel violation on the final model: MC-1 (update-introduced, Case C candidate), MC-2 (pre-existing, Case C candidate), MC-3 (pre-existing, Case C candidate); no unresolved Case A/B. Case A/B repairs made during validation/MC are listed in `spec/changelog.md`.

## Limits

- All exploration is bounded; budget-terminated runs are LIMITED_COVERAGE.
- Election is abstract (durable-length/epoch preference; a LOOKING peer may join an established leader with retained round votes); observers, reconfiguration, sessions excluded.
- Periodic snapshots do not change the modeled recoverable history (prior abstraction kept); NEWLEADER sync snapshots and TRUNC-with-newer-snapshot do.
- `forceSnapSync` with a peer ahead of the leader's committed log is excluded (test-only knob).
- Adjacent duplicate WAL records are accepted (`unresolved` in `invariant-evidence.json`).
- MC-1/MC-2/MC-3 were not reproduced end-to-end in real code (Part 4 not executed here); MC-1's thread leak and the UPD-1 attribution were observed in real code.
