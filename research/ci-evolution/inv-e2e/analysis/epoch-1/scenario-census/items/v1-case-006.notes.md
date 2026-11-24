# v1/case-006 census notes

- Items: US1-US6 from the V1 Update Scenarios table (output/modeling-brief.md:202-211). MC4/MC5 (findings table,
  :217-218) are the same situations as US3/US4 and are not separate items. Property intents (PendingMatchesQueue,
  ReadDeliveryJustifiedFresh, ReadIndexFreshness) are each tied to a scenario in the table and folded in.
- cfgs examined (all extend Update): Update_full, Update_focused, Update_focused_reset, Update_open (all four update
  properties); Update_hunt_us4_focused, Update_hunt_us4_guided, Update_hunt_us4_sim (no ReadDeliveryJustifiedFresh).
  Skipped: Update_reach_* and Reach_* (canary-only), Update_discharge*, MC*.cfg (V0 properties only), Trace*.
- Every agent canary cfg (Update_reach_*: MaxTerm=1, MaxCampaignLimit=1, ...) differs from the property cfgs, so no canary
  was counted. US3 and US4 are counted from the agent's own property-cfg violations (ReadDeliveryJustifiedFresh in
  Update_focused/_focused_reset and in a simulation of Update_full; ReadIndexFreshness in Update_hunt_us4_guided).
- Probes use the model's own ghost state: scenarioSeen flags (readFreed, readReenqueue, resetDropsRead, readResponse)
  and readReleases records (acks \ fresh /= {} = an ack not produced for this instance; commitHistory.commitTerm >
  release term = a newer leader committed). SC_US4 is my encoding of "US3 after a newer leader committed"; it does not
  require the stale index to be delivered.
- Update_hunt_us4_guided uses CONSTRAINT US4Guide (Update.tla), which forbids MsgReadIndex/MsgReadIndexResp messages:
  forwarded reads (US6) are structurally excluded there (US6 is not checked against that cfg anyway).
- Census runner: no errors.
