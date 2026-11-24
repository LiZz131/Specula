# v1/case-004 census notes

- Items: U1-U4 from the update brief (output/modeling-brief.md:197-229), split: U1a learner elects, U1b core panic,
  U1c absent target (named in analysis-report.md:181); U3a/b/c; U4a/b. Property intents of ElectionInitiatorIsVoter,
  CandidateIsVoterOfSnapshot, NoCorePanic all name the U1 situation and are folded into U1a-c.
- U1a/U1b/U1c/U3a/U3b were judged from the agent's own logs: violations in property cfgs (Update_full*.cfg) or canaries
  in canary cfgs whose CONSTANTS + SPECIFICATION are identical (checked by diff) to a property cfg
  (CanaryTransferVoterLeader/OldLeaderSuperseded/TransferLeaderCommits = Update_full_voter.cfg;
  CanaryCrashBeforeSaveVote = Update_full.cfg; CanaryAbsentElect = Update_hunt_U1_absent(_nodsb).cfg). No census needed.
- Census probes run for U3c, U4a (both double-checks of agent canaries) and U4b (no agent canary) on Update_full,
  Update_full_voter, Update_focused_voter, Update_open_voter, Update_hunt_U3_voter, Update_hunt_U4_crash (all extend Update).
- U2 (stale from) is trace-only by the agent's design: MCTransferLeader passes the node's own vote, so the ignored branch
  is unreachable in MC (MC.tla:50-54); classed unclear.
- Note Update_full_voter has TransferTargets={2}, ElectNodes={1}, CrashNodes={1,2}; Update_full has TransferTargets={2,3}.
- Census runner: no errors.
- Update_hunt_U3_voter.cfg has CrashLimit=0 (line 12): U4a/U4b structurally unreachable there. U4a not seen in 360 s in Update_focused_voter/Update_open_voter (no structural reason found).
