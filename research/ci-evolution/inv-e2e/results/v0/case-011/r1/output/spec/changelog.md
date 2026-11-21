# Changelog — incremental run (Pre-Vote update)

Prior suite: `/work/previous/.specula-output` (V0, exact-old). This run edits only
`/work/current/.specula-output/`.

## Round 0 - Inputs and decision
- [input] `artifact/` commits `baseline` 1adc857 → `update` 3ab6cdd; every changed file is byte-identical to `/work/old-source` (baseline) and `/work/new-source` (update) (cmp check, 0 mismatches).
- [decision] MODEL_CHANGE_REQUIRED (analysis-report.md §U.3): new Pre-Vote state/messages/actions; changed tick, external elect, do_elect, become_following, Engine::new.
- [baseline] Updated implementation builds with stable 1.100.0 (requested nightly-2026-03-01 unavailable); `openraft` lib 486/486 (harness tests excluded), `tests --test elect` 8/8 (incl. t12_pre_vote), `membership` 44/44, `life_cycle` 14/14 (`spec/output/baseline-new-*.log`).

## Round 1 - Generation (source-driven)
- [spec] base.tla: constant `TickPreVoteModes`; variables `preCandidateActive/Vote/Config`, `preGrants`; messages `PreVoteReq`/`PreVoteResp`; actions `PreElect`, `ExternalPreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`; `DoElect` factored from `StartElection` and clears the pre-candidate; `TickElect` gains the pre-vote branch; become_following callers (`HandleVoteRequest`, `HandleVoteResponse` adopt, `HandleAppendEntries`, `RefreshServerState`) and `Restart` clear the pre-candidate; `TypeOK` extended.
- [spec] MC.tla: `MCExternalPreElect`, reactive wrappers for pre-vote delivery, history variable `preRoundFromLeader`.
- [spec] Update.tla: Affected/Interaction Actions, `EnvMembership` rely + `DischargeMembership`, Focused/Open/TickOnly specs, properties U1–U4 + `PreCandidateProbesNextSelfTerm`, reachability canaries; 20+ cfgs.
- [spec] Trace.tla: pre-candidate init/pre/post checks, `ValidatePre` for multi-event traces, wrappers for PreElect, HandlePreVoteRequest/Response, HandleAppendEntries, `RunCommands` with constrained silent completion actions, `EventFieldsPresent` assumption.
- [preflight] SANY clean for base/MC/Update/Trace; static cfg operator resolution OK (`spec/output/cfg-static-preflight.log`).

## Round 1 - Trace Validation
- [harness] V0 patch no longer applies (engine/mod.rs context drift); rebased by copy + one-line registration; 7 prior + 12 update scenarios; fresh traces 19/19 nonempty (`spec/output/harness-run.log`).
- [fix] HandleVoteResponse (prior model defect): establish_leader installs the committed vote with leader_lease, adopt installs a zero lease; prior model left `leaseValid` unchanged (masked by V0 fixture lease). Trace: stale_pre_vote_after_establish.ndjson.
- [fix] Trace.tla TraceRunCommands: assign UNCHANGED vars before reading primed state (TLC evaluation order).
- [result] 19/19 PASS (`spec/output/trace-validation-full-run1.log`); 25/25 single-field mutants rejected (`spec/output/trace-mutation-check.log`).

## Round 1 - Model Checking
- [diagnosis] U1 hunt found no violation although the path is source-feasible. Localized to the prior log encoding: `NoLog(i)` embedded the node id, so `LogLE(None_i, None_j)` was FALSE and every log-less (pre-)vote request failed its log check; no three-voter election could succeed in the prior `MC.cfg` (prior leader/quorum properties vacuous there).
- [fix-spec] base.tla `NoLog` canonical (Option::None is one value, log_id/mod.rs:18-61); Trace.tla `SnapshotLog` maps absent logs to it. Repair of an existing model defect, independent of the source delta. Superseded round-1 MC logs: `spec/output/superseded-round1/`.

## Round 2 - Trace Validation (stable candidate)
- [result] full retained suite 19/19 PASS on the repaired model (`spec/output/trace-validation-full-run2.log`); mutation check re-run on the final artifacts (see Result).

## Round 2 - Model Checking
- [std] MC-membership.cfg exhausted: 299,637 distinct states, depth 29, no violation. MC.cfg: see Result (budget-limited).
- [bug] PreVoteNeverDemotesEstablishedLeader (U1) violated in hunt, timer-only hunt, full MCNext, focused and open views. Case C after source cross-check; engine-level trace replays the suffix; reproduced (MC-1, `spec/confirmation-MC-1.md`).
- [bug] PreVoteElectOnlyByVoter (U3) violated in full MCNext: same root cause (inherited round + leader self-removal). Recorded under MC-1.
- [canary] all five reachability canaries violated as expected (witnesses).

- [bug] PreVoteElectOnlyByVoter (U3) violated in `MC_hunt_prevote_membership.cfg` by a different trigger: operator `trigger().elect(true)` on the leader, leader self-removal, late grant → non-voter `elect()`. Still violated with the MC-1 fix applied to a model copy (`spec/fixcheck/`); recorded as MC-2 (`spec/confirmation-MC-2.md`).
- [spec] Update.tla: `TickOnlySpec` (timer-driven only) for the U1 timer-only hunt; U2/U4-only cfgs so the remaining properties are checked past the MC-1/MC-2 violations; `MC_hunt_prevote_membership_U2.cfg`.
- [control] `spec/fixcheck/` (MC-1 candidate fix) and `spec/fixcheck2/` (MC-1 + MC-2 candidate fixes) are copies for sanity controls only; the reference suite is unchanged by them.
- [harness] Reproduction tests `harness/repro/` (engine + runtime for MC-1 and MC-2). First reproduction logs were superseded (`spec/output/superseded-repro-shared-target/`): source copies shared one `CARGO_TARGET_DIR`, and cargo's path-independent artifact names plus mtime fingerprints reused an rlib built from a fix-control copy; `run-repro.sh` now uses one target dir per source tree and all sets were rerun.
- [sim] Simulation follow-ups (depth 100, 30/20 min) for std MC, full U2/U4, crash hunt, and discharge: no violation.

## Result
- Final semantic spec edit: NoLog canonicalization (Round 1 MC). Full retained trace suite replayed after it: 19/19 PASS (`spec/output/trace-validation-full-run2.log`); mutation check rerun on final artifacts: 25/25 rejected.
- Standard round: `MC-membership.cfg` exhausted (299,637 states); `MC.cfg` 23.9M distinct states, depth 20, budget-limited; simulation 144,684 traces — no violation of the preserved invariants.
- Update campaigns: U1 and U3 violated (MC-1, MC-2, both REPRODUCED); U2, U4, interaction invariant: no violation within bounds; discharge of EnvUpdate: no violation (seed1 exhausted); all canaries reached.
- Bug hunting: 2 bugs found. Campaign table: `spec/bug-report.md`.
