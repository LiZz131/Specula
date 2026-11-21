# V1 trace harness (rebased from the exact-old V0 harness)

`run.sh` idempotently applies `patches/instrumentation.patch` to the updated
source (`../artifact`, override with `SPECULA_WORK_SOURCE`), runs the six prior
regression scenarios and thirteen update-focused scenarios, each in its own Go
process with a ten-minute outer timeout, checks that every NDJSON file is
nonempty and structurally valid, and keeps the test logs under `../spec/output/`.

```bash
bash harness/run.sh                       # all scenarios, fresh traces in traces/
SPECULA_ONLY=update bash harness/run.sh   # update scenarios only
SPECULA_WORK_SOURCE=/path/to/tree SPECULA_TRACE_DIR=/tmp/t SPECULA_LOG_PREFIX=control bash harness/run.sh
bash harness/clean.sh                     # reverse only the instrumentation patch
harness/repro_MC-1.sh [tree] [log]        # instrumentation-free MC-1 reproduction (exit 1 = bug present)
```

- `patches/v0-instrumentation.patch`: the prior patch, applied cleanly to 401753b.
- `patches/instrumentation.patch`: the V1 patch (prior hooks + V1 fields + update scenarios).
- `src/*.txt`: readable copies of the trace module and the scenario file from the patch.
- `repro/specula_mc1_repro_test.go`: copied into `internal/state/` by
  `repro_MC-1.sh` and removed afterwards.
