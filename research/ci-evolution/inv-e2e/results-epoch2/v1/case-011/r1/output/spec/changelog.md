# Changelog — incremental run case-011 (Pre-Vote revision)

Prior suite: `/work/previous/.specula-output` (V0, exact-old `1adc857`).
Current source: `artifact/` `3ab6cdd` ("update").
Prior logs moved to `spec/output/prior-v0/`; prior traces archived in
`traces/archive-v0/`; prior specs copied to `spec/prior-v0/`.

## Round 0 - Generation (source-driven update; disposition MODEL_CHANGE_REQUIRED)
- [update] base: new Pre-Vote state `preActive/preVote/preConfig/preGrants`, message kinds `PreVoteReq/PreVoteResp`, message field `round` (engine_impl.rs:95-165, notification.rs:34-44).
- [update] base: `StartElection` split into entry guard + `DoElect` (engine_impl.rs:262-289); `DoElect` clears the pre-candidate.
- [update] base: new `PreElect`/`PreElectEffect` (engine_impl.rs:297-322, raft_core.rs:1385-1478,2342-2344), `HandlePreVoteRequest` (engine_impl.rs:414-447, raft_core.rs:1551-1562), `HandlePreVoteResponse` (engine_impl.rs:516-554, raft_core.rs:1803-1820,2066-2090).
- [update] base: `TickElect(i, pv)` Pre-Vote branch for >1 voter (raft_core.rs:2010-2035); `ExternalPreElect` (raft_core.rs:1683-1696); constant `TickPreVoteModes` (runtime toggle).
- [update] base: `become_following` clears the pre-candidate in `HandleVoteRequest` (follows), `HandleVoteResponse` (adopt), `HandleAppendEntries` (other leader), `RefreshServerState` (non-leading); `Restart` resets it (vote_handler/mod.rs:154-160,242-244).
- [update] MC: separate `external` counter for operator triggers; `MCRestart` bounded separately (`MaxRestartCount`) so "node stays down" can be selected; `MCExternalPreElect`; pre-vote delivery in `MCReactive`.
- [update] Update.tla + cfgs (`Update_full`, `Update_focused`, `Update_open`, `Update_discharge`, `MC_hunt_prevote_leader_demote`, `MC_hunt_prevote_livelock`, canaries).

## Round 0 - Generation (repairs of inherited V0 abstractions, kept separate from the source delta)
- [repair R-1] HandleAppendEntries: follower adopts a greater leader last log (engine_impl.rs:586-602, following_handler/mod.rs:64-125). V0 never advanced follower logs, so Pre-Vote's log guard could not be exercised by replication.
- [repair R-2] new `appendBehindVote`: a log append queued behind a pending SaveVote is not submitted (cannot be flushed) before the vote is durable (raft_core.rs:2265-2305). V0 let FlushLog precede PersistVote.
- [repair R-3] TickElect requires the committed-vote lease to have expired (raft_core.rs:1996-2007, utime.rs:148-152).

## Round 1 - Trace Validation
- [harness] V0 patch failed only on `openraft/src/engine/mod.rs` context (new test modules); trace module reused, rebased into `harness/instrumentation.patch`; build with installed `stable` (1.100.0) because `nightly-2026-03-01` is not installed.
- [harness] capture adds pre-candidate fields, real frozen candidate/pre-candidate quorum, `append_behind_vote`, real `seen_greater_log`; multi-event update scenarios with runtime command drain; `null` args replaced by `{present:false}` objects.
- [fix] Trace: V0 events do not carry `send_vote`; `SendVoteMatches` now checks it only when present (Trace: start_election.ndjson; TLC field-selection error, not a model change).
- [fix-spec R-4] HandleVoteResponse: establishment installs the leader's own lease (`update_vote(committed)` uses `leader_lease`, vote_handler/mod.rs:121-135); a strictly greater adopted uncommitted vote installs a zero lease (Trace: candidate_prevote_then_establish.ndjson event 4, post `lease_valid=true`). Inherited V0 defect; relevant because the leader's lease gates Pre-Vote and vote grants.
- [result] 15/15 fresh traces fully consumed (`spec/output/trace-validation-round2.log`); 9/9 mutated traces rejected (`spec/output/trace-mutation-controls.log`); every emitted field consumed (`spec/output/trace-field-consumption.log`).
- [fix-spec R-5] LogLE: two absent logs compare equal (`Option<LogId>::None == None`; engine_impl.rs:379,434). Found by reachability canaries (no granted Pre-Vote / no Leader reachable with three voters). V0 had the same defect: its exhaustive 3-voter `MC.cfg` space never reaches a Leader or a granted remote vote (`spec/output/prior-v0-vacuity-canary.log`), i.e. V0 election coverage was vacuous outside the single-voter companion. Implementation evidence: new trace `grant_empty_logs` (rejected by the pre-R5 definition, `spec/evidence/R5-control/tlc.log`; accepted after the repair).
- [result] round 4: 16/16 fresh traces fully consumed (`spec/output/trace-validation-round4.log`); 9/9 mutants still rejected; canaries re-run: all Scenario canaries reachable (`spec/output/canaries-summary.log`); `CanaryNoPreVoteTally` retired (unreachable by construction with three uniform voters; killed run kept in `spec/output/mc-canary-CanaryNoPreVoteTally.log`).
- [aborted] standard MC rounds started before R-5 were stopped and are invalid (`spec/output/aborted-preR5/`).

## Round 2 - Model Checking (standard + update campaigns on the R-5 model)
- [bug] HandlePreVoteResponse/HandleVoteResponse (Case C, MC-2): a Candidate's tick starts a Pre-Vote round while its real election is open; `establish_leader` keeps `pre_candidate`; the late Pre-Vote quorum calls `elect()` on the new Leader (Leader -> Candidate, term+1). `MC_hunt_prevote_leader_demote.cfg`, `spec/output/mc-hunt-leader-demote-bfs.log` (14 states). Same final steps observed on the real engine in trace `candidate_prevote_then_establish`.
- [result] standard `MC.cfg`: no violation, LIMITED_COVERAGE (81,089,397 generated / 15,748,310 distinct, depth 17, queue 8,388,541, 30 min) `spec/output/mc-MC.log`.
- [result] `MC-membership.cfg`: no violation, LIMITED_COVERAGE (82,441,638 / 13,485,457 distinct, depth 23, queue 5,452,163) `spec/output/mc-MC-membership.log`.
- [converged] the standard round changed no spec file; trace round 4 and the standard MC round apply to the same model.
- [bug] confirmed over full `MCNext` with all faults/operator triggers: `Update_full.cfg` violates `PreVoteQuorumNeverDemotesLeader` (12 states, first election by operator trigger) `spec/output/mc-Update_full.log`.
- [hunt] `MC_hunt_prevote_livelock.cfg` BFS: no violation, LIMITED_COVERAGE (78,140,925 / 13,578,324 distinct, depth 21; the U-S2 schedule needs ~25 steps) `spec/output/mc-hunt-livelock-bfs.log`. Directed BFS/simulation with `LivelockDirector` stopped early as superseded (logs kept, no violation).
- [bug] NoPermanentPreVoteLivelock (Case C, MC-1): `MC_hunt_prevote_livelock_phased.cfg` (pruning-only monitor `LivelockDirectorPhased`) reaches, in 25 states, a state with node 1 (old leader) down, node 2 = (1,1,committed) with the longest log, node 3 = Candidate (2,3) with a shorter log; no live voter can ever gather a Pre-Vote quorum. Closure from the witness (Pre-Vote on): exhaustive, no live leader, votes frozen (`spec/witness/livelock/closure_on.log`); control with the pre-update tick (Pre-Vote off): a leader is elected (`spec/witness/livelock/control_off.log`). Real-engine observation: `specula_observe_prevote_livelock` / `specula_observe_old_path_recovers` (`spec/output/observations.log`).
- [result] `Update_full_cont1.cfg` (demotion property disabled): no violation, LIMITED_COVERAGE (18,617,678 distinct, depth 15) — BFS does not reach the ~25-step livelock schedule.
- [result] `Update_focused.cfg`: no violation, LIMITED_COVERAGE (15,894,086 distinct, depth 15); simulation follow-up started.
- [result] `Update_discharge.cfg`: `DischargeContext` holds, LIMITED_COVERAGE (7,727,867 distinct, depth 15).
- [fix-update] `EnvUpdate` rewritten as an existential over successor configs: the first open run aborted with a TLC evaluation error (primed variable read before assignment), not a property result (`spec/output/mc-Update_open-evalerror.log`). Discharge semantics unchanged.
- [bug] `Update_open.cfg` (rerun): `PreVoteQuorumNeverDemotesLeader` violated in 14 states using only Affected/Interaction actions (no EnvUpdate step), i.e. admitted by the full model (MC-2).
- [bug] `Update_focused.cfg` simulation follow-up: `PreVoteQuorumNeverDemotesLeader` violated (23-state random trace) — the concrete focused view detects MC-2 as well (`spec/output/mc-Update_focused-sim.log`).
- [result] `MC_hunt_prevote_leader_demote_cont.cfg` (demotion property disabled): no violation, LIMITED_COVERAGE (15,182,176 distinct, depth 25); simulation follow-up started.
- [result] continuations with both analysed violations disabled, all other properties (reference invariants, `PreCandidateProbesNextTerm`, `LivelockClosed` where applicable) kept: `Update_full_cont2` BFS, `Update_focused_cont` BFS, `Update_open_cont` BFS, `MC_hunt_prevote_livelock_cont` simulation, `MC_hunt_prevote_leader_demote_cont` simulation — no further violation (budget-limited; numbers in `spec/output/campaign-summary.json`).
- [note] `base.tla` and `MC.tla` are unchanged since R-5 (before the standard round); every Round 2 campaign checked the final reference. `Update.tla` later gained only search monitors (`LivelockDirector*`) and the equivalent `EnvUpdate` rewrite; `Update_discharge` evaluated the earlier `EnvUpdate` form, which is evaluable and equivalent when both states are given.
- [result] final trace regression on the frozen model: 16/16 (`spec/output/trace-validation-final.log`; md5 `spec/output/final-spec-md5.txt`).

## Result
Converged (trace validation and standard model checking pass on the same final model; budget-limited). Bug hunting: 2 findings (MC-1 Pre-Vote livelock, MC-2 stale Pre-Vote demotes a new leader), both update-introduced; see `spec/bug-report.md`.
