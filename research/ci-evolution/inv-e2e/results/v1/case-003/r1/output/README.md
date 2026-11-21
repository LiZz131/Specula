# Specula V1 incremental run — CometBFT case 003

Incremental update of the exact-old V0 suite for the source update
`9dd6e50` → `401753b` (`ConsensusParams.ValidateUpdate` rewrite).

- Disposition: **MODEL_CHANGE_REQUIRED** (reported as `MODEL_UPDATED`).
- Validation: prior harness rebased; 19 fresh traces (6 prior + 13 update) all
  matched by real TLC trace validation; mutation and old-code controls show the
  new decision and fields are checked.
- Model checking: standard, full-update, focused, open/discharge, hunts,
  deep BFS/simulation, and 25 reachability canaries. All are bounded runs
  (`LIMITED_COVERAGE`).
- Finding **MC-1** (High, introduced by the update, reproduced): an unchanged,
  already reached `VoteExtensionsEnableHeight` update is rejected, which makes
  the chain halt permanently.

Start with `validation-report.md`, `spec/bug-report.md`, `spec/findings.json`,
`spec/final-result.json`. Analysis: `analysis-report.md`, `modeling-brief.md`.
Specs: `spec/base.tla`, `spec/MC.tla`, `spec/Trace.tla`, `spec/Update.tla`.
Property evidence: `spec/invariant-evidence.json`. Logs: `spec/output/`
(V0 logs in `spec/output/v0-archive/`). Traces: `traces/` (V0 traces in
`traces/archive-v0/`).
