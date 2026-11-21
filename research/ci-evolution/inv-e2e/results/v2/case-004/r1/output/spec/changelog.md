# Changelog — incremental run for artifact commit `d7176ef` ("update")

Source: `/work/current/.specula-output/artifact` (branch `experiment`, `d86101c baseline` →
`d7176ef update`). Prior: `/work/previous/.specula-output` (V0, unchanged). Disposition:
**MODEL_CHANGE_REQUIRED** (`analysis-report.md`, "Incremental update analysis").

## Round 0 — Generation (source-driven update + prior-defect repairs)

- [update] `base!Elect` = `Engine::elect()` (engine_impl.rs:219-249) without voter guard;
  `base!StartElection` = RaftCore tick / `ExternalCommand::Elect` guard `IsVoter` + `Elect`.
  `Elect` now follows `update_internal_server_state`: a member (voter or learner) becomes
  Candidate; a node absent from membership drops candidate/leader (vote_handler/mod.rs:168-176,
  240-250).
- [update] new `base!TransferLeader(n, from, to)` (raft_core.rs:1190-1202): vote == from and
  n == to → `Elect`; otherwise a stutter (lease not modeled) with no queued commands.
- [repair] `base!ReceiveVoteRequest` compares the full last LogId (term,node,index)
  (engine_impl.rs:318) instead of the index only.
- [repair] `MC.tla` message-faithful framing (grant log after vote flush, published vote
  requests to effective voters, appends copied from a live leader's submitted log, flush-gated
  acks, `Drained` inbound guard). V0 counters `AckLimit` dropped (acks are reactive now);
  `TransferLimit`, `ElectNodes` added; `MCView` excludes the write-only `commands` variable.
- [trace] `Trace.tla`: `TransferLeader` event; VoteRequest args `last_term/last_node`;
  `accepted_kind` interpretation of `accepted_index`; `TraceElect` maps to `Elect`.
- [update] `Update.tla` + cfgs (full / focused / open / discharge / hunts / canaries);
  property `ElectionByVoterOnly`.
- Preflight: SANY clean for base/MC/Trace/Update (`output/sany-generation.log`); static cfg
  name resolution (`output/cfg-static-preflight.log`).

## Round 1 — Validation (harness rebase, fresh traces, trace validation)

- [harness] V0 patch re-applied cleanly to the update commit; unit capture gained
  `accepted_kind`, VoteRequest args gained `last_term/last_node` (scenarios unchanged).
- [harness] new RaftCore probes (`core/specula_core_trace.rs`; hooks in the TransferLeader arm,
  `handle_vote_request`, `Notification::VoteResponse`) and update scenarios
  `t99_specula_transfer::{specula_transfer_to_learner, specula_transfer_all_nodes}`; existing
  `t14_transfer_leader` reused unmodified.
- [harness-fix] session contiguity ignored nothing at first → target sessions closed at the
  first VoteResponse because RaftCore had drained the queued commands; contiguity now ignores
  `commands` (command execution is modeled by separate actions touching no other captured field).
- [harness-fix] RaftCore keeps condition-blocked `Respond` commands queued across inputs, so
  probes now report only commands queued by the current handler; the leader's committed SaveVote
  echo (no-op `handle_vote_resp`) is not emitted as a candidate grant.
- [fix-spec] (code observation, `output/harness-core.log`) a learner candidate's self-grant
  panics in `Candidate::grant_by` (`candidate.rs:92` `expect("target not in quorum set")`;
  progress is voter-only, `candidate.rs:66-72`). Added ghost `panicked`, guard
  `peer \in Voters(candidateConfigs[n])` on `ReceiveVoteResponse`, new action
  `CandidateGrantPanic`; property `NoRaftCorePanic` in `Update.tla`.
- Fresh trace suite: 8 Engine-level + 10 RaftCore session traces, all PASS with
  `TraceMatched` (`output/trace-validation-summary.tsv`, `output/trace-*.log`).
- Field-consumption controls: 11 single-field mutations, 10 FAIL as expected and 1 (m8)
  PASS as expected (`evidence/trace-mutation/README.md`).

## Round 2 — Model checking

- [fix-spec] (canary witness review) `CanaryLearnerLeader` was reachable because remote grants
  could be handled before the candidate's own grant. In code the self VoteResponse is queued by
  `SaveVote` before `SendVote` sends any request (raft_core.rs:1670-1682, engine_impl.rs:236-246),
  so `MCVoteResponse` now requires `peer = n \/ n \in granters[n]`. Round-1 canaries kept in
  `output/canary-r1-superseded/`.
- [fix-spec] (U1 hunt r1, `output/superseded/mc-Update_hunt_U1_voter_transfer-r1-evalerror.log`)
  with 3 voters a leader can commit index c through two followers before flushing its own entry c;
  the model's `SaveCommit` then persisted c, and after `Crash`/`Restart` commitIndex exceeded the
  recovered log (CommittedLogAgreement evaluation error; DurableStateBounded would also fail).
  The storage contract serializes write-IO (storage/v2.rs:33-35), so `save_committed(c)` completes
  only after the earlier append of entry c: `SaveCommit` now requires `flushedIndex >= commitIndex`.
  Independent of the update (path has no TransferLeader); needed for the 3-voter update hunts.
  Runs with 2 voters (MC-standard, Update_full_controls, U2 consequence, discharge) are unaffected:
  every quorum there includes the leader, whose self match is its flushed index.

- [bug] MC-1 (Case C): `ElectionByVoterOnly` violated in `Update_full.cfg` (12 states:
  leader 1 elected, learner 3 accepts its append, `MCTransferLeader(3)` makes the learner a
  candidate); same in focused/open/U2 hunt. Consequence `NoRaftCorePanic` violated in
  `Update_hunt_U2_panic.cfg` (16 states). Implementation reproduced on a clean d7176ef worktree
  (`output/clean-update-*.log`). Saved: `output/mc-Update_full.log`, `output/ttrace-Update_full/`,
  `output/mc-Update_hunt_U2_panic.log`, `output/ttrace-Update_hunt_U2_panic/`.
  The violating runs were repeated after the SaveCommit repair with the identical path
  (pre-repair logs in `output/superseded/`).
- Canaries: 7 witnessed; `CanaryLearnerLeader` not witnessed (15-min budget), consistent with code.
- Budgeted campaigns without violation (LIMITED_COVERAGE, 30 min each): MC-standard (V0
  invariants), Update_full_controls (BFS + simulation), Update_open_controls,
  Update_hunt_U1_voter_transfer (BFS + simulation), Update_hunt_U2_learner_consequence,
  Update_discharge (`DischargeContext`). Numbers: `output/model-checking-summary.md`.
- Final regression on final artifacts: 18/18 fresh traces PASS after the last `base.tla` edit
  (`output/trace-validation-summary.tsv`, checksums `output/trace-regression-final.md5`);
  MC-standard-final and Update_open_controls ran on the final model; Update_full re-run on the
  final model reproduces the same counterexample.

## Result

Converged: trace validation passes on the final model; every remaining counterexample is
classified (MC-1 Case C). The kept core-safety properties showed no violation within the
explored (budget-limited) state spaces — LIMITED_COVERAGE, not proof.
