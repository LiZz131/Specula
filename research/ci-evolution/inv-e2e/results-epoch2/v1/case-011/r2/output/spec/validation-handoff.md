# Validation handoff (Validation 4)

- **Source**: artifact `update` 3ab6cddc34a5bf127747434bb41e20a1b9ef7769 (instrumented copy: `harness/work-source`, a detached git worktree; the artifact tree stays clean).
- **Harness command**: `harness/run.sh` (applies `harness/instrumentation.patch`, builds with `nightly-2026-03-01`, runs 17 scenarios under `timeout`). Build/run log: `spec/output/harness-run.log`.
- **Validation command**: `harness/validate-traces.sh` (real TLC replay, `Trace.cfg`, `PROPERTIES TraceConsumed`, post-state checks active). Summary: `spec/output/trace-validation-summary.tsv`; per-trace logs `spec/output/trace-<name>.log`.
- **Fresh trace inventory**: `spec/trace-inventory.json` (17 traces, 20 events, sha256 per file) — 17/17 PASS.
- **Prior regression**: all 7 V0 scenarios rebuilt and rerun on the update revision; all pass against the updated reference.
- **Archived V0 traces**: `/work/previous/.specular-output/traces/*.ndjson` (immutable) — disposition *superseded by fresh reruns* (same scenarios; the V0 records lack the mandatory Pre-Vote fields required by the current `Trace.tla`). V0 logs are kept in `spec/output/prior-v0/`.
- **Affected Actions observed**: `PreElect` (follower, single voter, Candidate context), `HandlePreVoteRequest` (grant, lease reject, log reject, empty-log grant), `HandlePreVoteResponseElect`, `HandlePreVoteResponseReject`; `DoElect` via `StartElection` and via the Pre-Vote quorum.
  Not observed in a trace (model-checked only, reachable by canaries): `HandlePreVoteResponseTally` (needs >= 4 voters for a non-final grant with the self grant), `HandlePreVoteResponseStale` (runtime filter is not an engine boundary), the tick/flag branch (runtime timer).
- **Interaction Scenarios observed**: Candidate -> PreElect -> HandleVoteResponse(win) -> HandlePreVoteResponseElect (`pre_vote_after_establish`); PreElect -> HandleVoteRequest(follow drops the round) (`pre_candidate_cleared_by_vote`).
- **Field checks**: every mandatory field is compared by `ValidatePost`/`TracePreElect`/`TraceHandlePreVoteRequest`; 6/6 field mutations rejected (`spec/evidence/trace-mutations/summary.txt`).
- **Semantic spec files changed by validation**: yes — `HandleVoteResponse` lease repair (Round 1) and `LogLE` repair (Round 2); both trace-required (`spec/evidence/repair-lease`, `spec/evidence/repair-logle`). The full regression was rerun after the last repair (Round 3).
