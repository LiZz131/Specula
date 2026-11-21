# Validation changelog

## V0 (prior, exact-old) — retained summary

V0 converged in one trace-first round (six traces, no fixes, no findings).
Its logs are preserved under `spec/output/v0-prior/` and its traces under
`traces/archived-v0/` (immutable old-version evidence; see disposition below).

## V1 Generation (incremental, source delta `baseline` -> `update`)

- [decision] `MODEL_CHANGE_REQUIRED`. `types/params.go:208-261`
  (`ConsensusParams.ValidateUpdate`) changes which of the modeled Actions
  `UpdateStateAccepted` / `UpdateStateRejected` is enabled, as a function of
  (current enable height, proposed enable height, block height). The V0 static
  `ValidParams` set cannot express that dependency. Exhaustive old/new branch
  projection: `spec/analysis/validate_update_projection.py` →
  `spec/output/validate-update-projection.log` (63 differing tuples on the
  grid: 21 first-enablement, 21 cancel-future — old reject/new accept; 21
  unchanged-after-enable — old accept/new reject; closed form of the new rule
  verified).
- [fix-spec / source-driven] `base.tla`: parameter records become
  `[body, veh]`; update descriptors `[body, abci]`; added code-faithful
  `ApplyParamUpdate` (params.go:289-318), `ValidateBasicOK` (params.go:145-206),
  `ValidateUpdateOK` rows 1-9 (params.go:219-261), `VEEnabled`
  (params.go:75-83), `UpdateAccepted` (execution.go:611-631).
  `UpdateStateRejected` is split by stage (`basic` / `update`) because the code
  paths diverge at execution.go:617-625.
- [property] `ParameterUpdateReflected` re-expressed for the new
  representation (meaning unchanged); new structural `InstalledParamsBasicValid`.
- [update] `Update.tla` with Affected/Interaction/Omitted actions, `EnvUpdate`
  rely and `DischargeEnvUpdate`, update properties P-U1..P-U4 and 11
  reachability canaries; 22 `Update_*.cfg`.
- [preflight] SANY on base/MC/Trace/Update (`output/sany-v1-generation.log`);
  static cfg resolution + per-action variable-assignment check
  (`output/static-preflight-v1.log`: PASS). No TLC exploration in generation.

## V1 Round 1 — Harness rebase and trace validation

- [rebase] The V0 patch (sha256 `d9c8c96a…`, preserved as
  `harness/patches/instrumentation-v0-prior.patch`) applied cleanly to the
  updated tree (`output/harness-rebase-apply-check.log`); `execution.go` and
  `replay.go` are unchanged by the update. Only the parameter projection
  changed: params are now `{body, veh}`, update descriptors
  `{present, body, abciPresent, veh}`; `FinalizeBlock` adds `proposedBodyValid`;
  `UpdateStateRejected` adds `stage` and `error`. New patch:
  `harness/patches/instrumentation.patch` (sha256 `3a6785ed…`).
- [scenarios] Prior six scenarios rerun on the new implementation; 14
  update-focused traces added (ValidateUpdate rows 2-9 on the production path,
  producer→affected→consumer two-block chain, rejection→restart→real replay,
  accepted enable→injected state-save failure→mock replay).
- [fix-trace] `Trace.tla` `TraceValidBodies` initially admitted every body seen
  in any post-state, making acceptance of an invalid body (and
  `InstalledParamsBasicValid`) vacuous. Negative control M5 exposed it (mutant
  passed). Repaired to use only independent evidence (first-state bodies +
  harness `proposedBodyValid`). Abstraction-gap repair in the trace wrapper;
  no base semantics changed. All six mutants now rejected at the intended event
  (`output/negative-controls/summary.txt`).
- [result] Full fresh suite (20 traces) PASS against the final candidate, each
  with `TraceMatched` checked and depth = events + 1
  (`output/trace-v1-full-regression.txt`, per-trace `output/trace-v1-*.log`).
- [regression] Scope baseline tests pass on the clean updated tree
  (`output/regression-types-v1.log`, `output/regression-state-v1.log`,
  `output/regression-consensus-replay-v1.log`).
- [archived] The six V0 traces in `traces/archived-v0/` were produced by the
  old implementation with the V0 field schema (opaque parameter
  fingerprints). Disposition: superseded by fresh V1 traces of the same six
  scenarios; not replayed against V1 because their schema lacks the enable
  height. They remain immutable evidence for V0.

## V1 Round 1 — Model checking

- [fix-cfg] TLC's cfg parser rejects negative literals; the `-1` enable-height
  domain is substituted from `MC!MCVEHValuesWithNegative` (cfg plumbing only).
- [fix-update-lens] `EnvUpdate` first read `counters'.blocks` before binding
  `counters'` (TLC evaluation error in `Update_open*.cfg`); rewritten as an
  equivalent set membership. Open/focused lenses omit `EnvironmentStutter`, so
  their cfgs set `CHECK_DEADLOCK FALSE` (deadlock is not a property there).
  Added `DischargeCanaryOmittedNeverFires` (expected violation) to show the
  discharge is non-vacuous.
- [result] `MC.cfg` (standard convergence): 75,944 distinct states, depth 34,
  exhausted, no violation. No Case A/B counterexample arose; no semantic
  change to `base.tla` was needed during model checking.
- [bug] UpdateStateRejected / `ContractLegalUpdateAccepted` (P-U1), Case C
  candidate: `Update_full.cfg` 6-state counterexample — enable height 1 at
  genesis, application re-sends `Abci{VoteExtensionsEnableHeight: 1}`, row 6
  rejects at height 1. Same violation in focused, open, U1 (13-state upgrade
  path: enable at 2 in block 1, re-send in block 2), U2 and U4 hunts.
  Fidelity check: the step is reproduced by real traces
  (`apply_ve_unchanged_echo`, `apply_ve_unchanged_after_enable`,
  `replay_ve_unchanged_*`), so it is not a Case B artifact. Saved as MC-1
  (`bug-report.md`, `findings.json`); confirmed REPRODUCED
  (`confirmation-MC-1.md`).
- [result] P-U2..P-U4 hold in every run (full, focused, open + discharge, U1-U5
  safety variants, deep BFS at height 4, 30-min deep simulation); all 7 V0 and
  11 update reachability canaries reached.
- [final] Final full checks rerun on the final artifacts:
  `final-std-MC`, `final-upd-full-safety` (no violation, exhausted) and
  `final-upd-full` (P-U1 violation, MC-1). The final trace regression
  (20/20) applies to the final `base.tla`/`Trace.tla` (unchanged since).

## Result

Converged in one round (one trace-wrapper repair, no base-model repair).
Bug hunting: 1 update-introduced bug found (MC-1, REPRODUCED). All coverage is
bounded (`LIMITED_COVERAGE`).
