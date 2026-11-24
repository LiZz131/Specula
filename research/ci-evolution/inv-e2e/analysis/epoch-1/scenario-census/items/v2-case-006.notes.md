# v2 / case-006 census notes (etcd raft readOnly.advance frees released reads)

- Items: Scenarios U1-U4 of output/modeling-brief.md section 8. U2 split into re-registration (U2a), stale
  earlier ack counted (U2b), same context released twice (U2c, the agent's HuntReuseServed canary); U4 split
  into forwarded read responses around freed entries (U4a) and leader step-down / term change recreating
  readOnly (U4b). The four Upd* property intents name the same situations as U1/U2b/U3/U4b and were folded into
  them. Model repairs R1-R3 are not scenarios; findings MC-U1/MC-U2 = U2b/U3 violations.
- cfgs probed (12): every Update_* cfg that enables an Upd* property (focused/full/open and their *_rest
  variants, hunt_forwarded(_rest), hunt_linearizable, hunt_linearizable_directed, hunt_stale_ack) on
  Update.tla, plus MC.cfg (ReadDeliveryJustified, related to U4). Skipped: Reach_* and MC_hunt_s* canary
  cfgs, MC_complete_core, Update_discharge, Trace*, base.cfg.
- Agent canaries counted: Reach_update_{freed,reuse,reuse_served,stale_ack,forwarded_freed}.cfg have the same
  CONSTANTS / SPECIFICATION FocusedSpec / CONSTRAINT / SYMMETRY as Update_hunt_stale_ack.cfg (only VIEW MCView
  differs, which does not define behaviour). Reach_update_leader_stepdown.cfg (MaxReadLimit 1,
  MaxQuorumCheckLimit 2) matches no property cfg and was not counted.
- Runner: 120 s + 240 s retry, depth 100, --jobs 3, no errors. A second pass (--only on 6 cfgs, merged into
  result.json) added SC_U4b2 after SC_U4b (the agent's canary wording: step-down within the same term) was
  not seen in any cfg in 360 s. SC_U4b2 encodes the brief's full wording "step down or change term" and was
  reached in Update_full/focused/open/full_rest.
- MC.cfg reached nothing, not even the positive control (a served read) in 360 s of simulation; its
  MaxReadLimit = 1 and CONSTRAINT StateConstraint (messages <= 6) make random traces short/sparse. Reported as
  "not seen in budget"; no item depends on MC.cfg alone.
- U3 was reached only in Update_hunt_linearizable_directed.cfg (U3Spec, which only restricts MCNext steps by
  phase guards); in the undirected cfgs (Update_full/focused/open, Update_hunt_linearizable) it was not seen in
  budget, and it is structurally impossible in Update_hunt_stale_ack.cfg (MaxTerm = 1). The agent's own
  undirected Update_hunt_linearizable BFS/simulation also found no violation (LIMITED_COVERAGE).
- SC_U3 requires a re-registered pending read (servedReads has an earlier read for the same leader/term/context)
  at a leader while commitHistory holds an entry committed in a higher term: inferred encoding.
- SC_U1/U2a/U2b/U4a reuse the arm's own history flags (scenarioSeen.readFreed/readReuse/staleAck/readResponse),
  checked against the brief wording (base.tla:498-510, 620-623).
