# Harness instrumentation (rebased)

* Patch: `patches/instrumentation.patch` (against artifact commit `2efbdfc`,
  "update").  It is the prior Specula patch with `SpeculaTrace`/`specula.*`
  renamed to `SpecularTrace`/`specular.*`, the `BroadcastReady` probe moved to
  follow `zk.startServing()` (the updated replacement of `zk.startup()`), plus
  update-local probes: `LearnerSyncProposal`, `LearnerSyncCommit`,
  `NewLeaderReceived`, `NewLeaderAckSent`, `UpToDateReceived` (Learner),
  `AckSent` (SendAckRequestProcessor), `LeaderSyncQueued`, `NewLeaderQueued`,
  `NewLeaderAckRead`, `UpToDateQueued`, `LeaderAckReceived` (LearnerHandler),
  `LeaderProposed`, `LeaderCommitted` (Leader).  The writer gains `peer`/`info`
  fields.  The patch also adds the harness test
  `SpecularUpdateScenariosTest` (copy in `src/`).
* Prior patch preserved read-only at `patches.prior-ro/instrumentation.patch`.
* Event/field/Action mapping: `../spec/instrumentation-spec.md`.
* Rebuild and rerun: `harness/run.sh` (fresh copy of the artifact + patch +
  JDK 11 build) or `harness/run.sh --no-prepare <scenario...>`.
