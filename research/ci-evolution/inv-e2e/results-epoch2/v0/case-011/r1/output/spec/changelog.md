# Changelog — incremental run for the Pre-Vote update (case-011)

Prior suite: `/work/previous/.specula-output` (exact-old V0, immutable).
Source: `artifact/` synthetic history `1adc857` (baseline) -> `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` (update).
Harness work copy: `work-source/` (plain copy of `artifact/` at `3ab6cdd` + `harness/instrumentation.patch`).

## Round 0 - Generation (decision gate: MODEL_CHANGE_REQUIRED)

Source-driven updates (see `analysis-report.md` section "Incremental update"):
- [update] Declarations: `PreVoteSetting` constant; volatile Pre-Vote tracker `preCandidateActive/Vote/Config/preGrants`; ghost origin `preCandidateByTick`; message kinds `PreVoteReq`, `PreVoteResp`.
- [update] `PreElect` (Engine::pre_elect): no vote/role/persistence change, frozen effective config, self grant, single-voter direct `elect()`, SendPreVote emitted to the other effective voters.
- [update] `HandlePreVoteRequest` (handle_pre_vote_req + handle_pre_vote_request): lease (no transfer bypass) -> last log -> would-grant; read-only; reply not flush-gated.
- [update] `HandlePreVoteResponse` (Notification::PreVoteResponse filter + handle_pre_vote_resp): tally, quorum -> `elect()` without role check, rejection only sets the greater-log hint.
- [update] `DoElectCore` (do_elect) drops the tracker; `TickElect`/`TickPreElect` split on the runtime flag and voter count; `ExternalPreElect` (Trigger::elect(true)).
- [update] Tracker cancellation in `HandleVoteRequest` (follows), `HandleVoteResponse` (adopt), `HandleAppendEntries`, `RefreshServerState` (become_following) and `Restart` (Engine::new); kept on establishment (establish_leader -> become_leader).
- [update] MC: `MCTickPreElect`, `MCExternalPreElect`, `MCDeliverPreVoteRequest/Response`, `preVote` counter, `AllowDirectOperatorElect`, `AllowExternalPreElect`; reactive steps named individually for Update.tla.
- [update] Trace: new fields `pre_candidate_*`, `pre_grants`, `send_pre_vote_pending`, real `seen_greater_log`, real frozen `candidate_config`; wrappers `TracePreElect`, `TraceHandlePreVoteRequest`, `TraceHandlePreVoteResponse`.
- [update] New `Update.tla` (Affected/Interaction/Omitted actions, `EnvUpdate`, discharge, U1-U5 properties, canaries) and Update/hunt/canary cfgs.

Model repairs independent of the source delta (implementation-backed):
- [repair] `StartElection`/`ExternalElect`: no longer reset `seenGreaterLog` (only handle_tick_election calls reset_greater_log, raft_core.rs:2026-2027; ExternalCommand::Elect does not, raft_core.rs:1683-1695).
- [repair] `TickElect`: single-voter skip while a candidate exists (raft_core.rs:1988-1994) and multi-voter tick only after lease expiry (is_expired(now, election_timeout), raft_core.rs:1996-2008).
- [repair] `HandleVoteResponse`: a won election installs the leader's own vote lease (`leaseValid' = TRUE`, update_vote with leader_lease = election_timeout_max); an adopted stripped vote has lease 0. V0 left `leaseValid` unchanged. Found while building the update scenario `candidate_pre_round_survives_leadership` (a Candidate with a zero lease becomes Leader).
- [repair-harness] Trace capture of `seen_greater_log` (V0 hard-coded `false`) and of the Candidate's frozen quorum (V0 used the effective config).

Preflight: SANY clean for base/MC/Trace/Update (`spec/output/*-sany.log`); static resolution of every cfg operator/constant: 0 problems.

Known independent V0 limitation (not repaired; outside the update): `SendVoteRequest` always sends `transfer = FALSE`, so the leadership-transfer lease bypass is not reachable through MC (it is covered only by the engine-level Trace wrapper).

## Round 1 - Trace Validation

- Harness rebased: V0 patch hunk for `engine/mod.rs` drifted (new test modules); reapplied with `git apply -3`; test module extended (see `harness/INSTRUMENTATION.md`).
- Toolchain: `rust-toolchain` requests nightly-2026-03-01, which is not installed (`/opt/rustup` read-only); stable 1.100.0 builds the revision (`spec/output/harness-build.log`).
- 21 fresh traces (7 V0 regression + 14 update), 28 events; all 21 replayed with `TraceConsumed` and no error on the first attempt (`spec/output/trace-validation-round1.txt`, `spec/output/trace-*.log`).
- Negative control: 34 single-field mutants of fresh traces (post-state, request/response arguments) are all rejected (`spec/output/trace-mutation-check.txt`, `spec/output/mutants/`).
- Archived V0 traces (`traces/prior-v0/`) are superseded by the fresh reruns of the same scenarios (they lack the mandatory new fields).

## Round 1 - Model Checking

- [invalid] First standard runs (`spec/output/invalid-vacuous-mc-standard.log`, `invalid-vacuous-mc-membership.log`) and the first U2 hunt were started on a model in which no 3-voter election can succeed; stopped/discarded once the canaries exposed it.
- [fix-spec] `LogLE`: absent logs compare equal regardless of the trace node tag (`LogEq`). Case B, inherited from V0: `Canary-leader-tick-round.cfg` and scratch invariants (`spec/debug/`) showed no Leader reachable in 3-voter configs; the immutable V0 primary config has the same property (`spec/output/v0-vacuity-noleader.log`: "no Leader" holds over all 640,830 V0 states). Source: `Option<LogId>` ordering, `log_id/mod.rs:18-61`.
- [regression-check] All 21 fresh traces replayed again after the repair: 21/21 pass (`spec/output/trace-validation-round2.txt`).
- [bug] MC-1 `TickPreVoteNeverDeposesLeader` violated in `MC_hunt_prevote_leader.cfg` (14 states, `spec/output/MC_hunt_prevote_leader_violation.out`) and in `Update-full.cfg` over the complete MCNext (13 states, `spec/output/Update-full_violation.out`). Case C: path matches the implementation (trace-validated transitions; engine and integration reproductions incl. timer-only, `spec/bug-report.md`).

## Validation handoff (gate for model-checking campaigns)

- Source SHA: `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` (artifact `update`), instrumented copy `work-source/`.
- Harness command: `harness/run.sh` (build + 21 scenarios), `harness/validate-traces.sh`, negative control `harness/mutation-check.sh`.
- Fresh traces: `traces/*.ndjson` (21 files, 28 events): 7 V0 regression scenarios rerun on the updated implementation + 14 update scenarios. Inventory with event counts: `spec/output/trace-validation-round2.txt`.
- Affected Actions observed: `PreElect` (multi-voter, single-voter, Candidate, joint), `HandlePreVoteRequest` (lease/log/vote reject, grant), `HandlePreVoteResponse` (no tracker, reject+greater log, partial grant, quorum at follower, quorum at Leader), `DoElectCore` via `StartElection`. Not observed (time/runtime environment): the timer guards of `TickElect`/`TickPreElect`.
- Interaction Actions observed: `HandleVoteRequest` cancel, `HandleVoteResponse` establishment keeping the tracker, `Restart` dropping it. Not observed: `HandleAppendEntries`/`RefreshServerState` cancellation, `PersistVote`, `FlushLog`, network delivery/drop.
- Archived V0 traces: `traces/prior-v0/` superseded by fresh reruns (missing mandatory update fields).
- Semantic spec files changed during validation: yes (`LogLE` repair after round 1 canaries; leader lease repair during harness construction); full trace replay rerun after the last change (round 2, 21/21).

## Round 2 - Model Checking (campaigns) and repairs

- [bug] MC-1 also violated in `Update-focused.cfg` and `Update-open.cfg` (12 states each, concrete Affected/Interaction steps only; `spec/output/Update-focused_violation.out`, `spec/output/Update-open_violation.out`).
- [fix-spec] `Restart` (Case B, found by `MC_hunt_prevote_membership.cfg`, `spec/output/MC_hunt_prevote_membership_violation.out`): the counterexample delivered a Pre-Vote response for a request of the pre-crash incarnation to the restarted node. RPC responses only reach the RaftCore that issued the request (`spawn_parallel_vote_requests` sends on that core's `tx_notification`). Restart now discards the old incarnation's Pre-Vote requests and every Pre-Vote response addressed to it (Pre-Vote handling is read-only on the responder, so no responder behavior is removed). Pre-repair logs: `hunt-prevote-membership-prerepair.log` (the artifact counterexample) and `hunt-prevote-restart-prerepair.log` (no violation; over-approximation evidence).
- [code-review -> reproduced] The membership-hunt artifact pointed at a real mechanism: rounds at one term reuse the leader id `(term+1, self)` and RaftCore's filter compares only the leader id, so a delayed grant from an earlier round is counted in a later round; `Candidate::grant_by` `expect`s the granter to be in the frozen quorum set. A crash-free path (operator `Trigger::elect(true)` twice across a membership change that removes the granter) panics RaftCore: engine test `specula_repro_stale_pre_vote_grant_from_removed_member` and integration test `t93_specula_stale_pre_vote_grant_removed_member` (`spec/output/repro-engine-stale-grant.log`, `spec/output/repro-integration-stale-grant.log`). The follower variant is outside the model vocabulary (followers never change config in the model); the leader variant is hunted by `MC_hunt_prevote_stale_grant.cfg`.
- [regression-check] Final full trace replay on the final model: 21/21 pass (`spec/output/trace-validation-round3-final.txt`); mutation control 34/34 rejected (`spec/output/trace-mutation-check-final.txt`).
- [bug] MC-2 `PreVoteTrackerWellFormed` violated by TLC simulation of the complete MCNext (`Update-full-noU2.cfg`, 31 states, crash-free, `spec/output/Update-full-noU2_sim_violation.out`): timer round kept by the new Leader, membership change removes node 3, operator `Trigger::elect(true)` starts a same-term round, node 3's delayed grant is counted. Case C: in the implementation the grant reaches `Candidate::grant_by`'s `expect` and RaftCore panics; reproduced by engine tests (leader and follower variants) and integration test t93 (`spec/reproduction-MC-2.md`).
- [bug] MC-2 also found by BFS of `MC_hunt_prevote_stale_grant_tight.cfg` (17 states, crash-free, `spec/output/MC_hunt_prevote_stale_grant_tight_violation.out`); the engine test `specula_repro_stale_pre_vote_grant_leader_variant` follows this shape and panics.

## Result

Generation, Validation and Model Checking completed for the update (`MODEL_CHANGE_REQUIRED`).
- Trace validation: 21/21 fresh traces pass on the final model (round 3); mutation control 34/34 rejected.
- Model checking: standard MC/membership, full/focused/open/discharge, five Scenario hunt families with BFS + simulation follow-ups, eight canaries. All BFS/simulation runs without a finding are budget-limited (LIMITED_COVERAGE); no exhaustive pass is claimed.
- Bugs (Case C): MC-1 (`TickPreVoteNeverDeposesLeader`), MC-2 (`PreVoteTrackerWellFormed`), both reproduced on the updated implementation. Code-review: CR-1 (Pre-Vote term stall, reproduced end-to-end with a passing direct-election control), CR-2 (documentation/code mismatch on the default `pre_vote`).
- Model repairs: `LogEq` (V0 vacuity), leader lease on establishment, timer guards, external-elect greater-log flag, Restart purge of old-incarnation Pre-Vote exchanges; harness capture of `seen_greater_log` and frozen quorums.
