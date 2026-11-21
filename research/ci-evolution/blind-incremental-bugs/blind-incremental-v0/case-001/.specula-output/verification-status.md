# Verification status

## Outcome

- Workflow: `COMPLETED_WITH_LIMITED_COVERAGE`
- Trace validation: `PASSED`
- Model checking: `LIMITED_COVERAGE`
- Implementation findings: none reported by this neutral V0 workflow
- Blocking issues: none

## Trace result

Five fresh nonempty NDJSON files contain seven implementation events. Each file completed `TraceMatched` under `Trace.cfg`; every event used a named code-backed action and every captured post-state field was checked. See `spec/output/trace-*.log`.

## Model result

`MC.cfg` enables seven safety invariants over a bounded two-node model. TLC completed 253,262 distinct states at depth 27 with no error and nonzero coverage for all next-action branches. Finite nodes, terms, logs, messages, and action counters make this limited coverage rather than proof. See `spec/output/model-check.log` and `brief-coverage.md`.

The earlier three-node run was stopped by its five-minute outer timeout with a nonempty queue and is retained as incomplete exploration evidence only.

## Reproduction

Run `harness/run.sh` to reapply instrumentation idempotently and recollect traces. Run `harness/validate.sh` to validate all traces first and then execute the bounded model, using only `/dev/shm/specula-v0-case-001` for TLC state and cleaning it on exit.
