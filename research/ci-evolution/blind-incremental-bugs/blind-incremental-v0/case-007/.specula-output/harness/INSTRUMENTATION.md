# Exact-old trace harness

`apply.sh` idempotently applies `patches/instrumentation.patch` to the writable
`/work/work-source` copy only. `run.sh` executes neutral existing tests under
five-minute outer bounds and writes one fresh NDJSON file per process. The
`SPECULA_TRACE_FILE` switch is disabled by default, and
`SPECULA_TRACE_TARGET` restricts each trace to one modeled target.

`clean.sh` removes generated traces, harness logs, and the dedicated TLC shared
memory directory; it does not rewrite source. Each line is checked with `jq`
before the harness returns success.

