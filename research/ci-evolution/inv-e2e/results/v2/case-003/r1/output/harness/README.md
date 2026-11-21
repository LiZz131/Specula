# Trace harness (case-003 updated revision)

`run.sh` idempotently applies `patches/instrumentation.patch` to `../artifact`
(override with `SPECULA_WORK_SOURCE`), runs 16 real Go scenarios (6 V0
regression + 7 update-focused ApplyBlock + 3 update×recovery), each in its own
process with a ten-minute outer timeout, checks that every NDJSON file is nonempty
and structurally valid, and keeps filtered test logs under
`../spec/output/harness/`.

```bash
cd /work/current/.specula-output && bash harness/run.sh
```

`clean.sh [working-copy]` reverses only the instrumentation patch.
