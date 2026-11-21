# Validation handoff (V1 incremental run)

- Source under test: `artifact/` commit `update`
  3ab6cddc34a5bf127747434bb41e20a1b9ef7769; instrumented copy `work-source/`
  (same commit + `harness/instrumentation.patch`, test-only).
- Harness command: `harness/run.sh` (log `spec/output/v1-harness-run.log`),
  build log `spec/output/v1-harness-build.log`; toolchain `stable` 1.100.0.
- Trace validation command: `harness/validate-traces.sh` (TLC `Trace.cfg`,
  property `TraceConsumed`, invariants incl. `TraceTypeOK`), per-trace logs
  `spec/output/v1-trace-<case>.log`, summary `spec/output/v1-trace-summary.txt`.
- Final full regression (after the last semantic repair, LogLE, and after adding
  the joint-accumulation scenario): 20/20 PASS.
- Non-vacuity: 11 single-field mutants rejected
  (`spec/output/v1-trace-mutation-controls.txt`); each event is checked
  against its recorded pre-state and post-state.

## Fresh trace inventory (new version)

| Trace | Records | Kind | Affected / interaction actions observed |
|---|---|---|---|
| start_election | 1 | V0 regression | StartElection (DoElect) |
| reject_stale_log | 1 | V0 regression | HandleVoteRequest (log reject) |
| grant_greater_vote | 1 | V0 regression | HandleVoteRequest (grant, become_following) |
| establish_leader | 1 | V0 regression | HandleVoteResponse (wins) |
| append_joint_membership | 1 | V0 regression | AppendJointConfig |
| commit_membership | 1 | V0 regression | CommitMembership |
| restart_follower | 1 | V0 regression | Restart |
| pre_vote_req_grant | 1 | U-S1 | HandlePreVoteRequest (grant, pure) |
| pre_vote_req_reject_lease | 1 | U-S1 | HandlePreVoteRequest (lease, no transfer bypass) |
| pre_vote_req_reject_log | 1 | U-S1 | HandlePreVoteRequest (log) |
| pre_vote_req_reject_vote | 1 | U-S1 | HandlePreVoteRequest (vote order) |
| pre_elect_multi | 1 | U-S2 | PreElect (round, SendPreVote) |
| pre_elect_single | 1 | U-S2 | PreElect (self quorum -> DoElect) |
| pre_vote_resp_quorum | 3 | U-S2 | PreElect, [SendPreVoteRequest], HandlePreVoteResponse (quorum -> DoElect), [PersistVote], HandleVoteResponse |
| pre_vote_resp_joint_accumulate | 3 | U-S2 | PreElect (joint config), HandlePreVoteResponse (grant accumulated without quorum), HandlePreVoteResponse (joint quorum -> DoElect) |
| pre_vote_resp_reject_greater_log | 2 | U-S2 | PreElect, HandlePreVoteResponse (reject, seen_greater_log) |
| pre_vote_superseded_by_vote_req | 3 | U-S3 | PreElect, HandleVoteRequest (clears), HandlePreVoteResponse (dropped) |
| pre_vote_superseded_by_append | 2 | U-S3 | PreElect, HandleAppendEntries (clears) |
| pre_vote_superseded_by_elect | 2 | U-S3 | PreElect, StartElection (clears) |
| candidate_pre_vote_then_leader | 5 | U-S4 | StartElection, HandleVoteResponse, PreElect (as Candidate), HandleVoteResponse (wins, round kept), HandlePreVoteResponse (elect on Leader) |

Bracketed actions are replayed as guarded silent runtime steps.

## Archived V0 traces

`traces/archive-v0/*.ndjson` (7 files, exact-old) are retained unchanged as
prior evidence. Disposition: superseded by the fresh reruns of the same seven
scenarios on the new implementation (the V1 schema adds mandatory
pre-candidate and real `seen_greater_log` fields, which V0 records lack).

## Coverage gaps

Not observed in fresh traces: tick decision/rate limiting and runtime
response correlation in RaftCore (harness applies the same rule), clearing
via `RefreshServerState` and `Restart`, `TickPreElect`'s
`seen_greater_log` reset, RPC errors. These are covered by model checking
and code reading only. The six `t12_pre_vote` integration tests pass on the
new tree (`spec/output/v1-baseline-elect.log`); 486 OpenRaft library tests pass
(`spec/output/v1-baseline-openraft-lib.log`).

## Semantic spec changes made during validation

LogLE absent-log equality and establishment lease (prior-model defects), both
recorded in `spec/changelog.md`; every retained trace was re-validated after
the last change.
