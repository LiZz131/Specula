# v0 / case-003 census notes

- The census sub-agent for v0 002-006 wrote the probes and ran the census for this case but stalled
  before writing items; the coordinating agent classified from `runs/v0/case-003/result.json` and the
  probe comments (quotes from modeling-brief.md:180-183, the agent's U1-U4 table).
- 15 Update cfgs probed (module Update); positive control SC_CTRL_accepted reached in all.
- All 8 scenario items were reached by census in cfgs that run their properties (brief §8.3 mapping).
  U3b (move a future enable height) was not seen in Update_full/focused/open (and their _safety twins)
  in 360 s, but was reached in the U1/U3/U5/sim hunts, which run VEEnableHeightImmutableOnceEnabled and
  VEStatusOfDecidedHeightsPreserved.
- Property intents (P-U1..P-U4, brief §8.3) name the same situations as U1-U4 and were not itemised
  separately. Agent canary logs were not checked (every item was measured directly).
- Dismissals were collected by grep for exclusion / argued-not-modeled wording; may be incomplete.
