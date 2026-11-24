# v2 / case-012 census notes

- Inventory, probes (`probes/v2/case-012/`) and dismissals were written by the census sub-agent; it ran
  out of context before classifying, so the coordinating agent wrote the items CSV from the sub-agent's
  probe comments (quotes and sources) and `runs/v2/case-012/result.json`.
- Cfgs probed (11): Update_full, Update_focused, Update_open, MC_hunt_u1/u2/u3/s1/s2 (module Update),
  MC_hunt_s3/s4, MC_scale (module MC). Positive control SC_PC (some leader) reached in all 11.
  Census = simulation, depth 100, 120 s seed 1 + 240 s seed 2, 8k-32k traces per cfg.
- Related checks per item are the properties the brief names for the scenario; a cfg counts if it
  enables any of them.
- US2a: census never saw it; covered through the agent's canary MC_reach_u2_reelection.cfg, whose
  behaviour sections equal MC_hunt_u2_reelection.cfg's (checked by diff).
- US3: Q-a, not seen in budget. The agent's 30-min BFS of the canary cfg (same behaviour as
  MC_hunt_u3) stopped with 4.08M states on queue at depth 17; the agent itself states it was not reached.
- C2a/C2b: Q-a, agent-acknowledged coverage limits (bug-report.md:61). The agent's explanation (first
  AppendEntries of a leadership has prev = None) was not verified; no structural proof, so "not seen".
- Weaker probes (inferred): US1a (state after the append-time commit, not the step), US2b (global crash counter).
