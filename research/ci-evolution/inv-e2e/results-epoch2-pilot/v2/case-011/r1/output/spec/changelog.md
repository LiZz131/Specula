# Specular changelog — incremental run `incr-705b7bab5f0d` (case-011)

Prior suite: `/work/previous/.specular-output` (V0, exact-old election model).
Current source: `artifact/` commit `3ab6cddc34a5bf127747434bb41e20a1b9ef7769`
("update", parent `1adc857` "baseline"). Instrumented copy: `work-source/`.

## Generation — decision gate

- Disposition: **MODEL_CHANGE_REQUIRED**. The update adds an optional Pre-Vote
  round: new engine state (`Engine.pre_candidate`), new commands/messages
  (`Command::SendPreVote`, `RaftMsg::RequestPreVote`,
  `Notification::PreVoteResponse`), a new election-timer branch, a new
  external trigger (`ExternalCommand::Elect { pre_vote }`), and new effects in
  unchanged consumers (`do_elect` and `become_following` drop the
  pre-candidate). See `analysis-report.md` §Update.

## Generation — reference suite edits (source-driven)

- [update] constants/vars: `PreVoteNodes`; `preCandidate{Active,Vote,Config,LastLog}`,
  `preGrants`, `sendPreVotePending`; ghost observers `preRound`, `preByTimer`;
  message kinds `PreVoteReq`/`PreVoteResp`, ghost message field `round`.
- [update] `StartElection` split into `DoElectCore`/`DoElect` (engine `do_elect`,
  now drops the pre-candidate; voter check moved to callers as in the code;
  non-member caller becomes Learner and drops candidate/leader through
  `update_internal_server_state`).
- [update] new `PreElect`, `SendPreVoteRequests`, `HandlePreVoteRequest`,
  `HandlePreVoteResponse` (runtime leader-id filter + engine tally; grant from a
  non-member of the round's quorum set models the `grant_by` panic as a stop).
- [update] `TickElect`: Pre-Vote branch for `PreVoteNodes` with >1 voter;
  `ExternalPreElect` (trigger `elect(true)`), `ExternalElect`, transfer.
- [update] `HandleVoteRequest`, `HandleVoteResponse` (adopt), `HandleAppendEntries`,
  `RefreshServerState`: `become_following()` now drops the pre-candidate;
  `Restart` clears it; `establish_leader` keeps it (faithful to code).
- [update] `SendVoteRequest`: no longer requires `candidateActive` (the queued
  `SendVote` command runs even if `update_vote` dropped the candidate in the
  same event, e.g. a non-member electing through a stale Pre-Vote quorum).
- [repair, pre-existing] `TickElect` requires an expired vote lease
  (`handle_tick_election`: `is_expired(now, election_timeout)` implies the lease
  expired); single voter with an active candidate skips; only the timer path
  resets `seen_greater_log` (external `elect()` does not).
- [update] MC: `MCExternalPreElect` counted in the election budget;
  `MCReactivePreVote`; `MCTypeOK` bounds the ghost round counter.
- [update] Trace: new fields and events (`PreElect`, `SendPreVoteRequests`,
  `HandlePreVoteRequest`, `HandlePreVoteResponse`, runtime boundaries
  `PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast`, `FlushLog`,
  `ExpireLease`, plus `HandleAppendEntries`, `AppendUniformConfig`); trace file
  selection via `JSON`/`SPECULAR_TRACE`.
- [update] `Update.tla` + `UpdateProps.tla`: affected/interaction views,
  `EnvUpdate` rely, discharge/partition properties, 7 update properties,
  7 reachability canaries; cfgs `Update_*.cfg`, `MC_hunt_*.cfg`.
- Preflight: SANY clean for base/MC/Trace/Update/UpdateProps/EvidenceTrace;
  static cfg operator resolution OK for all cfgs (`spec/output/preflight.txt`).
  VAV tool aborted on the constant alias `ReferenceNodeOrder` (tool limitation);
  TLC's "successor not completely specified" check covers unassigned variables.

## Round 1 - Trace Validation

- Harness rebased: V0 patch no longer applied (`engine/mod.rs` context drift:
  new Pre-Vote test modules). New patch `harness/instrumentation.patch`
  (module renamed `specular_trace_test`, env `SPECULAR_TRACE_PATH`).
- [fix-harness] `candidate_config` now read from the Candidate's real frozen
  quorum set; `seen_greater_log` now the real engine flag (V0 hard-coded false).
- 19 fresh traces (7 rerun V0 scenarios + 12 update scenarios).
- [fix-spec] HandleVoteResponse (win): the new Leader's own lease is valid
  after `establish_leader -> update_vote(committed)` (pre-existing model
  defect, exposed by `candidate_prevote_establish` event 9, `lease_valid`).
  (Trace: candidate_prevote_establish.ndjson)
- Final regression: 19/19 PASS with `TraceConsumed` checked
  (`spec/output/trace-validation-summary.txt`); 20/20 field mutants rejected
  (`spec/output/trace-mutations/summary.txt`).

## Round 1 - Model Checking (first entry, before R1)

- `MC.cfg` (PreVoteNodes = {}) and `Update_full.cfg` exhausted their bounds with
  no violation (1.04M / 1.50M distinct states, depth 24) — but canary
  `CanaryNoLeaderWithTimerRound` showed leaders were unreachable.
- [fix-spec, pre-existing] R1 `LogEq`/`LogLE`: absent last-log ids compared
  unequal (placeholder node id), so no vote request between empty-log nodes was
  ever granted and no 3-voter election could succeed (Case B; prior V0 MC.cfg was
  vacuous for leader properties). New traces `grant_vote_empty_logs`,
  `prevote_req_grant_empty_logs`; V0 model rejects the first
  (`spec/evidence/E-LogNone/`).
- [fix-harness] `response_last_log` `None` placeholder now records the responder.
- Full trace regression after R1: 21/21 PASS; mutants 20/20 rejected.
- Results of the pre-R1 runs are superseded (logs overwritten by reruns).

## Round 2 - Model Checking

- Canaries: all 8 reachability canaries violated (non-vacuous).
- [bug] HandlePreVoteResponse/PreElect: `PreVoteStaleResponseIgnored` violated in
  `Update_full.cfg` (Case C → MC-1; counterexample
  `output/cex-update-full-PreVoteStaleResponseIgnored.log`).
- [bug] HandleVoteResponse/HandlePreVoteResponse: `TimerPreVoteElectionFromFollowerState`
  violated in `Update_full_cont1.cfg` (Case C → MC-2; counterexample
  `output/cex-update-full-TimerPreVoteElectionFromFollowerState.log`).
- [fix-inv] `ElectedNow` (UpdateProps) now also requires the queued `SendVote`,
  so a term bump without a real election is not mistaken for one (found by the
  regression mutant M-U2; Case A refinement of an observer, not a weakening).
  `update-full-cont2` restarted on the final definitions (earlier partial run
  kept as `output/update-full-cont2.superseded.log`); both counterexamples were
  regenerated on the final artifacts (`output/final-update-full-*.log`).
- Divergence evidence: `spec/invariant-evidence.json` (old-lens on traces,
  constructed TypeOK/MCTypeOK controls, regression mutants U1/U2/U3/U7).
- Reproduction (bug-confirmation, performed in this conversation because the
  `request_bug_confirmation` controller tool is not available here):
  `harness/repro/t13_specular_pre_vote_repro.rs` — MC-1 and MC-2 REPRODUCED
  (debug and release); `spec/confirmation-MC-*.md`; CR-1 documentation-only.
- Campaign table: `spec/output/campaigns.md`.
- [fix-inv] `EnvUpdate` (Update.tla rely) was too strong: its commit branch
  required an established leader, but `base!CommitMembership` has no role guard
  (counterexample: Leader appends a joint config, then starts an election, then
  commits; `output/discharge-full.cex-envupdate-too-strong.log`). The commit
  branch no longer requires leadership; install still does. Discharge rerun.
- [fix-inv] `EnvUpdate` rewritten into TLC-assignable `EXCEPT` form
  (`EnvInstall`/`EnvCommit`/`EnvFlush`; same meaning) — the per-index form
  evaluated in the discharge property but could not drive the open spec
  (`output/update-open-cont.tlc-assignment-error.log`). Discharge and open
  checks rerun on the final form.

## Round 3 - Model Checking (final artifacts)

- All campaigns rerun or run on the final definitions; table in
  `spec/output/campaigns.md`. No Case A/B issue remains open.
- [bug] MC-1 consequence: `PreVoteResponseNeverPanics` violated in the directed
  hunt `MC_hunt_prevote_panic_directed.cfg` (state constraint
  `HuntOnlyNode1Elects`, subset of reference behaviors),
  `output/cex-hunt-PreVoteResponseNeverPanics.log`.
- Canaries using `ElectedNow` re-run after its refinement: still violated.

## Result

Trace validation converged (21/21 fresh traces). Model checking (bounded,
LIMITED_COVERAGE): 2 implementation bugs found (MC-1, MC-2), both REPRODUCED
through the public API; CR-1 documentation inconsistency (FALSE POSITIVE as a
code defect). Pre-existing model defects repaired: R1, R2, R3.
