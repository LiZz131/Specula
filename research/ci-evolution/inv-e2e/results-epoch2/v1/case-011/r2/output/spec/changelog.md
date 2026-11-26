# Changelog — incremental run incr-315482ff25a1 (Pre-Vote revision)

Source: artifact `update` 3ab6cdd (old: `baseline` 1adc857). Prior suite: /work/previous/.specular-output (V0).

## Round 0 - Generation (MODEL_CHANGE_REQUIRED)
- [update] base: new constant `TickPreVoteModes`; variables `preCandidateActive/Vote/Config`, `preGrants`; message kinds `PreVoteReq`/`PreVoteResp`.
- [update] base: `DoElect` factored out of `StartElection` (engine `do_elect`), now drops the pre-candidate; shared by `PreElect` (self quorum) and `HandlePreVoteResponseElect`.
- [update] base: new `PreElect`, `TickPreElect`, `ExternalPreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse{Elect,Tally,Reject,Stale}`; `TickElect` now requires pre-vote mode off or a single voter.
- [update] base: `become_following` sites drop the round (`HandleVoteRequest` follow, `HandleVoteResponse` adopt, `HandleAppendEntries`, `RefreshServerState`); `Restart` drops it; establishment does not (source-faithful).
- [update] MC: `MCTickPreElect`/`MCExternalPreElect` bounded by `MaxPreElectionCount`; observer `preVoteBase`; named reactive wrappers; view canonicalizes inactive round fields.
- [update] Trace: pre-candidate init/post checks; `TracePreElect`, `TraceHandlePreVoteRequest` (purity: post = pre), `TraceHandlePreVoteResponse`; trace path env renamed to `SPECULAR_TRACE`.
- [update] Update.tla + cfgs: full, focused, open (EnvUpdate), discharge (two seeds), stale-round hunt, six reachability canaries.

## Round 1 - Trace Validation
- [harness] Rebased V0 patch (engine/mod.rs context drift), renamed to specular, added 10 update scenarios and 5 mandatory fields; V0 `candidate_config`/`seen_greater_log` approximations replaced by real captures.
- [fix] HandleVoteResponse: leader establishment installs the leader lease (`leaseValid := TRUE`), adopting an uncommitted vote clears it — pre-existing V0 abstraction defect masked by the V0 fixture; required by `pre_vote_after_establish.ndjson` (spec/evidence/repair-lease).
- Result: 16/16 fresh traces fully consumed (TraceConsumed) — superseded by Round 3 after the LogLE repair.

## Round 2 - Model Checking (aborted; vacuity found)
- [fix-spec] LogLE: two absent logs compared unequal because the absent-log record carries the owner id as placeholder; in the 3-voter MC no request from empty logs could ever be granted, so V0 `MC.cfg` never elected a leader (pre-existing V0 defect). Repaired as `LogEQ` (Option::None == None). Implementation observation `pre_vote_req_grant_empty_logs.ndjson`; reverted-repair replay rejected (spec/evidence/repair-logle). Runs started before the repair are kept in `spec/output/superseded/` and are not credited.

## Round 3 - Trace Validation (full regression on the stable candidate)
- [harness] added `pre_vote_req_grant_empty_logs`.
- Result: 17/17 fresh new-version traces pass (`spec/output/trace-validation-summary.tsv`); 6/6 field mutations rejected (`spec/evidence/trace-mutations/summary.txt`).

## Round 3 - Model Checking
- [canary] all six update reachability canaries violated (witnesses): Pre-Vote grant, reject, Pre-Vote-triggered election, election from Follower, round dropped by follow, Leader holding a round.
- [bug] HandlePreVoteResponseElect: `PreVoteElectionPremiseCurrent` violated under `Update_full.cfg` (12 states): a round started while Candidate survives `establish_leader`; a delayed granted Pre-Vote response makes the new Leader run `elect()` at term+1 (Case C; MC-1; spec/output/MC-1_update_full_PreVoteElectionPremiseCurrent.out).
- [hunt] continued with the Leader case filtered (`PreVoteElectionPremiseCurrentNonLeader`).

## Round 4 - Generation back-edge (completeness reread) + Model Checking
- [open] `Update_open.cfg` run 1: `DurableLogNotAhead` violated only through `EnvUpdate` (rely let a
  restarted node append below its existing log) — rely artifact; rely v2 requires monotone growth.
  Open run 2 (v2): no violation in 30 min (budget-limited, depth 10).
- [discharge] v2 rely: no violation in 30 min on both seeds; omitted actions fired thousands of times.
- [fix-spec] HandlePreVoteResponse: a granted response from outside the round's frozen voter set reaches
  `grant_by`'s `expect` (RaftCore panic); modeled as `HandlePreVoteResponseNonMember` (node stops).
  New update properties `PreVoteGrantFromRoundMember`, `NoPanicOnStalePreVoteGrant`; hunts
  `Update_hunt_stale_membership.cfg`, `Update_hunt_stale_membership_leader.cfg`.
- [regression] full trace replay after the repair: 17/17 PASS.
- [rerun] all campaigns restarted on the repaired suite (earlier logs in `spec/output/pre-nonmember-repair/`).
- [open] `Update_open_continue.cfg` (v2): `PreVoteGrantFromRoundMember` violated through an `EnvUpdate`
  step that changed a *follower's* voters without AppendEntries — not admitted by the full reference
  (only leaders change membership there); rely v3 restricts config changes to an active leader;
  open and discharge rerun with v3.
- [bug] stale Pre-Vote grant from a removed voter panics RaftCore — reproduced end-to-end
  (`spec/confirmation-MC-2.md`); MC counterexample from `Update_hunt_stale_membership.cfg` (15 states) = MC-2.

## Round 5 - Final checks on the stable suite
- [regression] full trace replay after the last reference edit: 17/17 PASS (`spec/output/trace-validation-summary.tsv`).
- [rely] `EnvUpdate` v3 (config changes only by an active leader with a committed self vote); discharge
  rerun on both seeds: no violation, omitted actions non-vacuous.
- [rerun] canaries (6/6 witnesses) and `Update_hunt_stale_round.cfg` rerun on the final suite (the
  pre-repair canary logs were overwritten in place by these reruns).
- [bug] MC-1 re-found by `Update_full.cfg` on the final suite (11 states).
- [bug] MC-2 found by `Update_hunt_stale_membership.cfg` and `Update_hunt_stale_membership_leader.cfg`
  (BFS, 15 states) and by the `Update_full_continue.cfg` simulation under standard bounds (31 states).
- [hunt] continued with both counterexamples filtered: `Update_full_continue2.cfg` simulation.
- No Case A/B remained open; every campaign outcome is listed in `spec/model-checking-summary.md`.

## Result
Converged in 5 rounds (trace validation and model checking pass on the final suite apart from the two
reproduced implementation defects). Bug hunting: 2 bugs found (MC-1, MC-2, both REPRODUCED); 1 code-review
observation classified FALSE POSITIVE (CR-1, documentation only). Model repairs of inherited V0 defects:
`LogLE` absent-log equality, `HandleVoteResponse` lease effects. Coverage is LIMITED_COVERAGE (bounded,
budget-terminated BFS + simulation; no exhaustive pass, no liveness claim).
