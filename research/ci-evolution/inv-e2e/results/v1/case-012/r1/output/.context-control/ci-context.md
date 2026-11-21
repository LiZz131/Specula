# CI context (case-012) — run-local working memory
- Source: artifact git: baseline ce863f4 (old) -> update aa05a38 (new). Copies: work/old-src, work/new-src (verified equal to /work/{old,new}-source changed files).
- Toolchain: rust-toolchain pins nightly-2022-03-30, not installed; RUSTUP_HOME read-only -> use `cargo +stable` (rustc 1.100). Probe build OK: spec/output/build-probe-new-stable.log.
- Chapter 1 decision: MODEL_CHANGE_REQUIRED. Leader commit moved from greatest_majority_value (core/replication.rs) to Engine::update_progress over Leader.progress: VecProgress<NID,Option<LogId>,Arc<EffectiveMembership>> (engine_impl.rs:617-647). leader_append_entries now: update_progress(self, prev-of-membership) -> update_effective_membership (upgrade_quorum_set) -> update_progress(self,last). Vote counting uses progress quorum set. Follower promotion only when commit advances (RaftState::update_committed). greatest_majority_value deleted.
- Suspected defect (code reading): VecProgress::update (progress/mod.rs:163-207) updates in place without move_up when prev > committed -> vector unsorted -> later recompute prefix includes lagging id -> over-commit. Reachable 3 nodes: leader n2, joint [{1,2,3},{1,3}] (remove leader): n1 acks idx0, propose joint at idx1, n3 acks idx1 -> commit idx1 without {1,3} quorum.
- Plan: base.tla adds progress record + leaderActive; ServerOrder constant; no symmetry in MC; Trace snapshot gains progress fields; new events UpdateProgress, UpdateEffectiveMembership, ProgressUpgrade; ProgressUpdate validated as pure VecUpdate relation; GreatestMajority superseded.

## Progress (after Validation, during MC)
- Validation done: harness rebased (patch applies to fresh artifact copy), 17 fresh traces all PASS r3 (spec/output/trace-validation-r3-summary.txt), 4 negative controls rejected.
- MC: MC.cfg no error (4.23M states, queue 0). MC-1 found (CommitWitnessSound etc.) in Update_full*, focused, open. Old control: spec/output/old-control-u1.log. Code observation: spec/output/new-observe-u1.log.
- OneOutstandingMembership crash violation = pre-existing Case A (V0 control log).
- Batch1 running (bg): upd-full-control-r2, upd-faults-control-r2, upd-focused-control-r1, upd-open-control-r1, upd-discharge-r2 (+ cws/open done).
- Next: batch2 = hunts s1-s4, Update_hunt_u1_deep/u2/u3/u4, Update_reach_*, MC5_u1_divergence, MC_scale; then sims for shallow BFS; final regression (MC.cfg re-run after base Init role tweak + full trace replay); validation-summary.md; final-result.json; /work/current/final-response.json.

## Round 2 (after repair)
- Repair: logConfig + faithful DeliverAppendEntries/RejectAppendConflict (spurious MembershipOrder from V0 sender-effective copy). Trace r5 17/17 PASS. Trace_keep OK.
- Wave A final (batch-final-A.txt): MC.cfg complete no error; s1-s4 complete; MC-1 regressions violated (cws/pcs/sorted/focused/open); canaries reached; u1deep sim2 clean; MC5 divergence violated CommittedLogAgreement again.
- Evidence re-evaluated on mc-upd-full-cws-final.log (E1,E1c,E3,E4,E4c,E5).
- Wave B running (batch-final-B.txt): controls, discharge, u2/u3/u4, u3 sim, scale.
- Remaining: validation-summary MC section, bug-report Not Reproduced table, final-result.json, /work/current/final-response.json.
- DONE: final outputs written (spec/final-result.json, /work/current/final-response.json).
