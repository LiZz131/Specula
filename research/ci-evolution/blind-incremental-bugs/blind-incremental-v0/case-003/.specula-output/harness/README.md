# Exact-old trace harness

`run.sh` idempotently applies `patches/instrumentation.patch` to the writable
copy, runs six real Go scenarios with a ten-minute outer timeout per command,
checks that every NDJSON file is nonempty and structurally valid, and preserves
test logs under `../spec/output/`.

```bash
/work/prior/.specula-output/harness/run.sh
```

Set `SPECULA_WORK_SOURCE` to another byte-identical writable baseline if needed.
`clean.sh [working-copy]` reverses only the preserved instrumentation patch.
Neither script modifies `/work/source`.

