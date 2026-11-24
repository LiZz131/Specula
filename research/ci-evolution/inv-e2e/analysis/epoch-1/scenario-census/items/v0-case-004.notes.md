# v0 / case-004 census notes

- Probes were written by the census sub-agent for v0 002-006, which stalled before running them; the
  coordinating agent ran `run_census.py v0 case-004 --jobs 6` (120 s + 240 s per cfg) and classified.
- Cfgs: Update_full/focused/open, MC_hunt_transfer_membership/voter/learner (module Update). Positive
  control (a disabled lease) reached in all 6.
- Related checks: the properties the brief names per scenario (U-S1: ElectOnlyByVoter, NoCorePanic,
  ElectedLeaderWasVoter; U-S2: LeaseReenabledOnVoteChange, DisabledLeaseOnlyByTransfer; U-S3: TransferSafety
  conjuncts); U-S4/U-S5 name no property, so the update safety invariants are used.
- US4a (removed/absent target elects): Q-a. Structural in the five MembershipLimit=1 cfgs; not seen in
  MC_hunt_transfer_membership (MembershipLimit=2), where the agent's own same-constants canary BFS also
  stopped without a witness. The agent witnessed it only in a narrowed canary cfg (ReplicateLimit=4) that
  runs no property. Note MC_hunt_transfer_membership does not enable NoCorePanic/ElectOnlyByVoter.
- Agent canary logs were not checked for the covered items (census reached each one directly).
- Dismissals collected from brief §6b; may be incomplete.
