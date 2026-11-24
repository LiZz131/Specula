# v2 / case-002 census notes (ZooKeeper NEWLEADER ACK vs durability)

- Items: U1-U5 from output/modeling-brief.md section 8 (U4 split into U4a abort-in-INITIAL and U4b
  leaked-processor/in-memory divergence), plus property intents of UpdateProps.tla
  (LeaderCompleteness, SyncedLogMatchesLeader x2, PendingOnlyDuringSync) and the SyncCompletionJustified
  strengthening (invariant-evidence.json). NewLeaderAckDurable/CommittedDurableOnQuorum intents name the same
  situation as U1 and were folded into U1. Findings MC-1..MC-3 are violations (reached by definition), not
  separate items.
- cfgs probed (19, all run on the module the agent used: Update.tla for Update-*.cfg, MC.tla for MC*.cfg):
  every Update-*.cfg that enables an update property plus MC.cfg, MC-sim.cfg, MC-small.cfg (SyncCompletionJustified).
  Skipped: canary/reach cfgs, MC-hunt-*.cfg (inherited canaries), Trace*/TraceSync*/TraceWitness (trace),
  base.cfg (reference Spec without MC counters; MC.cfg covers the same checks), Update-discharge.cfg
  (only DischargeContext).
- All probes were put in every cfg; runner: 120 s seed 1 + 240 s seed 2 retry, depth 100, 1 worker, --jobs 3.
  No runner errors.
- Positive control SC_CTRL (a leader activated) reached everywhere except MC.cfg: MC.cfg keeps
  CONSTRAINT CanonicalDepthBound (level <= 23, output/spec/MC.cfg:17, base.tla:911) so every simulated trace
  stops at length 23 and no random trace activated a leader in 360 s. MC.cfg is therefore effectively dead
  under the census simulation; P_SCJ is covered by other cfgs (and by the agent's canary).
- Update-full.cfg / Update-full-sim-*.cfg (MCInit) reached only SC_CTRL/SC_P_SCJ/SC_P_SLMLa (+U4b in
  sim-completeness): the update situations need an epoch-1 txn followed by a re-election and DIFF sync, which
  random simulation rarely hits. The agent's own simulation of Update-full.cfg did violate NewLeaderAckDurable
  (output/spec/output/update/final-sim-update-full.log:36), so U1 is reached there per the agent log.
- U2 (crash inside the ACK/fsync window): reached only in cfgs that start from PostActivationInit
  (Update-hunt-postact-crash.cfg, Update-hunt-postact-full.cfg), i.e. from a hand-written initial state that
  the agent derived from the reachable U2 counterexample (Update.tla comment). Note: the agent's own
  LeaderCompleteness counterexample in Update-hunt-postact-crash.cfg contains no crash; the agent never
  ran a canary for U2 (NotRecoveryAfterUpdate is defined but not enabled in any cfg). Coverage of U2 rests on
  the census probe only.
- SC_U2 encodes "queued records are lost" as: learner in nlAcks[l], down, and lacking (durably) a txn certified
  in l's epoch. This is inferred from the wording, not a variable the agent named.
- SC_U4a encodes "processors are not stopped" as a live LOOKING server whose queued log is longer than its
  durable log (only possible when BeginElection skips the flush, base.tla:131-160).
- P_SLMLb (duplicate records) was reached even with Txn = {t1}.
- Agent canaries counted: NotNewLeaderAckWithLog (Update-reach-nlack-logged.cfg has the same sections as
  Update-focused-ackdurable/quorumdurable.cfg) and NotUpToDateReached (Update-reach-uptodate.cfg = Update-focused.cfg
  sections). Hunt initial states PostActivationInit / PostActivation2Init make SC_U1 true in the initial
  state of those cfgs.
- U3 and U5 are code-review/trace items by the agent's own scoping (late join not modeled; U5 unconfirmed
  hypothesis): classified unclear.
