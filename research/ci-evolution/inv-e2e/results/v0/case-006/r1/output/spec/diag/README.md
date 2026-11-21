# Diagnostic only (not a campaign, not evidence of search coverage)

`PathCheck.tla` drives MCSpec (via the MC wrappers of Update.tla) along a
hand-derived 38-step S6b schedule to locate why a bounded BFS had not found
it. Result: every step is enabled and TLC reports `UpdReadIndexLinearizable`
violated at the end (`pathcheck.log`, `pathcheck-v2.log` under
`S6GuideConstraint`/`S6GuideConstraintV2`). This showed the earlier miss was a
search artifact of `VIEW MCView` (fault counters excluded). The `.tla` files
here are copies of `../` at diagnosis time.
