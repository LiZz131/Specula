# Validation handoff and fresh trace inventory

- Source: `artifact/` commit `update` 3ab6cddc34a5bf127747434bb41e20a1b9ef7769; instrumented copy `work-source/` (test-only harness module + registration line; plus MC-1 repro tests added after validation)
- Harness command: `harness/run.sh` (apply, build with stable toolchain, run 19 scenarios); validation: `harness/validate-traces.sh`; mutation check: `harness/mutation-check.sh`
- Trace spec: `spec/Trace.tla` + `spec/Trace.cfg` (PROPERTIES TraceConsumed; invariants incl. TypeOK); Category A linear replay, completion evidence = TLC 'No error' after checking temporal properties for the complete state space
- Semantic spec files changed during validation: yes (base.tla lease-on-establish repair; NoLog canonicalization), both recorded in `spec/changelog.md`; final full replay after the last semantic edit: `spec/output/trace-validation-full-run2.log`

| Trace | Origin | Events | Event names | Final replay | sha256 (first 16) |
|---|---|---|---|---|---|
| `start_election` | prior V0 scenario (rerun) | 1 | StartElection | PASS 3 states generated, 2 distinct | 0d1863948fab7cfa |
| `reject_stale_log` | prior V0 scenario (rerun) | 1 | HandleVoteRequest | PASS 3 states generated, 2 distinct | a2688e0c8d817b3f |
| `grant_greater_vote` | prior V0 scenario (rerun) | 1 | HandleVoteRequest | PASS 3 states generated, 2 distinct | 72a8f2ab9e3ef8c4 |
| `establish_leader` | prior V0 scenario (rerun) | 1 | HandleVoteResponse | PASS 3 states generated, 2 distinct | 4b89e46901639b6f |
| `append_joint_membership` | prior V0 scenario (rerun) | 1 | AppendJointConfig | PASS 3 states generated, 2 distinct | 1b79ba2a5f1b9ee7 |
| `commit_membership` | prior V0 scenario (rerun) | 1 | CommitMembership | PASS 3 states generated, 2 distinct | 6ba42c39009f2cbc |
| `restart_follower` | prior V0 scenario (rerun) | 1 | Restart | PASS 3 states generated, 2 distinct | d5e3af5fde6ab692 |
| `pre_elect_multi` | update | 1 | PreElect | PASS 3 states generated, 2 distinct | 0869ee799d22349f |
| `pre_elect_single` | update | 1 | PreElect | PASS 3 states generated, 2 distinct | fbfd7bc2f52afa47 |
| `pre_vote_req_grant` | update | 1 | HandlePreVoteRequest | PASS 3 states generated, 2 distinct | a4d83421d203d64c |
| `pre_vote_req_reject_lease` | update | 1 | HandlePreVoteRequest | PASS 3 states generated, 2 distinct | 0968d2d241553ed3 |
| `pre_vote_req_reject_log` | update | 1 | HandlePreVoteRequest | PASS 3 states generated, 2 distinct | e34edc7628068c2f |
| `pre_vote_req_reject_vote` | update | 1 | HandlePreVoteRequest | PASS 3 states generated, 2 distinct | 42d75fe0e1e6e9c0 |
| `pre_vote_resp_quorum_elect` | update | 3 | PreElect,RunCommands,HandlePreVoteResponse | PASS 5 states generated, 4 distinct | add2a159d8bcb081 |
| `pre_vote_resp_reject_greater_log` | update | 3 | PreElect,RunCommands,HandlePreVoteResponse | PASS 5 states generated, 4 distinct | 8fd6c3286397f970 |
| `pre_vote_resp_joint_no_quorum` | update | 3 | PreElect,RunCommands,HandlePreVoteResponse | PASS 5 states generated, 4 distinct | e12d63e9c34c8071 |
| `stale_pre_vote_after_establish` | update | 5 | PreElect,RunCommands,HandleVoteResponse,RunCommands,HandlePreVoteResponse | PASS 11 states generated, 9 distinct | ee022c763502f5d4 |
| `heartbeat_cancels_pre_vote` | update | 3 | PreElect,RunCommands,HandleAppendEntries | PASS 5 states generated, 4 distinct | 5e6eba19b67c3ada |
| `vote_grant_cancels_pre_vote` | update | 3 | PreElect,RunCommands,HandleVoteRequest | PASS 5 states generated, 4 distinct | 3ba1757f837e79d4 |

## Archived V0 traces

The seven V0 traces in `/work/previous/.specula-output/traces/` are **superseded**: the same seven scenarios were rerun on the updated implementation (rows marked 'prior V0 scenario'). The archived records lack the mandatory Pre-Vote fields (`pre_candidate_*`, `pre_grants`, `send_pre_vote_pending`) required by `Trace.tla` (`EventFieldsPresent`), and the old schema's `candidate_config`/`seen_greater_log` were proxies; they remain immutable evidence of the old run only.

## Field-consumption evidence

`spec/output/trace-mutation-check.log`: 25 single-field mutants across 13 traces (pre-candidate active/vote/config/grants, SendPreVote request vote and targets, pre-vote request grant/reject reasons and response last log, pre-vote response tally/election/greater-log, become_following cancellation, lease after heartbeat/establishment, RunCommands command list, multi-event pre-state) — all REJECTED by TLC.

## Coverage gaps

- `TickElect` (runtime tick guards: lease expiry, single-voter candidate skip, pre-vote mode, fresh-round rate limit) is not traced; engine traces call `pre_elect()`/`elect()` directly. Covered by model checking and the upstream integration tests (`tests --test elect`, 8/8 incl. 6 Pre-Vote tests).
- `RunCommands` emulates the runtime command boundary; storage/network completions are not observed directly (PersistVote/FlushLog/SendVoteRequest are checked only through the next engine state).
- No trace covers Pre-Vote across crash/restart or membership change on the pre-candidate; these interactions are covered by model checking only.
