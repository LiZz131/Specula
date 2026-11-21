# Bug Report — Openraft (incremental run: `update` d7176ef9, `RaftMsg::TransferLeader`)

## Summary

- Update scenarios tested: U1 (non-voter transfer target, learner and absent), U2 (stale `from`),
  U3 (voter transfer + commit), U4 (crash around transfer).
- Bugs found: 1 (MC-1, update-introduced, reproduced on the real implementation).
- Additional pre-existing model-checking observation: 1 (MC-2, independent of the update,
  unresolved; see "Other counterexamples").
- Configs run: `MC.cfg`, `Update_full_ElectionInitiatorIsVoter.cfg`, `Update_full_NoCorePanic.cfg`,
  `Update_full.cfg`, `Update_full_voter.cfg`, `Update_focused.cfg`, `Update_focused_voter.cfg`,
  `Update_open.cfg`, `Update_discharge.cfg`, `Update_hunt_U1_absent.cfg`,
  `Update_hunt_U1_absent_nodsb.cfg`, `Update_hunt_U3_voter.cfg`, `Update_hunt_U4_crash.cfg`,
  `Update_canary_*.cfg` (outcomes in the table at the end and in `spec/output/`).

## Bug 1: TransferLeader to a learner makes it elect and panics its RaftCore (`target not in quorum set`)

- **ID**: MC-1
- **Scenario**: U1 — non-voter transfer target (affected action `HandleTransferLeader` ->
  `Elect` -> old consumer `ReceiveVoteResponse`/`Candidate::grant_by`)
- **Severity**: High (unrecoverable `Fatal::Panicked` of the target's Raft core through a public API
  call with documented usage; the vote requests it already sent also depose the current leader)
- **Invariant violated**: `NoCorePanic` (also `ElectionInitiatorIsVoter`, `CandidateIsVoterOfSnapshot`)
- **Config**: `spec/Update_full_NoCorePanic.cfg` (full `MCNext`); also `Update_full_ElectionInitiatorIsVoter.cfg`,
  `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg`
- **Counterexample**: 12 states, `spec/output/upd-full-NoCorePanic.log`
  (`spec/output/upd-full-NoCorePanic.cex.json`); 11 states for the action property,
  `spec/output/upd-full-ElectionInitiatorIsVoter.log`

### Trace Summary

1. States 1-8: node 1 (voter) elects at term 1, persists its vote, voter 2 grants, node 1 handles
   its self-grant and voter 2's grant and becomes leader with committed vote `(1,1)` and blank `(1,1)@1`.
2. State 9: learner 3 (effective config `{{1,2}}`, learners `{3}`) accepts leader 1's AppendEntries:
   its vote becomes `(1,1,committed)` and it stays `Learner`.
3. State 10 (`MCTransferLeader(3)`, the update): `TransferLeader{from=(1,1,committed), to=3}` is
   handled at node 3; its vote equals `from`, so RaftCore calls `Engine::elect()` with no voter check.
   Node 3 becomes `Candidate` with vote `(2,3)` and a candidate quorum set `{{1,2}}` that does not
   contain itself; `SaveVote` and `SendVote` are queued.
4. State 11: `SaveVote` completes; RaftCore sends node 3 its own `VoteResponse(target = 3)`.
5. State 12: node 3 handles its own grant: `resp.vote == candidate.vote`, so
   `Candidate::grant_by(&3)` runs; 3 is not in the voter-only candidate progress and
   `.expect("target not in quorum set")` panics. Node 3's RaftCore stops (`corePanic[3] = TRUE`).

### Root Cause

`RaftMsg::TransferLeader` is handled in `RaftCore::handle_api_msg` by checking only
`engine.state.vote == from` and then calling `self.engine.elect()` when `self.id == to`
(`openraft/src/core/raft_core.rs:1190-1202`). Every pre-update caller of `Engine::elect` first
requires the node to be a voter of its effective membership: tick election
(`raft_core.rs:1454-1457`), `ExternalCommand::Elect` (`raft_core.rs:1206-1213`) and `initialize`
(`engine/engine_impl.rs:694-704`). `Engine::elect` itself has no guard (`engine_impl.rs:223-249`):
for a learner it creates a candidate whose progress is built from the voter quorum set only
(`proposer/candidate.rs:57-72`), keeps it because the learner is a member (`raft_state/mod.rs:369-371`),
and emits `SaveVote`/`SendVote`. After `SaveVote`, RaftCore always delivers the local self-grant
(`raft_core.rs:1670-1682`), which reaches `Candidate::grant_by` (`engine_impl.rs:374-376`), which
panics for an id outside the quorum set (`proposer/candidate.rs:91-92`). The `transfer_leader` API
(`raft/mod.rs:645-703`) does not validate `to` either, and documents "Call this method on every node
in the cluster with the same arguments" (`raft/mod.rs:641-642`). The documented role rule is that "a
learner does not try to elect itself" (`docs/data/vote.md:50-51`).

Absent-node variant (same root cause, no panic): a node removed from its effective membership that
still holds `from` also runs `Engine::elect()`; `become_following` drops the candidate
(`engine/handler/vote_handler/mod.rs:241-252`) but `SendVote` is still emitted with a higher term,
which can depose the current leader (`CanaryAbsentElect`, `traces/elect-absent.ndjson`).

### Real-system reproduction

- `harness/repro/t98_specula_repro_transfer_leader_to_learner.rs`, run with
  `harness/repro/run_repro.sh <clean update worktree> new <log>` (public API only, no instrumentation).
  On `update` d7176ef9: both tests FAIL. Learner 3 panics at `openraft/src/proposer/candidate.rs:92:59`
  ("target not in quorum set") and `is_initialized()` returns `Err(Panicked)`. In the all-nodes variant the
  term-2 vote requests depose leader 0, and the cluster re-elects at term 3
  (`spec/output/repro/repro-new-update.log`).
- Old-revision control (`baseline` d86101c7, no `transfer_leader`): `trigger().elect()` on the same
  learner is refused by the `is_voter` guard; no panic, still `Learner`
  (`spec/output/repro/control-old-baseline.log`). The panic path is unreachable before the update.
- The same panic appears in the RaftCore window trace
  `traces/window/t99-transfer-to-learner/00004-vote-response-n3.ndjson` (`VoteResponsePanic`), which
  replays against `Trace.tla` (`spec/output/trace-validation-r3/`), and in the unit trace
  `traces/elect-learner.ndjson`.

### Affected Code

- `openraft/src/core/raft_core.rs:1190-1202`: TransferLeader branch calls `engine.elect()` without `is_voter`.
- `openraft/src/raft/mod.rs:645-703`: `transfer_leader` accepts any `to`.
- `openraft/src/proposer/candidate.rs:91-92`: `grant_by` panics for a target outside the quorum set.
- `openraft/src/core/raft_core.rs:1670-1682`: SaveVote completion delivers the local self-grant.

### Recommendation

Handle `TransferLeader` only when the target is a voter of its effective membership (the same
`effective().is_voter(&self.id)` guard as `ExternalCommand::Elect`), and optionally reject a non-voter
`to` in `Raft::transfer_leader`. Defensively, `grant_by` could ignore a non-quorum target instead of
panicking.

---

## Other counterexamples (not update-related)

### MC-2 (NEEDS MORE INFO): persisted `committed` can run ahead of the leader's durable log

`Update_hunt_U1_absent.cfg` (three initial voters) violated the V0 reference invariant
`DurableStateBounded` before any transfer (`spec/output/upd-hunt-U1-absent-DurableStateBounded.log`,
19 states). Leader 1 commits its blank entry with acks from voters 2 and 3 before its own log flush,
and `SaveCommitted` has no flush condition (`engine/command.rs:240`). The persisted committed id
therefore exceeds the leader's durable log. `docs/data/log_pointers.md:28-34` states that
`committed <= flushed` need not hold. But `RaftState::validate` requires
`committed <= last_log_id` (`raft_state/mod.rs:177`), and `StorageHelper::get_initial_state` re-applies
up to the persisted committed id after a restart (`storage/helper.rs:63-100`). Whether a crash can leave the
persisted committed id beyond the persisted log depends on how the storage orders `save_committed`
against append flushes, and the `RaftLogStorage::save_committed` contract (`storage/v2.rs:66-85`) leaves
that unspecified. The mechanism is unchanged by the update, and V0 never explored a configuration with three initial voters.
The property was not edited; the finding is left unresolved for separate work.

---

## Not Reproduced / campaign outcomes

See the table in `spec/output/model-checking-summary.md` (states, depth, queue, budget) for every
campaign. All clean results are budget-limited (`LIMITED_COVERAGE`), not proofs.

## Spec fixes during checking

- Case B (bound artifact): `MCVoteResponse` explores a winning response only while the
  establishment blank fits `MaxIndex` (`spec/output/mc-standard-iter01-typeok.log`).
