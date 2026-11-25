# Validation handoff (Validation 4) — run `incr-705b7bab5f0d`

- **Source**: `artifact/` HEAD `3ab6cddc34a5bf127747434bb41e20a1b9ef7769`;
  instrumented copy `work-source/` = same HEAD + `harness/instrumentation.patch`
  (test-only). Toolchain from `rust-toolchain` (nightly-2026-03-01).
- **Harness command**: `bash harness/run.sh` (apply, build, run 21 scenarios),
  then `bash harness/validate-traces.sh` (real TLC replay, `TraceConsumed`).
- **Harness provenance**: V0 harness rebased (patch hunk drift in
  `engine/mod.rs`); V0 scenarios kept with identical engine calls; capture fixes
  for `candidate_config` (real frozen quorum) and `seen_greater_log` (real flag).
  V0 patch kept at `harness/patches/v0-instrumentation.patch`.
- **Fresh traces** (all PASS, `TraceConsumed` checked, post-state checks active):
  inventory with hashes, events and logs in `spec/output/trace-inventory.json`;
  summary `spec/output/trace-validation-summary.txt`.
  - V0 regression reruns (7): start_election, reject_stale_log,
    grant_greater_vote, establish_leader, append_joint_membership,
    commit_membership, restart_follower.
  - Update scenarios (14): prevote_elect_multi, prevote_single_voter,
    prevote_req_grant, prevote_req_reject_lease, prevote_req_reject_log,
    prevote_req_reject_vote, prevote_quorum_elect, prevote_reject_greater_log,
    prevote_cleared_by_vote_request, prevote_new_round_same_leader_id,
    candidate_prevote_establish, prevote_stale_member_panic,
    grant_vote_empty_logs, prevote_req_grant_empty_logs.
- **Affected Actions observed**: `PreElect` (multi/single voter, while
  Candidate, while Leader), `SendPreVoteRequests`, `HandlePreVoteRequest`
  (grant, lease/log/vote reject, empty logs), `HandlePreVoteResponse` (grant,
  quorum→elect, greater-log reject, ignored without pre-candidate, panic),
  `DoElect` (`StartElection`). Not traced (runtime timing, reported as limits):
  `TickElect`/`ExternalPreElect` callers (their engine effect is traced), the
  RaftCore leader-id filter (exercised by the integration repro instead).
- **Interactions observed**: candidate→establish with an active pre-candidate
  (`candidate_prevote_establish`), become_following via vote grant and via
  AppendEntries contact, membership evolution between two rounds, lease expiry.
- **Archived V0 traces** (`/work/previous/.specular-output/traces/*.ndjson`):
  disposition *superseded* by fresh reruns of the same scenarios on the new
  source (same engine calls); they lack the new mandatory `pre_candidate_*`
  fields, so they are not replayed against the current `Trace.tla`.
- **Field non-vacuity**: 20/20 single-field mutants rejected
  (`spec/output/trace-mutations/summary.txt`).
- **Semantic spec changes made during validation**: R2 (leader lease after
  establishment) and R1 (absent log ids equal); both followed by full replay of
  the retained suite (21/21 PASS) before model-checking entry.
