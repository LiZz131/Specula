# v0 / case-006 census notes

- Probes were written by the stalled census sub-agent; the coordinating agent ran
  `run_census.py v0 case-006 --jobs 7` and classified.
- Cfgs: Update_full/focused/open, MC_hunt_s6_stale_ack, MC_hunt_s6_linearizable(_guided_noview,_guided_v2).
  Update_open.cfg was a dead run (about 2k traces, not even the positive control reached); recorded as
  "not seen", and no item depends on it alone.
- S6b2 (MC-Q2, read index below a newer leader's commit): census never reached the precondition; covered
  through the agent's BFS violation of UpdReadIndexLinearizable in MC_hunt_s6_linearizable_guided_v2.cfg.
  The guided cfg uses a steering constraint; the unguided hunts were budget-limited.
- The sub-agent's SC_S6b_stale_read_released probe encodes the violation itself, not a precondition,
  and was not itemised.
