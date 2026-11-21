# Changelog — incremental run (baseline `d86101c` → update `d7176ef`)

Prior suite: `/work/previous/.specula-output` (V0, immutable). Prior artifacts that are not
evidence for the new revision were moved, not deleted: archived V0 traces →
`traces/archived-v0/`, V0 TLC logs → `spec/output/prior-v0/`, V0 TLC trace dumps →
`spec/prior-v0-ttrace/`.

## Chapter 1 decision

`MODEL_CHANGE_REQUIRED` (see `analysis-report.md` §Update reconnaissance). The new
`RaftMsg::TransferLeader` handler (`core/raft_core.rs:1190-1202`) adds an Engine input that
(a) disables the current vote's lease and (b) for `to == self.id` calls `Engine::elect()`
without the `is_voter` / not-Leader / `enable_elect` guards of the two existing callers. (b)
changes the enablement of the modeled election action; (a) adds the lease flag
(`utime.rs`) whose `touch`/`update` semantics the reference must carry.

## Generation — source-driven edits (base/MC/Trace/Update)

- [update] `base!ElectCore` extracted from `StartElection` (shared elect() body), including
  the containment branch of `update_internal_server_state` (absent node → become_following).
- [update] `base!TransferLeader` / `TransferLeaderIgnored` added; `StartElection` keeps the
  voter guard of the pre-existing callers.
- [update] `leaseEnabled` variable: Init TRUE; `Leased::update` sites (elect, greater vote
  request/append, leader establishment, restart) re-enable; equal-vote `touch` preserves;
  TransferLeader non-target disables.
- [update] `MCTransfer` wrapper and `TransferLimit/TransferSources/TransferTargets` constants;
  `Trace.tla` `TraceTransferLeader`; `ValidatePostState` checks `lease_enabled`.
- [update] `Update.tla` + `Update_full/_full_residual/_focused/_open/_discharge/_canary_*`
  cfgs and three `MC_hunt_transfer_*` cfgs.

## Generation — repairs of V0 abstractions the update depends on (source unchanged)

- [repair R1] Vote exchange was unconstrained (any peer could "grant", requests carried no
  candidate log). Added `sendVoteReq`/`voteReqs`/`voteGrants`; `ReceiveVoteRequest` uses the
  full `LogId` order (`engine_impl.rs:317-331`); remote grants require an accepting voter whose
  vote I/O is flushed (`raft_core.rs:1112-1123`). Needed to check transfer-triggered elections.
- [repair R2] Replication linkage: general `ReceiveAppend` (follower adopts replicated
  membership, `following_handler/mod.rs` `append_membership`); MC follower appends copy a
  current leader's next entry; MC acks require the peer to hold and have flushed the prefix.
  Needed so commit/completeness across a leadership transfer is not vacuous or spurious.
- [repair R3] `ReceiveVoteResponse` grants from a target outside the candidate quorum set now
  take the panic branch of `Candidate::grant_by` (`candidate.rs:62-96`); `panicked` variable.
- [repair R4] Restart / `RestartFromRecovered` restore leadership only when the node is
  contained in the effective membership (`raft_state/mod.rs:369-383`).
- [repair R5] `ReceiveVoteRequest` saves (and re-enables the lease) only for a strictly greater
  vote; `last_seen_vote` updated monotonically (`vote_handler/mod.rs:96-171`).
- [repair R6] `FlushLog` persists only the submitted prefix, not the whole in-memory log.
- [repair R7] Leader establishment rebuilds the whole progress row (fresh `Leader::new`
  progress, `proposer/leader.rs:111-125`), not only self.
- [repair] `acceptedVoteIO` observation variable: core-level `accepted_io` after elect() is a
  vote I/O with no log id (`io_id.rs:71-98`); Trace compares the kind always and the index
  whenever it is a log I/O. Added `ReceiveVoteResponseOther` (rejection/stale responses only
  raise `last_seen_vote`) and `RejectVoteRequest` (lease/log/vote rejection, no state change)
  for the RaftCore-level traces.

Generation preflight: SANY clean for base/MC/Trace/Update; all cfg operator/constant names
resolve (static script). No TLC exploration during generation.

## Validation Round 1 — trace validation (harness rebased, fresh traces)

- Harness: V0 `instrumentation.patch` applied cleanly to the update tree; rebased patch keeps
  every V0 probe, adds `lease_enabled`/`accepted_vote_io` capture, last-log-id request args,
  the `specula_trace_lease_touch` unit scenario, the RaftCore hook
  (`openraft/src/specula_core_trace.rs`, hooks at the TransferLeader handler, RequestVote
  handling, and VoteResponse handling with an unwinding guard) and the integration scenario
  `t14_specula_transfer_to_learner`. Old patch kept as `harness/instrumentation.v0.patch`.
- `harness/run.sh` → 20 fresh nonempty traces (9 unit, 11 RaftCore chains).
- All 20 passed real TLC replay with `TraceMatched` on the first run
  (`output/trace-validation-round1.txt`, per-trace `output/trace-*.log`). No trace fix needed.
- Non-vacuity: 8 single-field mutations of fresh traces (lease disabled/not, touch vs update,
  vote-I/O kind, candidate/role of a learner target, ignored transfer, panic from a voter peer)
  are all rejected (`output/trace-mutation-check.txt`).
- Source tests on the instrumented tree: 199 passed, 0 failed (`output/source-tests.log`).

## Model Checking Round 1 — standard MC.cfg

- [fix-spec] `MCVoteResponse` (Case B, bounded-model artifact): a leader re-elected through
  transfer-to-self appended its establishment blank beyond `MaxIndex`, violating `TypeOK`'s
  length bound (`output/mc-standard-round1.log`). The code appends unconditionally; the MC
  wrapper now admits the winning grant only when the blank fits in `MaxIndex`. Base unchanged.
- `output/mc-standard-round2-interrupted-tool-limit.log`: rerun stopped by the agent after
  ~10 min because of a tool foreground limit (no violation before interruption); superseded.
- [fix-spec R8] Self vote-response ordering (Case B). `Update_full_ElectedLeaderWasVoter.cfg`
  found a learner becoming *leader* because the model let voters' grants be processed before
  the learner's own grant (`output/caseB-R8_ElectedLeaderWasVoter_pre-repair.out`). RaftCore
  queues the self `VoteResponse` during `SaveVote` on the same FIFO notification channel that
  later carries remote responses (`raft_core.rs:1065,1093,1669-1681`), so it is always
  processed first. Added `selfRespPending` (set by `PersistVote` of an own uncommitted vote,
  consumed by the self grant or `DropSelfVoteResponse`); MC remote grants wait for it.
  `output/mc-standard-round2b-superseded-R8.log` was stopped (model changed; no violation).
- [regression gate] Full fresh-trace replay after R8: 20/20 PASS
  (`output/trace-validation-round2.txt`).

## Model Checking Round 2 — standard MC.cfg on the final reference

- `output/mc-standard-round3.log`: 30-min BFS budget reached, no violation; 290,764,287 states
  generated, 40,710,696 distinct, depth 28, 9,739,774 left on queue (LIMITED_COVERAGE).

## Update campaigns (incremental Part 3)

- [bug] MC-1 (Case C): `ElectOnlyByVoter` violated on full `MCNext`
  (`output/MC-1_ElectOnlyByVoter_violation.out`, depth 10) and `NoCorePanic` violated
  (`output/MC-1_NoCorePanic_violation.out`, depth 12): TransferLeader to a learner → elect() →
  self grant → `Candidate::grant_by` panic. Also found by focused (`update-focused-c2-allprops`),
  open (`update-open-c3-allprops`) and `hunt-transfer-learner-bfs`. Real trace
  `core-learner-n3-c0` replays the same path; uninstrumented reproduction 5/5; baseline and
  same-revision controls guarded (`confirmation-MC-1.md`).
- `ElectedLeaderWasVoter` after R8: no violation in 30-min BFS on full `MCNext`
  (`output/update-full-c1-nonvoterleader-final.log`: 239,110,966 generated, 33,881,195
  distinct, depth 27, queue 8,783,686; LIMITED_COVERAGE).
- Canaries (all reached = non-vacuous): LeaseDisabled, TransferElectedLeader, OldLeaderDeposed,
  NonVoterCandidate, TransferGrant (wide cfg); CommitAfterTransfer and AbsentElect via tight
  witness cfgs (`output/canary-*-witness.log`); the wide-cfg runs of those two stopped at
  their 6-min budget unreached (`output/canary-CommitAfterTransfer.log`,
  `output/canary-AbsentElect.log`).
- [bug] MC-2 (Case C, pre-existing, new trigger): U7 `LeaderVoteNotSuperseded` (model form of
  the `Engine::leader_handler` debug assertion) violated via `MCTransfer(1,1)` on the leader
  (`output/MC-2_LeaderVoteNotSuperseded_transfer.out`) and, with transfers disabled, via a second
  `MCElect(1)` on the leader (`output/MC-2_LeaderVoteNotSuperseded_preexisting.out`). Real
  probes: update (`transfer_leader` to the leader, `trigger().elect()`) and baseline
  (`trigger().elect()`) all panic at `engine_impl.rs:765` (`confirmation-MC-2.md`). Found during
  the Chapter 5 completeness reread of the leader-target branch. U7 was added after the
  residual campaigns started; those campaigns do not check it.
- Discharge (`output/update-discharge-c3b.log`): `DischargeContext` holds within the 30-min
  budget (93,376,911 generated, 14,045,829 distinct, depth 22, queue 4,987,155); omitted-context
  canaries `CanaryOmittedApply`, `CanaryOmittedStale` reached (non-vacuous).

## Remaining campaigns (all on the final reference; see `output/campaign-table.md`)

- Residual full (`update-full-residual-c1b`, BFS) and simulation (`update-full-residual-sim`),
  focused residual (`update-focused-residual-c2`), open residual (`update-open-residual-c3a`),
  discharge (`update-discharge-c3b`), voter hunt BFS+simulation, membership hunt
  BFS+simulation, standard simulation: no violation; all budget-limited (LIMITED_COVERAGE).
- Startup errors: two hunts first launched against module MC (their cfgs use Update
  operators); logs kept in `output/startup-errors/`, rerun against Update.

## Result

Converged: final reference changed last by R8; full fresh-trace regression (20/20) and every
standard/update campaign ran after it. Findings: MC-1 (REPRODUCED, update-introduced),
MC-2 (REPRODUCED with debug assertions, pre-existing defect with a new update trigger).
No Case A/B remains open.
