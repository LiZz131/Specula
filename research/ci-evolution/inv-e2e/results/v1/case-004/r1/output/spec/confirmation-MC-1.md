# Confirmation record: MC-1

- **Title**: TransferLeader to a learner makes it elect and panics its RaftCore (`target not in quorum set`)
- **Source**: MC (actual counterexample `spec/output/upd-full-NoCorePanic.log`, 12 states; also
  `spec/output/upd-full-ElectionInitiatorIsVoter.log`)
- **Novelty**: NEW within this blind run. No upstream history, issue tracker or prior Specula record
  was consulted (forbidden inputs), and the prior V0 suite has no findings.
- **Status**: REPRODUCED
- **Severity**: High
- **Location**: `openraft/src/core/raft_core.rs:1190-1202` (new TransferLeader branch);
  panic at `openraft/src/proposer/candidate.rs:91-92`
- **Update attribution**: introduced by the update. The panic site is pre-existing, but before the update it is
  unreachable because every `Engine::elect` caller requires `is_voter`
  (`raft_core.rs:1454-1457`, `1206-1213`; `engine_impl.rs:694-704`).

## Description

`RaftCore` handles `RaftMsg::TransferLeader{from,to}` by checking only `engine.state.vote == from`.
When `self.id == to` it calls `Engine::elect()` with no voter check. A learner holding the leader's
committed vote therefore elects itself. Its candidate progress covers voters only
(`proposer/candidate.rs:57-72`). The local self-grant that RaftCore sends after `SaveVote`
(`raft_core.rs:1670-1682`) reaches `Candidate::grant_by(self)`
(`engine/engine_impl.rs:374-376`), whose `.expect("target not in quorum set")` panics, and the
learner's RaftCore stops with `Fatal::Panicked` ("Fatal is unrecoverable and shuts down raft at once",
`error.rs:122-132`).

## Trigger scenario

1. A cluster with voters {0,1,2} and learner 3; leader 0 holds committed vote `<T1-N0:Q>`, and
   learner 3 has replicated the log, so it holds the same vote.
2. The application calls `transfer_leader(<T1-N0:Q>, 3, last_log_id)`, either on node 3 alone or, per
   the documented usage, on every node (`raft/mod.rs:641-642`).
3. Node 3: `TransferLeader` passes the vote check and `elect()` runs. The node becomes Candidate
   `<T2-N3>` with candidate quorum {0,1,2}, then `SaveVote` and `SendVote` run.
4. SaveVote completes and node 3 handles its own VoteResponse: `grant_by(&3)` panics.
5. Peers that received `TransferLeader` have disabled leases, so they grant the term-2 request.
   Leader 0 adopts `<T2-N3>` and steps down, and the cluster stays leaderless until a term-3
   election. Node 2 won that election in the harness run (`traces/window/t99-transfer-to-learner/observations.json`)
   and node 0 won it in the final repro run.

## Developer-intent evidence (requirement, not implementation)

- `openraft/src/docs/data/vote.md:50-51`: "follower and learner in Openraft is almost the same. The only
  difference is a learner does not try to elect itself."
- `openraft/src/raft_state/mod.rs:341-343`: a learner leader "is possible ... Although currently it is
  not supported."
- `openraft/src/error.rs:122`: "Fatal is unrecoverable and shuts down raft at once."
- The `transfer_leader` doc (`raft/mod.rs:635-643`) does not restrict `to` to voters and asks callers to
  invoke it on every node.

## Reproduction

- Test: `harness/repro/t98_specula_repro_transfer_leader_to_learner.rs` (public API only). It asserts
  the correct behaviour: the learner's RaftCore must stay alive.
- Command: `harness/repro/run_repro.sh <clean worktree of d7176ef9> new spec/output/repro/repro-new-update.log`
  (runs `timeout 15m cargo +stable test -p tests --test client_api t98_specula_repro_transfer_leader_to_learner`).
- Escalation level: real interface (live 4-node memstore cluster in-process); deterministic.
- Result on `update` d7176ef9: **both tests FAIL**. The failure is the bug being triggered:
  ```
  thread 'tokio-rt-worker' panicked at openraft/src/proposer/candidate.rs:92:59:
  target not in quorum set: false
  SPECULA_REPRO target_only: learner3.is_initialized = Err(Panicked)
  SPECULA_REPRO all_nodes: n0: alive=Ok(true) state=Leader vote=<T3-N0:Q> leader=Some(0) | ... | n3: alive=Err(Panicked) state=Learner vote=<T1-N0:Q> leader=Some(0)
  test result: FAILED. 0 passed; 2 failed
  ```
- Old-revision control on `baseline` d86101c7 (`harness/repro/t98_specula_control_old_elect_learner.rs`,
  `spec/output/repro/control-old-baseline.log`): `trigger().elect()` on the same learner is refused by the
  `is_voter` guard; the learner stays alive and remains `Learner`; `test result: ok`.
- Independent observations: the RaftCore window trace
  `traces/window/t99-transfer-to-learner/00004-vote-response-n3.ndjson` (`VoteResponsePanic`) and the
  Engine unit trace `traces/elect-learner.ndjson`. Both replay successfully against the faithful model
  (`spec/output/trace-validation-r3/`), and the model's `CoreVoteResponsePanic` step is the only
  transition that admits them.

## Recommendation

Apply the `ExternalCommand::Elect` guard in the TransferLeader branch: elect only if
`self.engine.state.membership_state.effective().is_voter(&self.id)`. Optionally reject a non-voter
`to` in `Raft::transfer_leader`, and make `grant_by` ignore non-quorum targets instead of panicking.
