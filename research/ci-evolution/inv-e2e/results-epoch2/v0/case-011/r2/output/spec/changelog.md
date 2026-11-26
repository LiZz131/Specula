# Changelog — incremental run incr-b919e9f909ea (Pre-Vote update)

Prior suite: `/work/previous/.specular-output` (V0, no changelog). Source: `artifact/` HEAD `3ab6cdd` (`update`).

## Round 0 - Generation (MODEL_CHANGE_REQUIRED)
- [update] base.tla: constant `PreVoteSetting`; variables `preCandidateActive/Vote/Config`, `preGrants`; message kinds `PreVoteReq`/`PreVoteResp`; `ElectEffect` factored out of `StartElection` (clears the pre-candidate, keeps Leader object as `do_elect` does); new `PreElect`, `TickPreElect`, `ExternalPreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`; `TickElect` gated by `PreVoteSetting`/voter count; pre-candidate cleared by `become_following` paths (`HandleVoteRequest`, `HandleVoteResponse` adopt, `HandleAppendEntries`, `RefreshServerState`) and `Restart`; kept by `establish_leader`.
- [update] MC.tla: `MCTickPreElect`, `MCExternalPreElect`, counters `preElect`/`env`, `AllowAdminElect`; reactive groups.
- [update] Update.tla: Affected/Interaction actions, `EnvUpdate` rely, `DischargeEnv`, properties `LeaderVoteCoversLocalVote`, `PreCandidateTracksNextTerm`, `PreVoteStepIsSideEffectFree`, reachability canaries; cfgs full/focused/open/discharge/control/toggle/canaries.
- [update] Trace.tla/Trace.cfg: new fields and events (`PreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`, `RuntimeDrain`), pre-state validation, continuity assumption.
- Preflight: SANY clean for base/MC/Update/Trace (`output/*-sany.log`); VAV clean on base.tla (run on a copy with tuple-literal aliases stubbed because the VAV tool rejects them).

## Round 1 - Trace Validation
- [harness] Prior patch failed to apply (`engine/mod.rs` context drift: new `pre_elect_test` modules). Rebased: same engine-level test module, renamed, new fields, 11 update scenarios; `seen_greater_log` now real.
- [fix] Trace.tla: `ValidatePre` was evaluated after silent `RuntimeDrain` steps; restricted to non-drain events plus `TraceContinuity` assumption (Trace: candidate_prevote_then_leader.ndjson).
- [fix-spec][repair-prior] HandleVoteResponse: establishment installs the leader lease (`update_vote` with committed vote → `vote.update(now, leader_lease, ..)`); adopt installs a zero lease. Prior fixture masked it (Trace: candidate_prevote_then_leader.ndjson).
- Result: 18/18 fresh traces PASS (`output/trace-validation-summary-gate1.tsv` before the LogLE repair re-run, see Round 2).

## Round 2 - Reachability / Model Checking
- [fix-spec][repair-prior] LogLE: two absent logs are equal (`Option::None == None`); the prior made them incomparable so no vote between empty-log nodes could be granted and multi-voter elections from Init were unreachable. Found by canaries `CanaryPreVoteGranted`, `CanaryElectedViaPreVote`, etc. being unreachable.
- Full trace regression re-run after the repair: 18/18 PASS; 14/14 negative controls rejected.
- [bug] HandlePreVoteResponse/HandleVoteResponse (U3): `Update!LeaderVoteCoversLocalVote` violated in `Update.cfg` (15 states, `output/MC-1-counterexample-update-full.log`) and fault-free in `Update-nofault.cfg` (14 states, `output/update-nofault.log`). A Candidate's Pre-Vote round survives `establish_leader`; the delayed granted Pre-Vote response makes the established Leader call `elect()`. Case C (model faithful at every step; same state reached by the real Engine in `traces/candidate_prevote_then_leader.ndjson`, `output/trace-update-property-candidate_prevote_then_leader.log`). Control `Update-control-off.cfg` (Pre-Vote disabled) — see Result.
- [fix-env] Update.tla EnvUpdate (open view only): the first constructive rely let a restarted node append a membership entry under an older vote than its existing last log (`update-open-residual-v1-weak-rely.log`, `DurableLogNotAhead`, 10 states). Real omitted context (leader-only append) appends under the current vote, which is ≥ the last log id; added `LogLT(lastLog[i], Log(vote[i].term, vote[i].node, idx+1))`. Case B for the open view (rely too weak), not a finding; discharge re-run against the strengthened rely.
- [harness] Update-open*.cfg first launch failed at startup (rely written relationally; TLC cannot generate from it) — rewritten constructively (`update-open*-startup-error.log`).
- [ops] Four batch-1 runs were killed by the agent tool's 10-minute background limit (`*-interrupted.log`); all were re-run to their full 30-minute budget.

## Round 3 - Regression / confirmation
- [regression-check] With both prior-model repairs reverted in a scratch copy (`regression-prior-equivalence/`) and Pre-Vote disabled, MC reproduces the prior exhaustive graph exactly: 5,273,983 generated, 640,830 distinct, depth 24 (`output/regression-prior-equivalence.log`).
- [bug-confirmed] MC-1 REPRODUCED through the real Raft API (Level 1 public API; Level 3 timer path with slow test-storage `save_vote`), 3/3, controls clean (`confirmation-MC-1.md`).
- [code-review] CR-1 documentation mismatch (`pre_vote.md` vs. transport-error handling) — FALSE POSITIVE for protocol behavior (`confirmation-CR-1.md`).

## Fresh trace inventory (final, against the final base/MC/Trace)
18 traces in `traces/` (7 prior scenarios rerun + 11 update scenarios), all PASS with completed `TraceConsumed` checks (`output/trace-validation-summary.tsv`, per-trace logs `output/trace-<name>.log`); 15 one-field negative controls rejected (`output/negative-controls/summary.tsv`).
Archived V0 traces (`/work/previous/.specular-output/traces/*.ndjson`, 7 files): retained as old-version evidence; superseded by fresh reruns of the same scenarios on the new implementation; not replayed against the new Trace.tla because they lack the now-mandatory pre-candidate/leader-vote fields.

## Result
Converged: trace validation passes on the final reference; model-checking campaigns all executed (budget-limited, LIMITED_COVERAGE); one real bug (MC-1, Case C) found and reproduced; no unresolved Case A/B.

## Round 4 - Simulation follow-ups
- Simulations (depth 60, 30 min) for MC.cfg, Update-residual, Update-focused-residual, Update-toggle, Update-discharge: no violation (budget-limited).
- [ops] Update-open*/simulate first stopped on *deadlock* (`update-open*-sim-deadlock-bounded-env.log`): bounded-rely quiescence (every node has an outstanding env-appended membership entry and the env counter is exhausted, so neither commit nor refresh is enabled). Not a property under test and impossible in full MCSpec (CommitMembership is unbounded there); re-run with `-deadlock` (safety checks unchanged).
