# Instrumentation (rebased for the Pre-Vote revision)

Prior V0 harness: engine-level, test-only (`#[cfg(test)]`) module that calls real `Engine` methods and writes one NDJSON record per call. Rebased, not regenerated:

- `openraft/src/engine/mod.rs`: register `mod specular_trace_test;` (context drifted because the update added `pre_elect_test` etc.; the old patch failed to apply, `spec/output` has no prior-patch log because the failure was immediate).
- `openraft/src/engine/tests/specular_trace_test.rs`: prior file renamed (`specula`→`specular`), state extended with `pre_candidate_*`, `pre_grants`, `send_pre_vote_pending`, `send_pre_vote_req`, `leader_vote`, real `seen_greater_log`; 11 update scenarios added (see `instrumentation-spec.md` §4).
- Production code is untouched.

Rebuild / rerun:

```bash
harness/run.sh                 # copy artifact -> work-source (if absent), apply patch, build, run 18 scenarios
harness/validate-traces.sh     # real TLC replay of every trace (Trace.tla/Trace.cfg)
harness/trace-negative-controls.sh   # one-field mutations must be rejected
```
