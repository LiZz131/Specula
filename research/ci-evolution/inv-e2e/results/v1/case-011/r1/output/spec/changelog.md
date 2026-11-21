# Changelog — V1 incremental run (Pre-Vote update)

Source: artifact `update` 3ab6cddc34a5bf127747434bb41e20a1b9ef7769 (prior V0:
`baseline` 1adc857f05fc8632eca18a7ce636f9c489dd5038).

## Generation (source-driven, disposition MODEL_CHANGE_REQUIRED)
- [update] base: constant `PreVoteSetting`; variables `preCandidateActive`,
  `preCandidateVote`, `preCandidateLastLog`, `preCandidateConfig`, `preGrants`,
  `sendPreVotePending`, `preSentReq`, ghost `preStartRole`; messages
  `PreVoteReq`/`PreVoteResp`.
- [update] base: actions `PreElect`, `TickPreElect`, `ExternalPreElect`,
  `SendPreVoteRequest`, `FinishPreVoteBroadcast`, `HandlePreVoteRequest`,
  `HandlePreVoteResponse`; `DoElect` factored out of `StartElection` and now
  clears the pre-candidate; `TickElect` only when the runtime flag is off or a
  single voter.
- [update] base: pre-candidate cleared on every `become_following` caller
  (`HandleVoteRequest`, `HandleVoteResponse` adopt, `HandleAppendEntries`,
  `RefreshServerState`) and on `Restart`; deliberately NOT on establishment.
- [update] MC: `preVote` counter, `MCTickPreElect`, `MCExternalPreElect`,
  reactive pre-vote actions. Trace: pre/post validation of every event,
  pre-candidate fields, new event wrappers, guarded silent runtime steps.
- [update] Update.tla + Update-*.cfg (full, focus, open, discharge, hunts).
- [repair] TickElect/TickPreElect reset `seenGreaterLog` (tick only);
  direct/external elections no longer reset it (raft_core.rs:2026-2027).

## Round 1 - Trace Validation
- Harness rebased (patch context drift in engine/mod.rs); 19 fresh traces
  (7 V0 regression + 12 update) collected with `harness/run.sh`.
- [fix] HandleVoteResponse: establishment installs the leader lease, adoption
  a zero lease (vote_handler/mod.rs:126-136). Exposed by the multi-event trace
  candidate_pre_vote_then_leader before any replay (pre-state analysis).
- All 19 traces PASS (`spec/output/v1-trace-summary.txt`); 11 single-field
  mutants all rejected (`spec/output/v1-trace-mutation-controls.txt`).

## Round 1 - Model Checking (pre-campaign canaries)
- [fix-spec] LogLE: absent logs compare equal (prior-model defect; V0 3-voter
  MC never granted a remote vote). Found because the U-S4 hunt reported no
  pre-vote grant at all; canary runs before the fix are kept as
  `*.invalidated-pre-LogLE-repair.log`. All traces re-validated afterwards
  (19/19 PASS) and mutation controls re-run (11/11 rejected).

## Round 1b - Trace coverage gap
- Canary `CanaryNoPreGrantCounted` cannot be reached in 3-voter uniform
  configurations (one remote grant is already a quorum). Added the real-engine
  scenario `pre_vote_resp_joint_accumulate` (joint config, grant accumulated
  without quorum, then quorum). 20/20 traces PASS after the harness rerun.

## Round 2 - Model Checking / Update campaign
- [bug] HandlePreVoteResponse/establish_leader: a Pre-Vote round started while
  Candidate survives leader establishment; its quorum calls elect() on the
  Leader (PreVoteNeverDemotesLeader, NoStalePreCandidateAtLeader). Case C;
  recorded as MC-1 (`spec/bug-report.md`, `spec/findings.json`). Continued
  the remaining campaigns with companion cfgs that disable U4/U5.
- [refactor] Update.tla: action properties re-expressed through named step
  operators (`*Step`) for static evidence evaluation; identical semantics;
  done after batch A had parsed the previous text (batch A results remain
  valid).
- Campaign results: see `spec/bug-report.md` "Campaign outcomes" and
  `spec/output/v1-campaign-table.md`. No further semantic edit was made after
  the campaign started; the final trace regression (20/20 PASS, 11/11 mutants
  rejected) applies to the final artifacts.

## Result
Trace validation converged (20/20 fresh traces). Model checking: 1 bug found
(MC-1, Case C), reference and other update properties not violated within
the 30-minute budgets (LIMITED_COVERAGE).
