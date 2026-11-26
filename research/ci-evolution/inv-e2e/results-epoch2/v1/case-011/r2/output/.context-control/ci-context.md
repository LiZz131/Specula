# CI context handoff — incr-315482ff25a1 (case-011, OpenRaft Pre-Vote update)

## Identity
- Source: artifact `update` 3ab6cdd (old `baseline` 1adc857). Instrumented worktree: harness/work-source (detached, patch applied + MC-1 repro changes in tests/).
- Disposition: MODEL_CHANGE_REQUIRED -> final JSON decision MODEL_UPDATED.

## Done
- Generation: base/MC/Trace updated (pre-candidate vars, PreVote msgs, PreElect/TickPreElect/ExternalPreElect, HandlePreVoteRequest, HandlePreVoteResponse{Elect,Tally,Reject,Stale}, DoElect). Update.tla + cfgs (full/focused/open/discharge x2/hunt/canaries/continue).
- Repairs (V0 defects): HandleVoteResponse lease on win/adopt; LogLE absent logs equal (V0 3-voter MC could never elect). Evidence: spec/evidence/repair-*/.
- Validation: 17/17 fresh traces pass (spec/output/trace-validation-summary.tsv); 6/6 mutations rejected.
- Divergence evidence: spec/invariant-evidence.json, spec/evidence/divergence/.
- MC: canaries 6/6 violated (reachable). MC-1 found: Update_full.cfg PreVoteElectionPremiseCurrent (spec/output/MC-1_update_full_PreVoteElectionPremiseCurrent.out). Focused reproduces it.
- Open run1: DurableLogNotAhead = EnvUpdate artifact (rely allowed lower-leader append) -> rely tightened (grow => LogLT), open + discharge restarted.
- Repro: REPRODUCED (Level 1) spec/confirmation-MC-1.md, spec/repro/*. Debug: RaftCore panics at engine_impl.rs:977 debug_assert; release: leader -> Candidate term 3.
- Docs written: modeling-brief (U section), analysis-report (U section), instrumentation-spec, harness/INSTRUMENTATION.md, README, brief-coverage, changelog (partial).

## Pending
- Wait: MC-standard (30m, budget-limited), update-full-continue, update-open (rerun), discharge (2 seeds), hunt-stale-round. Then MC-membership.cfg rerun, simulations for non-exhausted BFS (MC.cfg, Update_full_continue).
- Write: bug-report.md, findings.json, validation handoff/validation-summary.json, final changelog Result, final-result.json (MC-1 REPRODUCED; CR-1 doc mismatch D-U2 as FALSE POSITIVE/doc-only), run `specular ci-result`, final-response.json.
- Cleanup: remove /dev/shm state dirs, kill no background processes left; `git -C artifact worktree remove` work-source? (keep patch + repro script; artifact must stay clean at `update`).

## Update (04:07 UTC)
- Round 4: HandlePreVoteResponseNonMember repair (grant_by expect panic); EnvUpdate rely v2 (monotone log) and v3 (leader-only config change). Traces 17/17 after repair.
- MC-2 found (Update_hunt_stale_membership.cfg, 15 states; also leader hunt) + reproduced (spec/confirmation-MC-2.md; repro logs MC-2-repro-*). MC-1 re-found on final suite (11 states).
- Final BFS (no violation, budget-limited): MC.cfg 8.46M/d17, MC-membership 2.47M/d19, full_continue 5.47M/d15, focused_continue 3.76M/d13. Pending at 04:07: open_continue(v3), discharge x2 (v3) ~04:09; sims: MC (to ~04:20), full_continue, focused_continue, MC-membership (to ~04:37); then open_continue sim.
- final-result.json drafted (MC-1, MC-2 REPRODUCED; CR-1 FALSE POSITIVE); ci-result ran OK (FAIL verdict). Remaining: validation_limits, model-checking-summary.md, bug-report Not Reproduced table, brief-coverage U-5, changelog Result, final ci-result, final-response.json, cleanup (/dev/shm, worktree, processes).
