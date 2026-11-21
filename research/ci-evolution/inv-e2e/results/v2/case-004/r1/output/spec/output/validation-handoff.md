# Validation handoff (incremental, artifact d7176ef)

- Source: `artifact/` HEAD `d7176ef` ("update"); instrumentation = `harness/instrumentation.patch`
  (V0 patch rebased + update probes), applied by `harness/apply.sh` (idempotent).
- Harness command: `harness/run.sh` (logs `spec/output/harness-unit.log`,
  `spec/output/harness-core.log`, stdout `spec/output/harness-run.stdout`); toolchain
  `cargo +stable` 1.100.0 (V0 used 1.95.0, not installed here).
- Trace validation command: `spec/run_trace_validation.sh` (TLC `-deadlock`, `Trace.cfg` with
  `PROPERTIES TraceMatched`, one TLC per trace, states under `/dev/shm/specula-e2e-case-004/`,
  removed after each run). Every log below contains `Finished checking temporal properties` and
  `Model checking completed. No error has been found.`
- Source tests on the instrumented tree: `spec/output/source-tests-lib.log` (198 passed),
  `spec/output/source-tests-client-api.log` (18 passed, includes t14 and the t99 scenarios).
- Semantic spec files changed during validation: yes — `base.tla` gained `panicked` and
  `CandidateGrantPanic` (code observation of U2); trace suite re-run afterwards (all PASS).

## Fresh trace inventory (all PASS)

| result | trace | events | replayed events | log |
|---|---|---:|---|---|
| PASS | `traces/election.ndjson` | 4 | Elect, VoteResponse, VoteResponse | `spec/output/trace-election.log` |
| PASS | `traces/follower-append.ndjson` | 2 | FollowerAppend | `spec/output/trace-follower-append.log` |
| PASS | `traces/joint-membership.ndjson` | 2 | LeaderAppend | `spec/output/trace-joint-membership.log` |
| PASS | `traces/learner-membership.ndjson` | 2 | LeaderAppend | `spec/output/trace-learner-membership.log` |
| PASS | `traces/partial-replication.ndjson` | 4 | AckReplication, AckReplication, AckReplication | `spec/output/trace-partial-replication.log` |
| PASS | `traces/restart.ndjson` | 2 | Startup | `spec/output/trace-restart.log` |
| PASS | `traces/uniform-membership.ndjson` | 2 | LeaderAppend | `spec/output/trace-uniform-membership.log` |
| PASS | `traces/vote-request.ndjson` | 2 | VoteRequest | `spec/output/trace-vote-request.log` |
| PASS | `traces/core-t14-transfer-leader/transfer-n2-001.ndjson` | 3 | TransferLeader, VoteRequest | `spec/output/trace-core-t14-transfer-leader__transfer-n2-001.log` |
| PASS | `traces/core-t14-transfer-leader/transfer-n2-003.ndjson` | 2 | TransferLeader | `spec/output/trace-core-t14-transfer-leader__transfer-n2-003.log` |
| PASS | `traces/core-t14-transfer-leader/transfer-n3-002.ndjson` | 4 | TransferLeader, VoteResponse, VoteResponse | `spec/output/trace-core-t14-transfer-leader__transfer-n3-002.log` |
| PASS | `traces/core-transfer-all-nodes/transfer-n1-002.ndjson` | 3 | TransferLeader, VoteRequest | `spec/output/trace-core-transfer-all-nodes__transfer-n1-002.log` |
| PASS | `traces/core-transfer-all-nodes/transfer-n2-003.ndjson` | 4 | TransferLeader, VoteResponse, VoteResponse | `spec/output/trace-core-transfer-all-nodes__transfer-n2-003.log` |
| PASS | `traces/core-transfer-all-nodes/transfer-n3-001.ndjson` | 3 | TransferLeader, VoteRequest | `spec/output/trace-core-transfer-all-nodes__transfer-n3-001.log` |
| PASS | `traces/core-transfer-to-learner/transfer-n1-004.ndjson` | 3 | TransferLeader, VoteRequest | `spec/output/trace-core-transfer-to-learner__transfer-n1-004.log` |
| PASS | `traces/core-transfer-to-learner/transfer-n2-001.ndjson` | 4 | TransferLeader, VoteRequest, VoteRequest | `spec/output/trace-core-transfer-to-learner__transfer-n2-001.log` |
| PASS | `traces/core-transfer-to-learner/transfer-n3-002.ndjson` | 2 | TransferLeader | `spec/output/trace-core-transfer-to-learner__transfer-n3-002.log` |
| PASS | `traces/core-transfer-to-learner/transfer-n4-003.ndjson` | 2 | TransferLeader | `spec/output/trace-core-transfer-to-learner__transfer-n4-003.log` |

## Update coverage

| Affected / interaction behavior | Fresh trace evidence | Compared by |
|---|---|---|
| TransferLeader at a voter target (`vote==from`, `to==self`) → `Elect` | `core-t14-transfer-leader/transfer-n3-002`, `core-transfer-all-nodes/transfer-n2-003` | `TraceTransferLeader` + `ValidatePostState` (vote, last_seen, role, candidate, granters, commands, accepted) |
| TransferLeader at a learner target → `Elect` (learner candidate) | `core-transfer-to-learner/transfer-n4-003` | same; `IsMember` branch of `Elect` |
| TransferLeader non-target (lease only) incl. the old Leader | `core-*/transfer-n1-*`, `transfer-n2-001`, `transfer-n3-001`, … | stutter of every modeled field (mutation m3) |
| TransferLeader with stale `from` (U3) | `core-t14-transfer-leader/transfer-n2-003` | stutter; mutation m8 shows the vote guard dominates `to` |
| Consumer: peers' VoteRequest grant (full-LogId freshness) incl. the old Leader stepping down | `core-*/transfer-n1-*`, `transfer-n2-001`, `transfer-n3-001` | `TraceVoteRequest` (mutation m5 checks `last_term`) |
| Consumer: candidate self grant then remote grant → Leader (blank, commands) | `core-t14-transfer-leader/transfer-n3-002`, `core-transfer-all-nodes/transfer-n2-003` | `TraceVoteResponse` |
| Consequence: learner self grant panics (`CandidateGrantPanic`) | not traceable (the RaftCore task panics inside the handler; no post-state) — observed in `spec/output/harness-core.log`, `spec/output/obs-transfer-to-learner.jsonl`, clean repro logs | code observation; MC (`CanaryLearnerPanic`) |
| Crash/restart around the transfer (U4) | not traced (unit `restart.ndjson` covers `Engine::startup` only) | MC only (`CanaryTransferCrash`) — validation gap |
| Lease disable / `touch` interplay | not modeled (time abstracted) | code review only |

## Archived (V0) trace dispositions

All eight V0 traces (`/work/previous/.specula-output/traces/*.ndjson`) were **retained**: the
same scenarios were re-run on the update commit and the fresh files replaced them in `traces/`.
Differences: `accepted_kind` field added; `vote-request` args gain `last_term`/`last_node`.

## Field-consumption controls

`spec/evidence/trace-mutation/README.md`: 11 single-field mutations; 10 FAIL as expected, m8 PASS
as expected (vote guard). Shows the TransferLeader post-state, its args, the VoteRequest
`last_term`, `accepted_kind`, `commands`, and `leader` are compared by active predicates.
