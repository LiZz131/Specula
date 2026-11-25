# spec/output layout

Current run (case-002, revision `update`):
- `generation/` - preflight notes and pre-repair snapshots of base.tla
- `harness/`, `harness-run-*.log`, `harness-rebase-apply.log`, `build-warmup-pristine.log` - harness rebase/build/run
- `trace/` - trace validation logs (`r1..r5-*`; final full regression `r5-*`), evidence runs, `ledger.ndjson`, `coverage.json`
- `mc/` - model-checking logs, `ledger.ndjson`, `campaign-summary.md`, counterexamples `MC-*`
- `validation-handoff.md`

Files directly under `spec/output/` other than the above (e.g. `trace-final-*.log`,
`base-canonical-*.log`, `model-check-*.log`, `repair-suite/`) are the immutable V0 prior
run's evidence seeded into this directory; they are not results of this run.
`spec/legacy-V0/` holds V0-only scripts/manifests whose paths point to the prior environment.
