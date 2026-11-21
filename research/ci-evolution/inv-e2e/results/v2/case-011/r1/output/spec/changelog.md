# Changelog — incremental run, Pre-Vote revision

Source: artifact commit `update` (3ab6cdd) vs `baseline` (1adc857). Prior suite: `/work/previous/.specula-output` (V0).
Disposition (Chapter 1): **MODEL_CHANGE_REQUIRED**.

## Generation (Chapters 1-5)

- [update] `base.tla`: new pre-candidate state (`preCandidateActive/Vote/Config`, `preGrants`), history
  `preCandidateByTimer`, `preRound`; message kinds `PreVoteReq`/`PreVoteResp` with history field `round`;
  constants `TickPreVoteModes` (runtime `enable_pre_vote`), `PreVoteFallbackPeers` (default `pre_vote` network impl).
- [update] new actions `PreElect` (`TickPreElect`, `ExternalPreElect`), `HandlePreVoteRequest`,
  `HandlePreVoteResponse` (ignore / grant / quorum→elect / reject / grant_by-panic branches).
- [update] `StartElection` split into `ElectEffects` (do_elect, clears the pre-candidate) + member guard;
  `TickElect` taken only when the timer observes Pre-Vote disabled or a single voter.
- [update] `PreCandidateCleared` added to every `become_following` path (`HandleVoteRequest` follows,
  `HandleVoteResponse` adopt, `HandleAppendEntries`, `RefreshServerState`) and to `Restart`; not to
  `establish_leader`/`become_leader` (source does not clear there).
- [repair] `ElectEffects` derives role/candidate/leader from membership (do_elect → update_internal_server_state).
- [repair] `seenGreaterLog` reset only on the timer path (`raft_core.rs:2027`), not in every election start.
- [new] `MC.tla` wrappers `MCTickPreElect`, `MCExternalPreElect` (counter `prevote`), reactive Pre-Vote delivery;
  `Update.tla` (Affected/Interaction/EnvUpdate/focused/open/discharge), `UpdateProps.tla` (update properties,
  step recognizers, canaries), cfgs `Update*.cfg`, `MC_hunt_U2/U4/U4b/U5*.cfg`.
- [trace] `Trace.tla`: Pre-Vote wrappers, `HandleAppendEntries` wrapper, pre-state check of every event
  (`ValidatePre`), runtime-completion silent steps gated by the next event's pre-state, inbound Pre-Vote
  message injection; `Trace.cfg` replay bound `MaxLogIndex = 6` (a recorded request carries index 5).
- Syntax preflight: `spec/output/{base,MC,UpdateProps,Update,Trace}-sany.log` (all clean).

## Round 1 — Trace validation (fresh new-version traces)

- [harness] prior patch no longer applied with full context (`mod pre_elect_test;` added next to the anchor);
  rebased as copy-and-patch with a symbol anchor. Toolchain: installed `stable` (pinned nightly unavailable,
  `/opt/rustup` read-only). Real capture of `seen_greater_log` and of the frozen candidate quorum set replaces
  the prior constant/proxy.
- [fix-spec] `HandleVoteResponse`: winning installs the leader lease, adopting installs a zero lease
  (`vote_handler/mod.rs:122-146`); found by `prevote_stale_round_after_leadership` (prior `establish_leader`
  trace started with a valid lease and masked it). (Trace: prevote_stale_round_after_leadership.ndjson)
- [fix-trace] lease expiry between events modeled as a gated silent `ExpireLease`; harness uses a 20 ms lease and
  real sleep instead of re-setting the vote object. (Trace: prevote_round_reuses_probe.ndjson)
- [fix-trace] inbound Pre-Vote messages are injected and consumed from `messages` so step properties see the
  consumption; `Trace.cfg` `MaxLogIndex` raised to 6 (replay bound). (Trace: prevote_req_reject_lease.ndjson)
- Result: 16/16 fresh traces pass (`spec/output/trace-validation-summary.txt`), every trace field consumed
  (`spec/output/trace-field-consumption.txt`).

## Round 2 — Model checking (convergence and update campaigns)

- [fix-spec] (Case B, prior-model defect) `LogLE`: two absent logs (`None`) were unequal because the record
  encoding carries a don't-care node, so no vote/Pre-Vote request between log-less nodes could be granted
  and no multi-voter election ever completed in the 3-voter configs (prior `MC.cfg` was vacuous for
  leadership; prior leader coverage came only from the single-voter companion). Found by the reachability
  canary `CanaryNoCandidate` (spec/output/canary-prevote-elect-candidate.log after the fix). Runs started
  before the fix are under `spec/output/superseded/`.
- [fix-spec] (Case B) first `Update-full` counterexample to `StalePreVoteResponseIgnored`
  (`spec/output/superseded/mc-Update-full-preTimeoutRepair-caseB-stale-round-cex.log`) restarted a *timer*
  round while the previous round's responses were in flight. The implementation runs each Pre-Vote RPC under
  `timeout(election_timeout_min)` and restarts/creates a timer round only ≥ `election_timeout` after the
  previous round or lease refresh, so those responses have timed out. `PreElect` now drops the node's earlier
  Pre-Vote traffic when the timer starts a round; operator rounds (`ExternalPreElect`) are unchanged.
- [bug] `HandlePreVoteResponse`→`ElectEffects` on an established Leader: `TimerPreVoteElectsOnlyNonLeader`
  violated (U2). Counterexample `spec/output/mc-hunt-U2-bfs.log` (13 states); see `spec/bug-report.md` MC-1.
- [bug] `HandlePreVoteResponse` counts a grant of an earlier round with the same probe:
  `StalePreVoteResponseIgnored` violated through an operator round (U4). Counterexamples
  `spec/output/mc-Update-full.log` (full MCNext) and `spec/output/mc-hunt-U4-stale-bfs.log`; consequence
  `PreVoteResponseNeverPanics`; see `spec/bug-report.md` MC-2.
- [bug] consequence of MC-2: `PreVoteResponseNeverPanics` violated with operator rounds and a leader-local
  membership change (`MC_hunt_U4c_prevote_panic_operator.cfg`, 16 states,
  `spec/output/MC-2_PreVoteResponseNeverPanics_cex.out`); the mixed timer/operator hunt `MC_hunt_U4b` did not
  reach it within budget (BFS diameter 15 + simulation).
- [infra] focused/open specs have no always-enabled action, so bounded runs reach terminal states; they run
  with deadlock reporting disabled (`SPECULA_NODEADLOCK=1`).

## Final full trace regression

- After the last semantic edit (`PreElect` timeout drop), all 16 traces re-validated: PASS
  (`spec/output/trace-validation-summary.txt`).

## Final checks

- `MC.cfg` (standard round) ran after the last change that can affect it: with `MaxPreVoteCount = 1` at most
  one Pre-Vote round exists per behavior, so the later `PreElect` timeout drop (which only removes traffic of
  earlier rounds) cannot change its reachable transitions; its result stands for the final model.
- All update campaigns (full, residual, focused, open, discharge, hunts, simulations) ran on the final
  artifacts (after the timeout repair). Final trace regression: 16/16 PASS on the final `base.tla`/`Trace.tla`.
- End-to-end reproductions re-run on the final harness: both still fail as expected
  (`spec/output/repro-MC-{1,2}-latest.log`).
- Instrumentation reverted from `artifact/` (`harness/clean-instrumentation.sh`); TLC state directories removed.

## Result

Converged: no unresolved Case A/B. Two Case C findings (MC-1, MC-2), both reproduced end-to-end on the
update revision. All campaigns budget-limited (`LIMITED_COVERAGE`); see `spec/bug-report.md`.
