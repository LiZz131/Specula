# Specula incremental run — case-003 (updated CometBFT revision)

Current suite for artifact commit `401753b` ("update"), evolved from the V0
exact-old prior (`/work/previous/.specula-output`, kept immutable).

- Decision: `MODEL_CHANGE_REQUIRED` (reported as `MODEL_UPDATED`) — the rewritten
  `ConsensusParams.ValidateUpdate` changes which enable-height updates are accepted.
- `analysis-report.md` / `modeling-brief.md`: V0 analysis + "Incremental update analysis".
- `spec/`: reference (`base.tla`, `MC.tla`, `Trace.tla`), update lens (`Update.tla`,
  `UpdateProps.tla`), cfgs, `invariant-evidence.json` + `evidence/`, `changelog.md`,
  `bug-report.md`, `findings.json`, `confirmation-MC-1.md`, `repro/MC-1/`, logs in `output/`.
- `harness/`: rebased instrumentation patch, `run.sh` (16 scenarios), old/new observation test.
- `traces/`: 16 fresh traces from the updated implementation; `traces/archived-v0/`
  keeps the six V0 traces (superseded by fresh reruns of the same scenarios).
- `validation-report.md`: trace validation, model-checking campaigns, coverage limits.

Result: one model-checking finding (MC-1, reproduced on the updated revision, absent
on the baseline; requirement contested by the update's own unit test); all other
reference and update properties hold within the checked bounds
(LIMITED_COVERAGE, not a proof).
