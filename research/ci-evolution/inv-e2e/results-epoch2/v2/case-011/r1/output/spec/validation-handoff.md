# Validation handoff (incremental Pre-Vote run)

- Source: artifact HEAD `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` (`update`), built from `harness/work/source-new` (git archive of HEAD + test-only instrumentation).
- Harness command: `bash harness/run.sh` (stable rustc 1.100.0); validation: `bash harness/validate-traces.sh`; field consumption: `bash harness/field-consumption.sh`.
- Final full regression on the stable candidate: `spec/output/trace-validation-round5.log` (23/23 PASS) after the last semantic repair (RefreshServerState); per-trace logs `spec/output/trace-<name>.log` (each: TLC `Model checking completed. No error has been found.` plus `Checking temporal properties for the complete state space` for `TraceConsumed`).
- Field consumption: 20 single-field mutants of fresh traces, all rejected (`spec/output/field-consumption-summary.log`, mutants and logs in `spec/output/field-consumption/`).
- Semantic spec files changed during validation: yes (`HandleVoteResponse` leader lease, `LogLE` absent logs, `RefreshServerState` leading case; `spec/changelog.md`). All three are V0 defects present in both revisions.

## Fresh trace inventory

| Trace | Events | Event sequence | Kind | Result | Distinct states |
|---|---|---|---|---|---|
| `append_joint_membership` | 1 | AppendJointConfig | V0 regression | PASS | 2 |
| `commit_membership` | 1 | CommitMembership | V0 regression | PASS | 2 |
| `establish_leader` | 1 | HandleVoteResponse | V0 regression | PASS | 2 |
| `grant_greater_vote` | 1 | HandleVoteRequest | V0 regression | PASS | 2 |
| `grant_vote_empty_logs` | 1 | HandleVoteRequest | update | PASS | 2 |
| `prevote_cleared_by_heartbeat` | 2 | StartPreVote → HandleAppendEntries | update | PASS | 3 |
| `prevote_cleared_by_higher_vote_resp` | 4 | StartElection → HandleVoteResponse → StartPreVote → HandleVoteResponse | update | PASS | 10 |
| `prevote_cleared_by_vote_grant` | 2 | StartPreVote → HandleVoteRequest | update | PASS | 3 |
| `prevote_joint_grant_then_elect` | 3 | StartPreVote → HandlePreVoteResponse → HandlePreVoteResponse | update | PASS | 4 |
| `prevote_req_grant` | 1 | HandlePreVoteRequest | update | PASS | 2 |
| `prevote_req_grant_empty_logs` | 1 | HandlePreVoteRequest | update | PASS | 2 |
| `prevote_req_reject_lease` | 1 | HandlePreVoteRequest | update | PASS | 2 |
| `prevote_req_reject_log` | 1 | HandlePreVoteRequest | update | PASS | 2 |
| `prevote_req_reject_vote` | 1 | HandlePreVoteRequest | update | PASS | 2 |
| `prevote_resp_quorum_elect` | 4 | StartPreVote → HandlePreVoteResponse → HandleVoteResponse → HandlePreVoteResponse | update | PASS | 10 |
| `prevote_resp_reject_greater_log` | 2 | StartPreVote → HandlePreVoteResponse | update | PASS | 3 |
| `prevote_single_voter` | 1 | StartPreVote | update | PASS | 2 |
| `prevote_start` | 1 | StartPreVote | update | PASS | 2 |
| `prevote_tick_start` | 1 | StartPreVote | update | PASS | 2 |
| `reject_stale_log` | 1 | HandleVoteRequest | V0 regression | PASS | 2 |
| `restart_follower` | 1 | Restart | V0 regression | PASS | 2 |
| `stale_prevote_after_win` | 5 | StartElection → HandleVoteResponse → StartPreVote → HandleVoteResponse → HandlePreVoteResponse | update | PASS | 14 |
| `start_election` | 1 | StartElection | V0 regression | PASS | 2 |

## Archived V0 traces

The seven V0 traces (`/work/previous/.specula-output/traces/*.ndjson`, immutable) are **superseded** by fresh regenerations of the same scenarios on the updated implementation: they lack the mandatory update fields (`pre_candidate_*`, `pre_grants`, `send_pre_vote_pending`) and carried a hard-coded `seen_greater_log: false`, which `Trace.tla` now requires and compares. No archived trace crosses removed behavior.

## Affected-Action and interaction coverage

| Model action / branch | Fresh trace(s) |
|---|---|
| `ExternalPreElect` (`PreElect` round branch) | prevote_start, prevote_resp_*, prevote_joint_*, prevote_cleared_* |
| `TickPreVote` (incl. seen_greater_log reset; on a Candidate) | prevote_tick_start, stale_prevote_after_win, prevote_cleared_by_higher_vote_resp |
| `PreElect` single-voter quorum branch → `DoElect` | prevote_single_voter |
| `HandlePreVoteRequest` grant / reject-lease / reject-log / reject-vote / empty logs | prevote_req_grant, _reject_lease, _reject_log, _reject_vote, _grant_empty_logs |
| `HandlePreVoteResponseGrant` (no quorum, joint config) | prevote_joint_grant_then_elect (event 2) |
| `HandlePreVoteResponseElect` (follower) | prevote_resp_quorum_elect, prevote_joint_grant_then_elect |
| `HandlePreVoteResponseElect` (on an established Leader, U2) | stale_prevote_after_win (event 5) |
| `HandlePreVoteResponseReject` (greater log) | prevote_resp_reject_greater_log |
| `HandlePreVoteResponseIgnored` (round already finished) | prevote_resp_quorum_elect (event 4) |
| become_following clears the round: AppendEntries / real vote grant / higher vote response | prevote_cleared_by_heartbeat, prevote_cleared_by_vote_grant, prevote_cleared_by_higher_vote_resp |
| `HandleVoteResponse` wins keeps the round (establish_leader) | stale_prevote_after_win (event 4) |
| `PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast`, `FlushLog` (silent runtime steps) | multi-event update traces |

Not observed in a fresh trace (model-checking only, with reason): `DefaultPreVoteRpcGrant` (network layer, not an engine call), `RefreshServerState` clearing a round (requires a committed membership change on a node holding a round; MC hunts), `Restart` clearing a round (a reconstructed Engine trivially has `pre_candidate: None`; V0 restart trace retained), `AppendUniformConfig`, `SendAppendEntries`, `ExpireLease`, `DropMessage`, `Crash` (unchanged V0 limits).

## Code observations (Divergence Evidence §6)

- Real RaftCore runtime: `harness/repro/t13_specula_stale_prevote_repro.rs`, log `spec/output/repro-MC-1-new.log`: with a Pre-Vote round started while the real vote RPC is in flight, node 1 wins term 2 and its RaftCore then panics at `engine_impl.rs:977` (`leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)`); the control without the Pre-Vote trigger keeps node 1 Leader at term 2 with a live core.
- Integration suites on the updated source: elect 8/8 (incl. 6 Pre-Vote tests), membership 44/44, life_cycle 14/14; library 486/486 (`spec/output/baseline-new-*.log`).
