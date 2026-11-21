# Exact-old trace harness

`run.sh` idempotently applies `patches/instrumentation.patch` to
`/work/work-source`, executes five ordinary exact-old unit scenarios under
five-minute outer timeouts, checks every emitted line with `jq`, and replaces
the NDJSON files in `../traces`.

`validate.sh` replays every nonempty trace through `Trace.tla` before running
the bounded `MC.tla` model. It places TLC state below
`/dev/shm/specula-v0-case-001`, applies two/five-minute outer timeouts, writes
logs to `../spec/output`, and removes the state root on exit.

Set `SPECULA_WORK_SOURCE` to use another byte-identical writable baseline.
The patch is intentionally never applied to `/work/source`.
