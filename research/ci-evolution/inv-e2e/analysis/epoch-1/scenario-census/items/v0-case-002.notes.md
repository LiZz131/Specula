# v0/case-002 census notes
- Items: Update Scenarios U-NPE, U-DUR, U-EPOCH (split crash/non-crash), U-LOSS (split INITIAL-exit/crash) from output/modeling-brief.md:28-62.
- Property intents in Update.tla (U-P1..U-P5, lines 122-157) name the same situations as the scenarios; not listed separately.
  CommittedNeverLost (U-P4) shares U-LOSS; agent notes it was never violated (brief-coverage.md).
- Check statement output/spec/bug-report.md:127 (loss with crashes not reached) merged into U-LOSS-b.
- CR-1 (shutdown from INITIAL no-op) is folded by the agent into MC-3 (= U-EPOCH-b/U-LOSS-a); not a separate item.
- V0 scenarios 1-4 (prior brief appendix) skipped: not update scenarios.
- Cfgs probed (all run on Update.tla as in the agent's run-tlc.sh ledger): Update-full, Update-focused, Update-open,
  Update-hunt-loss-crash, Update-hunt-loss-crash-tight (first pass, result.json) and Update-hunt-npe, -dur, -epoch,
  -epoch-nocrash, -loss-tight (second --only pass).
- RUNNER ERROR: the --only pass crashed at run_census.py:153 (TypeError: result.json is loaded as the whole document,
  not its "configs" map), so result.json holds only the first five cfgs. The --only results are in
  runs/v0/case-002/only-hunts.stdout and logs/Update-hunt-*.seed{1,2}.log. run_census.py was not modified.
- Positive control SC_CTRL_leader reached in every cfg.
- Census simulation (depth 100, 120 s + 240 s retry, 1 worker) is weak for this model: traces average ~91 steps and the
  agent's own U-EPOCH/U-LOSS violations needed guided BFS at depth 30-49. Census "no" here means not seen in budget.
- Covered verdicts for U-EPOCH-a/b and U-LOSS-a rest on the agent's own violations in guided hunt cfgs that run the
  related property, not on census reach.
- U-LOSS-b is Q-a: neither the agent (budget-limited BFS, depth 38) nor the census reached it.
- Agent BFS runs of Update-full/focused/open were budget-limited (queue non-empty), see output/spec/bug-report.md:122-126.
- Coordinator: after the --only merge bug was fixed, the five hunt cfgs were rerun (120 s + 240 s); result.json now holds all 10 cfgs, with the same reach as only-hunts.stdout.
