# Changelog — incremental run incr-4e410cd184be (case-011, Pre-Vote update)

Source identity: artifact HEAD `3ab6cdd` (synthetic commit `update`) over `1adc857`
(`baseline`). Prior suite: `/work/previous/.specular-output` (V0, exact-old).
Disposition: **MODEL_CHANGE_REQUIRED** (reported as `MODEL_UPDATED`).

## Round 0 - Generation (source-driven update)

- [update] base.tla: added pre-candidate state (`preCandidateActive/Vote/Config`,
  `preGrants`), `PreVoteReq`/`PreVoteResp` messages with the `reqVote`
  correlation field, `PreElectCore`/`TickPreElect`/`ExternalPreElect`,
  `HandlePreVoteRequest`, `HandlePreVoteResponse`, `NetworkDefaultPreVote`,
  constants `EnablePreVote`, `PreVoteDefaultGrant`.
- [update] base.tla: `do_elect` factored as `ElectEffects` (clears the
  pre-candidate, engine_impl.rs:263-264); `StartElection` keeps the old callers'
  voter guard; the new pre-vote caller has none (non-voter branch modelled as the
  learner-member / non-member union).
- [update] base.tla: tick path split by `EnablePreVote` and voter count
  (raft_core.rs:2012-2035); `seenGreaterLog` reset moved to the tick callers
  only (raft_core.rs:2027) — the prior reset it on every election start
  (implementation-backed correction, recorded as a repair).
- [update] base.tla: every `become_following` caller (HandleVoteRequest,
  HandleVoteResponse adopt, HandleAppendEntries, RefreshServerState) drops the
  pre-candidate (vote_handler/mod.rs:242-244); Restart drops it (Engine::new).
- [update] MC.tla: wrappers for the new actions, `preVote` counter, `preOrigin`
  MC ghost (origin of the active round), named reactive wrappers.
- [update] Update.tla + Update_*.cfg: Affected/Interaction sets, EnvUpdate
  (FlushLog rely), DischargeContext, five update properties, canaries.
- [update] Trace.tla: pre-candidate fields, `PreElect`/`HandlePreVoteRequest`/
  `HandlePreVoteResponse` wrappers, `ValidatePre`, narrowly guarded silent
  runtime completions for multi-event traces, env var renamed `SPECULAR_TRACE`.

## Round 1 - Trace Validation

- [fix] HandleVoteResponse: on a win the implementation's
  `establish_leader -> update_vote(committed)` installs the leader lease
  (vote_handler/mod.rs:123-135), the prior model left `leaseValid` unchanged;
  an adopted uncommitted vote gets a zero lease. Prior-model defect masked by
  the V0 fixture (its pre-state already had a lease).
  (Trace: stale_pre_vote_after_leader.ndjson event 4; establish_leader.ndjson re-passes)
- [fix] LogLE: `NoLog(i)` embeds a node id, so two empty logs
  (`Option<LogId>::None`) compared unequal and the last-log check rejected every
  vote request between empty logs. Prior-model defect: no multi-node election
  from empty logs was possible, so the prior 3-node MC.cfg never reached a
  leader (its leader coverage came only from the single-voter companion).
  Found by reachability canaries (`spec/scratch/Probe.tla`, logs
  `spec/output/probe-P4.log`, `probe-P5/P6.log`); repaired as `LogEq`.
  In-flight MC runs started before the fix were stopped and archived as
  `spec/output/*-INVALIDATED-prelogfix.log`.
- Full fresh suite (17 traces, 25 events) re-validated after both repairs:
  `spec/output/trace-validation-summary.log` (17 PASS, TraceConsumed checked).
- Negative controls: 12 single-field mutations of fresh traces all rejected
  (`spec/output/trace-mutation-controls.log`, `spec/evidence/trace-mutations/`).

## Round 1 - Model Checking

- [bug] TickPreVoteRoundNotHeldByLeader / LeaderNotPreemptedByTimerPreVote
  (MC-1): a pre-vote round started by the election timer while the node is a
  real Candidate survives `establish_leader`; its quorum makes the new Leader
  run `elect()` at term+1. Counterexamples: `output/upd-hunt-stale-round.log`,
  `output/upd-hunt-stale-round-consequence.log` (+ `cex/MC-1-stale-round.json`);
  also admitted by full `MCNext` (`output/upd-full.log`).
- [bug] VoteResponseFromFrozenVoter (MC-2): the surviving round completes after
  the leader removed itself from the voters; `elect()` runs for a (learner)
  non-voter whose own grant targets a node outside the candidate quorum set.
  `output/upd-hunt-nonvoter-cont.log` (+ `cex/nonvoter.json`).
- [bug] PreVoteResponseFromFrozenVoter (MC-3): a second round at the same
  hypothetical vote over a smaller membership is matched by a delayed grant of
  the first round from a removed node. `output/upd-hunt-repeat-round-cont.log`
  (+ `cex/repeat-round.json`).
- Standard MC.cfg / MC-membership.cfg and the update campaigns: see
  `spec/bug-report.md` "Campaign outcomes" for final bounded results.

## Round 2 - Model Checking (property revision, no behavior change)

- [fix-inv] PreVoteResponseFromFrozenVoter -> PreVoteGrantsWithinFrozenVoters and
  VoteResponseFromFrozenVoter -> CandidateGrantsWithinFrozenVoters: the repaired-model
  control `spec/evidence/mutants/CTRL-D-voter-recheck-repeat` showed the in-flight
  form rejects a legal state (a stale non-member grant in flight that a guarded
  handler ignores). The properties now constrain the grants actually counted
  (Candidate::grant_by's precondition). Both bugs re-found under the revised forms
  (`output/upd-hunt-nonvoter-cont.log`, `output/upd-hunt-repeat-round-cont.log`,
  `output/upd-full-cont1-sim.log`); the repaired-model controls satisfy them.
  Note: the first logs of the two `-cont` hunts (initial forms) were overwritten
  by these reruns; their JSON dumps are kept as `output/cex/*-initial-form.json`.
- Stage-2 campaigns with all three findings filtered (`Update_*_cont2.cfg`, BFS +
  simulation) and the default-grant hunt: no further violations within budget.
- Final regression gate on the final artifacts: SANY clean
  (`output/*-sany.log`), 17/17 fresh traces (`output/trace-validation-final.log`),
  12/12 mutations rejected (`output/trace-mutation-controls-final.log`).

## Result

Converged in 1 repair round (two prior-model defects repaired, no update-model
Case A/B repairs). Bug hunting: 3 model-checking findings, all reproduced on the
updated implementation (see `spec/bug-report.md`, `spec/confirmation-MC-*.md`).
