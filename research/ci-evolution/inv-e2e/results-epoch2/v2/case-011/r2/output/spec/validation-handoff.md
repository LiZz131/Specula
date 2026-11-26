# Validation handoff — incremental run incr-4e410cd184be

- **Source**: artifact HEAD `3ab6cdd` (`update`); harness work copy
  `.specular-output/work/source` = `git archive` of that HEAD + `harness/instrumentation.patch`.
- **Toolchain**: nightly-2026-03-01 (repository `rust-toolchain`).
- **Harness command**: `harness/run.sh` (apply, build, 17 scenarios, event-count checks);
  log `spec/output/harness-run.log`.
- **Prior harness reuse**: the V0 patch failed to apply only because of context
  drift in `openraft/src/engine/mod.rs` (new pre-vote test modules); the V0 test
  module was carried over (specula->specular rename, `caller` argument, real
  `seen_greater_log` instead of a hard-coded `false`), and update scenarios
  were added to the same module.

## Fresh trace inventory (all new-version, all PASS with TraceConsumed)

| Trace | Events | Kind | Affected / interaction actions |
|---|---|---|---|
| start_election | 1 | prior regression | ExternalElect (ElectEffects clears round) |
| reject_stale_log | 1 | prior regression | HandleVoteRequest (reject) |
| grant_greater_vote | 1 | prior regression | HandleVoteRequest (grant, become_following) |
| establish_leader | 1 | prior regression | HandleVoteResponse (win) |
| append_joint_membership | 1 | prior regression | AppendJointConfig |
| commit_membership | 1 | prior regression | CommitMembership |
| restart_follower | 1 | prior regression | Restart |
| pre_elect_multi | 1 | update | ExternalPreElect (round created) |
| pre_elect_single_voter | 1 | update | ExternalPreElect (self quorum -> ElectEffects) |
| pre_vote_req_grant | 1 | update | HandlePreVoteRequest (grant, no state change) |
| pre_vote_req_lease_reject | 1 | update | HandlePreVoteRequest (lease reject) |
| pre_vote_req_stale_log | 1 | update | HandlePreVoteRequest (log reject) |
| pre_vote_resp_quorum | 2 | update | ExternalPreElect -> HandlePreVoteResponse (win -> ElectEffects) |
| pre_vote_resp_reject_greater_log | 2 | update | HandlePreVoteResponse (reject, seen_greater_log) |
| pre_vote_resp_no_round | 1 | update | HandlePreVoteResponse (no round) |
| pre_vote_cleared_by_vote_request | 2 | update/interaction | ExternalPreElect -> HandleVoteRequest (become_following clears round) |
| stale_pre_vote_after_leader | 5 | update/interaction (U1) | ExternalElect, HandleVoteResponse (self), TickPreElect, HandleVoteResponse (win), HandlePreVoteResponse (win from Leader) + silent PersistVote/SendVote/FlushLog |

Summary log: `spec/output/trace-validation-summary.log`; per-trace logs
`spec/output/trace-<name>.log`. Negative controls: `spec/output/trace-mutation-controls.log`
(12/12 rejected).

## Archived-trace dispositions

The seven V0 traces (`traces/archived-v0/`) are exact-old evidence; each
scenario was re-run on the new implementation and its fresh trace is retained
above (disposition: superseded by fresh rerun). The archived files use the old
event shape (no pre-candidate fields) and are not replayed against the updated
Trace.tla.

## Coverage and gaps

- Every Affected Action is observed in a fresh trace except
  `NetworkDefaultPreVote` (environment behaviour of the network trait default,
  not an Engine transition) and `StartTransferElection` (prior gap).
- U3/U4 (membership change while a round is in flight) cannot be captured by the
  engine-level harness because the frozen quorum set is private; they are
  covered by model checking and runtime reproductions.
- Effects compared by active Trace predicates: vote, role, candidate/leader
  flags, pre-candidate vote/grants/config, pending SaveVote/SendVote/AppendEntries,
  SendPreVote request contents, seen_greater_log, response vote/granted/last log.

## Semantic spec changes made during validation

Two prior-model defects repaired (see `spec/changelog.md` Round 1): leader lease
on establishment and empty-log comparison. The full fresh suite and the mutation
controls were re-run after both repairs (all pass / all rejected).

## Baseline tests on the updated revision

`work/repro` (artifact HEAD + reproduction patch, test-only):
`timeout 25m cargo test -p openraft --lib` -> 486 passed
(`spec/output/baseline-new-openraft-lib.log`);
`timeout 20m cargo test -p tests --test elect -- --skip t90_specular` -> 8 passed,
including all six `t12_pre_vote` tests (`spec/output/baseline-new-elect.log`).
The existing tests do not exercise MC-1..MC-3.

Prior-run logs seeded into `spec/output/` were moved to `spec/output/prior-v0/`
(the immutable originals remain in `/work/previous/.specular-output`).
