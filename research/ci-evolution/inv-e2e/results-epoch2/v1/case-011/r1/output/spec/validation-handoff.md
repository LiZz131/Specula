# Validation handoff (Validation 4) — case-011 Pre-Vote revision

* **Source**: `artifact/` commit `3ab6cdd` ("update"); instrumented copy
  `work-source/` = `3ab6cdd` + `harness/instrumentation.patch` (test-only).
* **Harness command**: `harness/run.sh` (apply → build → 16 scenarios → fresh
  traces); build log `spec/output/harness-build.log`, run log
  `spec/output/harness-run.log`. Toolchain `stable` 1.100.0 (pinned nightly not
  installed; V0 also substituted a toolchain).
* **Harness provenance**: V0 module `specula_trace_test.rs` reused; the V0 patch
  failed only on `openraft/src/engine/mod.rs` context drift (new test modules);
  all 7 V0 scenario setups unchanged. No replacement of the harness.
* **Trace validation command**: `harness/validate-traces.sh` (TLC, `Trace.cfg`,
  `PROPERTIES TraceConsumed`, states under `/dev/shm/specula-e2e-case-011/`).
* **Fresh trace inventory (new version)** — all PASS, every run reports
  "Checking temporal properties for the complete state space" and "No error":

| Trace | Events | Kind |
|---|---|---|
| start_election, reject_stale_log, grant_greater_vote, establish_leader, append_joint_membership, commit_membership, restart_follower | 1 each | V0 regression (rerun on new code) |
| grant_empty_logs | 2 | repair R-5 evidence |
| prevote_quorum_elect | 2 | U-S1 |
| prevote_reject_higher_vote | 3 | U-S2 |
| prevote_request_branches | 3 | U-S2/U-S5 |
| prevote_request_lease | 1 | U-S5 |
| candidate_prevote_then_establish | 5 | U-S3 (+ silent runtime completions) |
| prevote_cleared_by_append | 2 | U-S4, R-1 |
| prevote_cleared_by_vote_grant | 2 | U-S4 |
| prevote_single_voter | 1 | U-S1 |

* **Archived V0 traces** (`traces/archive-v0/*.ndjson`, exact-old run): retained
  as immutable evidence; superseded for the gate by their fresh reruns (same
  scenario names). Not replayed against the new model: they lack the mandatory
  new fields (`pre_candidate_*`, `append_behind_vote`, `send_pre_vote_pending`).
* **Field consumption**: `spec/output/trace-field-consumption.log` (every
  pre/post/args key read by `Trace.tla`).
* **Mutation controls**: 9 mutated copies (`traces/mutants/`) of update traces
  are all rejected (`spec/output/trace-mutation-controls.log`): pre-candidate
  kept/cleared, demotion vs. no demotion, higher-vote adoption, responder
  grant/mutation, probed term, log adoption, establishment lease.
* **Affected Actions observed**: `PreElect` (both branches), `HandlePreVoteRequest`
  (lease/log/vote/grant), `HandlePreVoteResponse` (grant→elect, reject),
  `DoElect` (via StartElection, PreElect, HandlePreVoteResponse). `TickElect`
  and `ExternalPreElect` are runtime wrappers (timer / RaftMsg) not driven by
  the engine-level harness: environment limitation; their guards are
  model-checked only.
* **Interaction coverage**: establishment keeps the pre-candidate (U-T4),
  AppendEntries and vote grant clear it (U-T5/U-T6), log adoption (R-1),
  leader lease at establishment (R-4). Not traced: `RefreshServerState`,
  `Crash`, message drop, runtime correlation filter (engine-level harness).
* **Semantic spec changes made during validation**: R-4 (trace-driven),
  R-5 (canary-driven, then trace `grant_empty_logs` added). Final full replay
  after the last change: `spec/output/trace-validation-round4.log` (16/16); final regression on the frozen model (md5 in `spec/output/final-spec-md5.txt`): `spec/output/trace-validation-final.log` (16/16).
