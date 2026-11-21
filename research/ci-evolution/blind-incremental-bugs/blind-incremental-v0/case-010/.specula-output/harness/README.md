# Runnable exact-old trace harness

Run from any directory:

```bash
/work/prior/.specula-output/harness/run.sh
```

The script verifies the neutral working-tree commit, runs each real three-peer JUnit scenario under an independent 15-minute outer timeout, writes Maven logs under `spec/output/`, creates two run-labelled trace files, and fails unless both NDJSON files are nonempty. It refuses to overwrite retained traces. Set `SPECULA_TRACE_RUN_ID` to a new label for a later run. Instrumentation is dormant unless `specula.trace.file` is set.

The preserved patch can be reviewed or replayed from the neutral root:

```bash
git -C /work/work-source apply --check /work/prior/.specula-output/harness/patches/instrumentation.patch
```

Trace validation uses the `JSON` environment variable consumed by `IOUtils`:

```bash
cd /work/prior/.specula-output/spec
JSON=/work/prior/.specula-output/traces/election-ordered.ndjson \
  timeout 5m java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
  tlc2.TLC -workers 1 -config Trace.cfg Trace
```

Use a fresh `-metadir` below `/dev/shm/specula-v0-case-010/` for every TLC run and delete it after preserving the corresponding log.
