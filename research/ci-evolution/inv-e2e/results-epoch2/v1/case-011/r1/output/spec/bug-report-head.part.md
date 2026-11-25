# Bug Report — OpenRaft election with Pre-Vote (case-011, artifact 3ab6cdd)

## Summary

- Disposition: MODEL_CHANGE_REQUIRED (Pre-Vote phase added); reference suite updated, `Update.tla` generated.
- Scenarios tested: V0 Scenarios 1–5 (standard rounds) and update Scenarios U-S1…U-S6.
- Bugs found (Case C, model checking): **2** — MC-1 (Pre-Vote livelock, High), MC-2 (stale Pre-Vote round demotes a new leader, Medium).
- No reference safety invariant (persistence ordering, role/vote consistency, frozen joint quorum, membership staging) was violated in any campaign.
- Both findings are update-introduced: they need Pre-Vote (`enable_pre_vote` or `trigger().elect(true)`), which does not exist in the baseline. Their mechanisms were observed on the real `Engine` (validated traces and `spec/output/observations.log`); the full multi-node schedules were not replayed on the real runtime (Part 4 reproduction not executed in this run).
- All model checking is bounded (`LIMITED_COVERAGE`): 3 nodes, small term/log/message bounds, 30-minute budgets; not a proof.

