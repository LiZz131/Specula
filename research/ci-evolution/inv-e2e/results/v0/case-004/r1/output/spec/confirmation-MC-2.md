# Confirmation — MC-2

- **Source**: MC (`spec/output/MC-2_LeaderVoteNotSuperseded_transfer.out`,
  `spec/output/MC-2_LeaderVoteNotSuperseded_preexisting.out`).
- **Status**: REPRODUCED (builds with debug assertions; the configuration of openraft's tests)
- **Novelty**: not assessed (external issue search prohibited by the isolation contract).
- **Attribution**: pre-existing defect; the update adds a new public trigger
  (`transfer_leader` with `to` = the current leader). Baseline control reproduces through
  `trigger().elect()`.
- **Severity**: Low (leader RaftCore panic → leader lost until election timeout; release-build
  consequence not verified).
- **Location**: `openraft/src/engine/engine_impl.rs:765-770` (assertion),
  `openraft/src/core/raft_core.rs:1190-1202` (new trigger), `:1207-1213` (pre-existing trigger),
  `:966-969` (per-iteration `leader_handler()` call).

## Investigation

- `Engine::elect()` on a Leader: `update_vote(new uncommitted self vote)` →
  `update_internal_server_state()` → `is_leading` → candidate kept, `self.leader` untouched
  (`vote_handler/mod.rs:174-182`) — documented coexistence (`proposer/leader.rs:21-27`).
- `Engine::leader_handler()` debug-asserts `leader.committed_vote >= state.vote`
  (`engine_impl.rs:765-770`); `(T,L,Q) >= (T+1,L,-)` is false by `vote/vote.rs:21-41`.
- RaftCore calls `self.engine.leader_handler()` after every batch of inputs
  (`raft_core.rs:966-969`), so the assertion fires on the next loop iteration.
- Guards: tick election refuses a Leader (`raft_core.rs:1446-1449`); ExternalCommand::Elect does
  not ("TODO: reject if it is already a leader?"); TransferLeader does not.

## Reproduction

`harness/repro/run_probe_leader_self_elect.sh update` and `... baseline` (test files only):

```
update  : probe_transfer_leader_to_current_leader -> n0 panicked at openraft/src/engine/engine_impl.rs:765:9
          leader.vote(<T1-N0:Q>) >= state.vote(<T2-N0:->); n0.is_initialized() = Err(Panicked)
update  : probe_trigger_elect_on_leader -> same panic
baseline: probe_trigger_elect_on_leader -> same panic
```

Logs: `spec/output/probe-leader-self-elect-update.log`, `spec/output/probe-leader-self-elect-baseline.log`.

## Limits

The reproduced consequence depends on debug assertions. In release builds the leader keeps its
Leader object while re-electing; appends in that window use the old committed vote and the
re-establishment blank is numbered from the candidate's last-log snapshot
(`candidate.rs:111-121`, `leader.rs:83-125`). Whether that can overwrite an acknowledged entry
was not tested and is not claimed.
