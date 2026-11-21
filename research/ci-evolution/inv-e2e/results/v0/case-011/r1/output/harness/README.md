# Specula incremental harness (Pre-Vote update)

One-command trace collection: `harness/run.sh` (applies the test-only
instrumentation to `work-source/`, a writable copy of `artifact/` at commit
`update`, builds with bounded timeouts, runs the 7 prior + 12 update scenarios,
writes `traces/*.ndjson`). Validation: `harness/validate-traces.sh`. See
`INSTRUMENTATION.md` for what changed relative to the V0 harness and
`repro/` for the MC-1 reproduction tests.

Fix controls (sanity only, not upstream fixes): `fixcheck-source/` = update +
`repro/candidate-fix-sanity.patch` (MC-1); `fixcheck2-source/` = update +
`repro/candidate-fix-combined-sanity.patch` (MC-1 + MC-2). Model copies with the
same fixes: `spec/fixcheck/`, `spec/fixcheck2/`. Reproduction:
`harness/repro/run-repro.sh [MC-1|MC-2|all]` (one cargo target dir per tree).
