# Specula V1 — incremental run for case 003 (CometBFT, `baseline` -> `update`)

This directory evolves the immutable exact-old V0 suite
(`/work/previous/.specula-output/`) for the updated source in `artifact/`
(two neutral commits; the update rewrites `ConsensusParams.ValidateUpdate`,
`types/params.go:208-261`).

- Disposition: **MODEL_CHANGE_REQUIRED** (reported as `MODEL_UPDATED`).
- `modeling-brief.md` §8 and `analysis-report.md` (V1 section): decision,
  old/new projection, update Scenarios U1-U4.
- `spec/`: updated reference `base.tla`/`MC.tla`/`Trace.tla`, `Update.tla`
  lens (affected/interaction actions, `EnvUpdate` rely + discharge, update
  properties P-U1..P-U4, reachability canaries), all cfgs, `changelog.md`,
  `brief-coverage.md`, `instrumentation-spec.md`, logs in `spec/output/`.
- `harness/`: V0 harness rebased onto the updated tree plus update-focused
  scenarios; `bash harness/run.sh` regenerates all 20 fresh traces in
  `traces/` (V0 traces archived in `traces/archived-v0/`).
- Finding: **MC-1** — the updated `ValidateUpdate` rejects an unchanged
  `VoteExtensionsEnableHeight` once vote extensions are enabled; consensus
  halts and restart cannot recover. Model counterexample + Level-0
  reproduction with an old-tree control: `spec/bug-report.md`,
  `spec/findings.json`, `spec/confirmation-MC-1.md`, `spec/repro/`.
- `validation-report.md`: trace validation, model-checking campaigns, bounds.

All model-checking results are bounded (`LIMITED_COVERAGE`), never proofs.
