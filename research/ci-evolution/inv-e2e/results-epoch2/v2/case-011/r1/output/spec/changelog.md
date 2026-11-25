# Changelog — incremental run (Pre-Vote update, case-011)

Prior suite: `/work/previous/.specula-output` (V0, exact-old). Source delta:
artifact `1adc857` (baseline) → `3ab6cdd` (update). Disposition:
`MODEL_CHANGE_REQUIRED` (`analysis-report.md` §U.2).

## Round 0 - Generation (source-driven update)
- [update] base: new constants `PreVoteTickModes`, `PreVoteRpcDefaultGrant`; new variables `preCandidateActive/Vote/Config`, `preGrants`, history bit `preRoundFromLeader`; message field `reqVote`; kinds `PreVoteReq`/`PreVoteResp`.
- [update] base: `DoElect` (do_elect; drops pre_candidate; no voter guard; become_following for non-members), `StartElection`/`TickElect` via `DoElect`; tick split by `PreVoteTickModes` and voter count.
- [update] base: `PreElect`, `TickPreVote`, `ExternalPreElect`, `HandlePreVoteRequest`, `DefaultPreVoteRpcGrant`, `HandlePreVoteResponse{Ignored,Grant,Elect,Reject}`.
- [update] base: `PreCleared` in every become_following path (`HandleVoteRequest`, `HandleVoteResponse` adopt, `HandleAppendEntries`, `RefreshServerState`), `Restart`; `establish_leader` keeps pre_candidate (code-faithful).
- [update] MC: `preVote` counter, `MCTickPreVote`, `MCExternalPreElect`, split reactive groups; cfgs carry the new constants.
- [update] Update.tla: Affected/Interaction actions, `EnvUpdate` (FlushLog durability rely) + `DischargeFlushLog`, six update properties with observational step recognizers, five reachability canaries; cfgs `Update_full/focused/open/discharge`, `MC_hunt_prevote_*`, `Update_canary_*`.
- [update] Trace.tla: pre-candidate fields, `StartPreVote`/`HandlePreVoteRequest`/`HandlePreVoteResponse`/`HandleAppendEntries` wrappers, `ValidatePre` for later events, silent runtime steps (`PersistVote`, `SendVote*`, `FlushLog`) gated by the next event's pre-state, `send_pre_vote_pending` check.
- [repair-V0] `StartElection` no longer resets `seenGreaterLog` (only the tick does; core/raft_core.rs:2027, old 1922); `TickElect`/`TickPreVote` reset it.

## Round 1 - Trace Validation
- [harness] V0 patch no longer applies (engine/mod.rs context drift); rebased as copy-and-patch; real `seen_greater_log` and real frozen quorum sets captured; 13 update scenarios added (later 16).
- [fix-spec] HandleVoteResponse: `establish_leader → update_vote(committed)` installs the leader lease; adopting a stripped vote installs a zero lease. V0 left `leaseValid` unchanged (V0 defect, both revisions; vote_handler/mod.rs:126-136, old 125-135). (Trace: stale_prevote_after_win.ndjson, event 4)
- [harness] added prevote_cleared_by_higher_vote_resp. Result: 21/21 PASS (`trace-validation-round2.log`).
- [check] 20 single-field mutants, all rejected (`field-consumption-summary.log`).

## Round 2 - Model checking entry (aborted) and repairs
- [fix-spec] LogLE: absent last logs (`Option::None`) compare equal regardless of the `NoLog(i)` node tag. V0 compared `NoLog(i)` and `NoLog(j)` as unordered, so every remote vote/pre-vote request between empty-log nodes was rejected and the 3-voter model could not elect via remote votes (V0 defect, both revisions; engine_impl.rs:379,434, old 302). Found because canary `CanaryNoPreVoteElect` was NOT violated; the first std-MC/canary runs were stopped and archived as `output/*superseded-pre-logfix*`.
- [harness] added `prevote_req_grant_empty_logs`, `grant_vote_empty_logs` (real code grants; V0 LogLE would reject).
- [fix-spec] RefreshServerState: a leading-but-uncommitted node keeps its cached role (update_internal_server_state does nothing; vote_handler/mod.rs:154-162, old 153-161). V0 recomputed it as "Candidate" from the self-named default vote.
- Full regression: 23/23 PASS (`trace-validation-round5.log`); mutants 20/20 rejected; canaries 5/5 witnessed (`canaries-round1.status`).

## Round 3 - Model Checking
- [bug] HandlePreVoteResponseElect on an established Leader (MC-1): `Update_full.cfg` violates `PreVoteRoundNotOutlivedByOwnLeadership` (14 states, `output/MC-1_update_full_violation.out`). Case C: confirmed by the TLC-validated trace `stale_prevote_after_win` and by the real runtime (`harness/repro/`, debug build: RaftCore panic at engine_impl.rs:977; release build: Leader demoted to term+1 Candidate; control without Pre-Vote: Leader kept).
- [property-add] `LeaderObjectVoteNotBehind` (implementation-asserted, engine_impl.rs:976-981), added after the real-runtime panic; evidence in `invariant-evidence.json`.
- [pre-existing] operator `trigger().elect()` on a Leader reaches the same Leader-object state in both revisions (`output/control-elect-on-leader-{old,new}.log`: RaftCore panics in both). Not attributed to the update; recorded as CR-PRE-1.
- [campaign] `-continue` run stopped after 115 repeated reports of the two analyzed counterexamples (`output/mc-update-full-continue.stopped-repeated-reports.log`); replaced by `*_filtered.cfg` variants with `ACTION_CONSTRAINT KnownFindingsFilter` (prunes only transitions into a state violating `LeaderObjectVoteNotBehind`).
- [note] REQ-EVIDENCE comment edits in base.tla were made while std-MC was running (comment-only; no semantic change).
- [unresolved] `PreVoteElectionByVoter` violated in the membership and single-voter hunts (`output/D-2_*.out`): MC-1 root cause + self-removal, and operator elect(true) on a Leader + self-removal. Requirement evidence is implementation-only -> unresolved (no property edit); disabled in continued hunts.
- [bug] MC-2: `PreVoteGrantFromTrackedVoter` violated without crashes (`output/MC-2_cross_round_grant_violation.out`): a delayed round-1 grant from a node removed before round 2 (same probe leader id) is counted. Real runtime: RaftCore panics at proposer/candidate.rs:107 (`output/repro-D-4-new*.log`, 3/3). The earlier crash-based simulation witness (`output/D-4_*sim.out`) relies on response delivery across a restart (model over-approximation) and is not used as evidence.
- [campaign] two duplicate membership simulations wrote to one log (a line appended to a running queue script executed); the log was discarded (`output/*discarded-duplicate-run.log`) and the simulation rerun once with `MC_hunt_prevote_membership_filtered_nog.cfg`.
- [campaign] `Update_full_filtered.cfg` BFS (`mc-update-full-filtered.log`) ran with `PreVoteElectionByVoter` enabled; the cfg was edited afterwards to disable it for the follow-up simulation.
