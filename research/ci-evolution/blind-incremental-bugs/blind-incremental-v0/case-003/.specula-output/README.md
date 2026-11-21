# Specula V0 prior — exact-old CometBFT

This directory is a code-derived, pre-update verification prior built only from
the immutable source and neutral scope supplied for case 003.

- `modeling-brief.md` and `analysis-report.md`: source analysis and model plan
- `spec/`: base, trace, and model-checking specifications, configs, coverage,
  validation results, and preserved logs
- `harness/`: runnable instrumentation/trace harness and reversible baseline
  patch
- `traces/`: fresh NDJSON observations from the exact-old implementation

The result is intentionally labeled limited coverage. Read
`validation-report.md` for checked bounds and evidence.

