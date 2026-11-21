# Specula harness (V1, rebased from the exact-old V0 harness)

`run.sh` idempotently applies `patches/instrumentation.patch` to
`../artifact` (override with `SPECULA_WORK_SOURCE`), builds `./internal/...`,
runs the six prior scenarios and twelve update-focused test processes (ten
apply scenarios + two two-phase recovery scenarios, fourteen traces) with a ten-minute outer timeout
per command, checks every NDJSON file is nonempty and structurally valid, keeps
test logs under `../spec/output/harness-*.log`, and removes the
instrumentation on exit.

```bash
cd /work/current/.specula-output && bash harness/run.sh
```

`clean.sh [working-copy]` reverses the patch. `patches/instrumentation-v0-prior.patch`
is the unmodified V0 patch kept for provenance.
