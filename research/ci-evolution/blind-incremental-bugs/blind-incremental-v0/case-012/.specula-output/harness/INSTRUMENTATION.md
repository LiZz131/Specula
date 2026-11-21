# Harness operation

Run from the suite root:

```bash
cd /work/prior/.specula-output
bash harness/run.sh
```

`apply.sh` applies `harness/patches/instrumentation.patch` to `/work/work-source` or recognizes that it is already applied. It never resets the tree. `run.sh` then runs nine exact-old unit scenarios under five-minute outer timeouts and recreates one NDJSON file per scenario. `preprocess_trace.py` removes nested helper probes from the three Engine-action scenarios, leaving each action trace at its observable before/after boundary; it never synthesizes or edits event fields.

Probe locations after apply are listed in `spec/instrumentation-spec.md`. Event serialization and field mapping live in `openraft/src/specula_trace.rs`; add a snapshot field in `capture_engine`, add a helper event in the matching `emit_*` function, and add the corresponding post-state check in `spec/Trace.tla`. To move a capture point, keep the `capture_engine` call before the exact transition and `emit_engine` after it.

Tracing is disabled unless both environment variables are present:

- `SPECULA_TRACE=1`
- `SPECULA_TRACE_FILE=/absolute/path/to/scenario.ndjson`

After any probe adjustment, regenerate the patch relative to the neutral baseline and rerun `bash harness/run.sh`; every named trace is removed first, so nonempty output is fresh evidence.
