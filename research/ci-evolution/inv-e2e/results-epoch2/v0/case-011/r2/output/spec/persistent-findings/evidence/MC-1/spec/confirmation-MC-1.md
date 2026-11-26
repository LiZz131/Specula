# Confirmation — MC-1: Pre-Vote round survives leader establishment; the new Leader re-elects itself

- **Source**: MC (actual counterexample: `spec/output/MC-1-counterexample-update-full.log`, 15 states, `Update.cfg`; fault-free variant `spec/output/update-nofault.log`, 14 states, `Update-nofault.cfg`)
- **Violated property**: `Update!LeaderVoteCoversLocalVote` (`\A i : leaderActive[i] => VoteLE(vote[i], leaderVote[i])`)
- **Source revision**: `artifact/` HEAD `3ab6cdd` ("update"); reproduction run on `work-source/` (copy of artifact + test-only harness; memstore hook for Level 3 only)
- **Novelty**: NEW (no persistent record: `specular findings lookup` returned `[]`; no prior finding in the V0 suite). No external trackers were consulted (blind run).
- **Status**: **REPRODUCED** (Level 1 public API; Level 3 timer path), 3/3 runs each, controls clean.
- **Severity**: High — a freshly elected, healthy Leader crashes its `RaftCore` (debug builds: `Fatal::Panicked` from a `debug_assert!`), or in release builds keeps a Leader object whose committed vote is behind the persisted local vote while it campaigns for the next term.
- **Update attribution**: introduced by the update. `pre_elect` (new) runs on a Candidate without dropping `candidate`; `establish_leader` (old) does not clear the new `pre_candidate`; `handle_pre_vote_resp` (new) calls `elect()` without a role/leader check; the runtime gate (new) correlates only by leader id. With Pre-Vote disabled the prior behavior replaces the candidacy (control below; `Update-control-off.cfg`).

## Trigger scenario (from the counterexample)

1. Node 2 (Follower, 3 voters) runs a Pre-Vote round (term 1), gets node 3's grant, and `elect()`s at term 1 → Candidate `(1,2)`.
2. Its election timer expires before the election completes; `handle_tick_election` skips only `ServerState::Leader`, so it calls `pre_elect()`: Pre-Vote round `(2,2)` while the real candidacy `(1,2)` stays alive.
3. Node 3 grants the real vote `(1,2)` and also grants the Pre-Vote `(2,2)` (its vote is the uncommitted `(1,2)`, no lease).
4. The real vote response arrives first → quorum → `establish_leader`: Leader `(1,2,committed)`; `pre_candidate` is **not** cleared.
5. The Pre-Vote response arrives; `does_pre_candidate_vote_match` passes (same leader id `(2,2)`); `handle_pre_vote_resp` reaches quorum and calls `elect()` on the Leader.
6. `do_elect`: `state.vote = (2,2,uncommitted)`, server state Candidate, but `leader` (committed vote `(1,2)`) is kept (`update_internal_server_state` takes the `is_leading` branch). The next `RaftCore::trigger_routine_actions` calls `try_leader_handler` → `debug_assert!(leader.committed_vote >= state.vote)` fails.

## Code evidence (new revision)

- `openraft/src/core/raft_core.rs: handle_tick_election` — Leader skip only; multi-voter + Pre-Vote → `self.engine.pre_elect()`.
- `openraft/src/engine/engine_impl.rs:298 pre_elect` — creates `pre_candidate`, leaves `candidate` untouched.
- `openraft/src/engine/engine_impl.rs:855 establish_leader` — `self.candidate.take()`, no `pre_candidate` reset; `vote_handler::become_leader` does not reset it either.
- `openraft/src/core/raft_core.rs:1803 Notification::PreVoteResponse` and `:2067 does_pre_candidate_vote_match` — only `pre_candidate.is_some()` and leader-id equality.
- `openraft/src/engine/engine_impl.rs:516 handle_pre_vote_resp` — quorum → `self.elect()`; no role check.
- `openraft/src/engine/engine_impl.rs:262 do_elect` — clears `pre_candidate`, not `leader`.
- `openraft/src/engine/engine_impl.rs:968-982 try_leader_handler` — `debug_assert!(leader.committed_vote_ref() >= self.state.vote_ref())`.
- `openraft/src/core/raft_core.rs:908-921 trigger_routine_actions` — calls `try_leader_handler` every loop iteration.

## Reachability notes

The vote RPC timeout is `election_timeout_min` (`raft_core.rs spawn_parallel_vote_requests`), never longer than the node's election timeout, so on the *timer* path the winning vote cannot simply be a network-delayed reply. The timer path needs the Candidate's own election traffic to be processed after its election timer fired, e.g. vote persistence (`save_vote`, awaited inline by `RaftCore::run_command`) slower than the election timeout: queued `Tick` notifications are then handled before the self-grant and before the vote RPCs are even dispatched. The admin path (`trigger().elect(true)` on a Candidate, a documented public API that "does not disrupt a healthy leader") reaches the same state with ordinary network delays.

## Reproduction

Test: `harness/repro/t13_specular_mc1_prevote_reelect.rs` (copied to `work-source/tests/tests/elect/`), script `harness/repro/run-repro.sh`, memstore hook `harness/repro/memstore-savevote-block.patch` (adds `BlockOperation::SaveVote`; test storage only, used by Level 3).

Command: `harness/repro/run-repro.sh 3` (→ `RUSTUP_TOOLCHAIN=nightly-2026-03-01 timeout 5m cargo test -p tests --test elect specular_mc1 -- --nocapture --test-threads=1`)

| Test | Level | Mechanism | Result (3/3) |
|---|---|---|---|
| `specular_mc1_level1_admin_prevote_on_candidate` | 1 (public API; router post-hook delays node 2's real-vote reply by 250 ms and its Pre-Vote reply by 400 ms, both below the 500 ms RPC ttl) | timer Pre-Vote → elect T2; `trigger().elect(true)` while Candidate; T2 vote reply → Leader; Pre-Vote reply → elect T3 | REPRODUCED |
| `specular_mc1_level3_timer_path_slow_vote_persistence` | 3 (test-storage delay: node 1 `save_vote` 900 ms > election timeout 500 ms; Pre-Vote reply delayed 200 ms) | purely timer driven | REPRODUCED |
| `specular_mc1_control_level1_no_prevote_round` | control | same schedule, no Pre-Vote round on the Candidate | stable T2 Leader, no assertion |
| `specular_mc1_control_level3_prevote_disabled` | control | same slow storage, `enable_pre_vote = false` | no assertion |

Observed output (from `spec/output/repro-MC-1-run3.log`, identical in `repro-MC-1-reliability.log`):

```
specular: t=1.315301346s node1 state=Leader term=2 vote=<T2-N1:Q> leader=Some(1)
thread 'tokio-rt-worker' panicked at openraft/src/engine/engine_impl.rs:977:9:
leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)
specular: captured panic: openraft/src/engine/engine_impl.rs:977 | leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)
specular: client_write on node 1 after the term bump -> Ok(Err(Fatal(Panicked)))
SPECULAR-MC1-REPRODUCED level=1: ...
SPECULAR-MC1-REPRODUCED level=3: ...
SPECULAR-MC1-CONTROL-OK level=1
SPECULAR-MC1-CONTROL-OK level=3
test result: ok. 4 passed; 0 failed
```

Backtrace (`RUST_BACKTRACE=1`): `Engine::try_leader_handler` ← `RaftCore::trigger_routine_actions` ← `RaftCore::runtime_loop`.

Match with the counterexample: same action sequence (Pre-Vote on a Candidate → real election wins → Pre-Vote quorum → `elect()` on the Leader), same violated relation (`leader.committed_vote (T,self,committed) < state.vote (T+1,self,uncommitted)` = `LeaderVoteCoversLocalVote`), same code path. The engine-level implementation trace `traces/candidate_prevote_then_leader.ndjson` also reaches that state (`spec/output/trace-update-property-candidate_prevote_then_leader.log`).

Expected behavior: a Pre-Vote round should not outlive the node's transition to Leader (or `handle_pre_vote_resp`/the gate should ignore the response unless the node is still a non-leader whose vote is unchanged), so an established Leader never bumps its own term from a stale Pre-Vote round.

## Recommendation

Clear `pre_candidate` when a leader is established (`establish_leader` / `become_leader`), and/or in `handle_pre_vote_resp` (or the runtime gate) drop the response when the node is a Leader or its vote no longer equals the vote the round was derived from (`pre_candidate.vote.term == vote.term + 1` and not leading). Consider also dropping the old `candidate` (or not starting a Pre-Vote round) while a real candidacy is still running.

## Re-running on other revisions

`harness/repro/t13_specular_mc1_level1_only.rs` contains only the Level 1 test and its control and needs no memstore hook; it requires the Pre-Vote API (`Config::enable_pre_vote`, `trigger().elect(bool)`). On a tree with the defect: `SPECULAR-MC1-REPRODUCED level=1` (test passes). On a tree without it: the reproduction test fails with `BUG NOT TRIGGERED (level 1)` while the control passes. Verified on this tree: `test result: ok. 2 passed` (`cargo test -p tests --test elect specular_mc1 -- --nocapture --test-threads=1`).
