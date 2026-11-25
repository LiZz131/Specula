# Incremental Specula run — case-011 (OpenRaft Pre-Vote revision)

**Disposition:** `MODEL_CHANGE_REQUIRED` (reported as `MODEL_UPDATED`).
**Result:** two update-introduced model-checking findings (MC-1 High, MC-2 Medium);
reference safety invariants hold within bounds; all coverage is `LIMITED_COVERAGE`.

| Phase | Key artifacts |
|---|---|
| Generation | `modeling-brief.md` §0 (decision gate), §8 (update Scenarios/properties); `analysis-report.md` (incremental section); `spec/base.tla`, `spec/MC.tla`, `spec/Trace.tla`, `spec/Update.tla`, cfgs; `instrumentation-spec.md` §4; `brief-coverage.md`; `spec/invariant-evidence.json` (+ `spec/evidence/`) |
| Validation | `harness/` (rebased V0 harness: `run.sh`, `validate-traces.sh`, `instrumentation.patch`); `traces/*.ndjson` (16 fresh); `spec/output/trace-validation-final.log`; `spec/output/trace-mutation-controls.log`; `spec/output/trace-field-consumption.log`; `spec/validation-handoff.md` |
| Model checking | `spec/output/mc-*.log` (+ `campaign-summary.json`); `spec/witness/livelock/`; `spec/bug-report.md`; `spec/findings.json`; `spec/output/observations.log` (real-engine observations) |
| History | `spec/changelog.md`; prior inputs kept in `spec/prior-v0/`, `spec/output/prior-v0/`, `traces/archive-v0/` |

Repairs of the inherited V0 model (R-1..R-5) are listed separately from the source
delta in `spec/changelog.md`; R-5 shows the V0 three-voter checks never reached a
leader.

Reproduce: `harness/run.sh` → `harness/validate-traces.sh` →
`harness/run-model-check.sh <name> <Module> <cfg>` (see `spec/output/mc-*.log`
headers for the exact commands) → `harness/run-observations.sh`.
