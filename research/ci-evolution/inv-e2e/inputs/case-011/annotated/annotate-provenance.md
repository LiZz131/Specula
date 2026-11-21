# Provenance

Everything here was read from `/work`; no network access was used and `git` was never run directly.
All history access went through `tools/hist.sh`. From the third command on, calls went through a
logging wrapper (`out/tmp/h.sh`), which appended each invocation to `out/tmp/hist-log.txt` and then
executed `tools/hist.sh` unchanged.

## `tools/hist.sh` commands (complete, in order)

| # | Command | Purpose / result |
|---|---|---|
| 1 | `tools/hist.sh` (no arguments) | usage text |
| 2 | `tools/hist.sh log --oneline -5` | most recent commits (base is `f4b5f61d`) |
| 3 | `tools/hist.sh log -S'IOFlushed' --oneline -- openraft/src/core/raft_core.rs` | -> 15f927e1, 9206d947, ee460f37, c55a58d4 |
| 4 | `tools/hist.sh log -S'io_id: IOId::new(self.engine.state.vote_ref())' --oneline -- openraft/src/core/raft_core.rs` | -> 262524cd |
| 5 | `tools/hist.sh show ee460f37 --stat` | message: "Ensure `Respond` Waits for IO Completion" (GrantedResponseAfterDurable evidence) |
| 6 | `tools/hist.sh show ee460f37` | diff comments |
| 7 | `tools/hist.sh log -S'SendVote' --oneline -- openraft/src/engine/engine_impl.rs openraft/src/core/raft_core.rs` | -> b912cc24, 88754e09, 870037e3, 4060ba16 |
| 8 | `tools/hist.sh show 4060ba16 --stat` | Engine/Runtime introduction; no ordering rule |
| 9 | `tools/hist.sh show 4060ba16` | SaveVote/SendVote introduced as TODO commands |
| 10 | `tools/hist.sh log -S'spawn_parallel_vote_requests' --oneline` | -> 453e80d1, 27f589f5, 4792350d |
| 11 | `tools/hist.sh log --all --oneline -i --grep='vote'` | rejected by hist.sh: "option --all is not allowed" |
| 12 | `tools/hist.sh log --oneline -i --grep='persist.*vote\|vote.*persist\|save.*vote.*before\|before.*send'` | -> f4b5f61d, 558e1b94, 2a74b920, ea017289, 20832eef, 7d4ebdcb, 229f3368 |
| 13 | `tools/hist.sh show f4b5f61d --stat` | `enable_leader_restore` message (concerns.md C1) |
| 14 | `tools/hist.sh show f4b5f61d` | diff: startup demotion comment, startup test |
| 15 | `tools/hist.sh log -S'at most one outstanding' --oneline -- openraft/src/raft_state/membership_state/mod.rs` | -> ffa876c5 |
| 16 | `tools/hist.sh log -S'at most only one non-committed membership' --oneline` | -> 0399bb60 |
| 17 | `tools/hist.sh show 453e80d1 --stat` | candidate loop moved to Engine |
| 18 | `tools/hist.sh show 453e80d1` | old code: `save_vote().await` then "Send RPCs"; narration only |
| 19 | `tools/hist.sh log --oneline -i --grep='vote request\|vote-request\|RequestVote'` | -> 1e00adfe, b262f054, ee460f37, b06cbb37, 36d2c115, 90c29ccb, 97fa1581, e9382ffd, 1f3a74db, 61af8892, 27b6987e, 86e2ccd0 |
| 20 | `tools/hist.sh log --oneline -i --grep='SaveVote'` | -> f4b5f61d, ee460f37, 36d2c115 |
| 21 | `tools/hist.sh show 36d2c115 --stat` | message: "`Voting` state is now updated only after `SaveVote` is successfully persisted" |
| 22 | `tools/hist.sh show 86e2ccd0 --stat` | single-candidate self-vote fix; not counted |
| 23 | `tools/hist.sh show 36d2c115` | diff comments (grep) |
| 24 | `tools/hist.sh show 36d2c115` | saved to `out/tmp/36d2c115.diff`; `new_candidate` and elect() changes |
| 25 | `tools/hist.sh log --oneline -25` | recent commits |
| 26 | `tools/hist.sh show 408b55f5 --stat` | RefreshServerState fencing; not property-relevant |
| 27 | `tools/hist.sh show b262f054 --stat` | non-committed vote adoption on rejected vote response |
| 28 | `tools/hist.sh show 1e00adfe --stat` | leadership-transfer flag overrides lease |
| 29 | `tools/hist.sh log -S'fn new_candidate' --oneline -- openraft/src/engine/engine_impl.rs` | -> 36d2c115 |
| 30 | `tools/hist.sh log -S'membership.learner_ids()' --oneline -- openraft/src/engine/engine_impl.rs` | -> 36d2c115 |
| 31 | `tools/hist.sh log -S'save_vote(&vote)' --oneline -- openraft/src/core/raft_core.rs` | -> 88754e09 |
| 32 | `tools/hist.sh log -S'quorum_set' --oneline -- openraft/src/proposer/candidate.rs` | -> 36d2c115 |
| 33 | `tools/hist.sh log -S'voter_ids()' --oneline -- openraft/src/core/raft_core.rs` | -> eeeff6f3, 5be19695, 9906d6e9, 4a91fd4d, 9bc3434f, 7f00948d (not opened) |
| 34 | `tools/hist.sh show 88754e09 --stat` | message: "response must be after executing the commands"; "Command execution can be reordered" |
| 35 | `tools/hist.sh show 88754e09` | diff around `save_vote(&vote)` |
| 36 | `tools/hist.sh log -S'flushed <= submitted <= accepted' --oneline` | -> 2666d3d3, ee460f37 |
| 37 | `tools/hist.sh log -S'Demote the vote in memory only' --oneline` | -> f4b5f61d |
| 38 | `tools/hist.sh log -S'at most one outstanding, uncommitted membership log' --oneline` | -> d7afc721, 3fd1d8aa |
| 39 | `tools/hist.sh show 3fd1d8aa --stat` | message states "(2) there is at most one outstanding, uncommitted membership log." |
| 40-45 | `tools/hist.sh log -1 --format=%B <c>` for ee460f37, 88754e09, 36d2c115, 3fd1d8aa, 88754e09, ee460f37 | quote-verification attempt; hist.sh printed the base commit's message instead of `<c>`, so the output was discarded |
| 46-50 | `tools/hist.sh show <c>` for ee460f37, 88754e09, 36d2c115, 3fd1d8aa, 88754e09 | quote verification: every history quote matched (see check.md) |

## Files read

Unless marked otherwise, files were read in full or over the stated line range. "grep" means only grep
hits were seen.

### Model (`/work/spec-original/`)
- `base.tla` (full), `MC.tla` (full), `Trace.tla` (full)
- `base.cfg`, `MC.cfg`, `MC-membership.cfg`, `Trace.cfg` (full)

### Source (`/work/source/`)
- `CLAUDE.md` (first 50 lines; later shown in full by the harness)
- `raft-essentials.md` (full)
- `openraft/src/engine/handler/vote_handler/mod.rs` (1-260)
- `openraft/src/engine/engine_impl.rs` (90-760)
- `openraft/src/core/raft_core.rs` (518-580, 840-875, 1093-1138, 1340-1510, 2080-2260; grep for `send_satisfied_responds`, `run_command`, `handle_vote_request`, `IOFlushed`, ordering phrases)
- `openraft/src/engine/command.rs` (grep; 326-352)
- `openraft/src/engine/engine_output.rs` (49-91)
- `openraft/src/engine/respond_command.rs` (1-30)
- `openraft/src/core/io_flush_tracking/mod.rs` (1-26)
- `openraft/src/storage/v2/raft_log_storage.rs` (full)
- `openraft/src/storage/helper.rs` (60-230)
- `openraft/src/raft_state/mod.rs` (169-192, 400-505)
- `openraft/src/raft_state/io_state.rs` (165-190)
- `openraft/src/raft_state/io_state/io_progress.rs` (grep of comments, cursors, validate, tests)
- `openraft/src/raft_state/membership_state/mod.rs` (1-281)
- `openraft/src/raft_state/membership_state/change_handler.rs` (full)
- `openraft/src/raft_state/membership_state/change_handler_test.rs` (grep; 30-50)
- `openraft/src/raft_state/membership_state/membership_state_test.rs` (grep; 100-118)
- `openraft/src/engine/handler/server_state_handler/mod.rs` (full)
- `openraft/src/engine/handler/server_state_handler/update_server_state_test.rs` (grep)
- `openraft/src/engine/handler/following_handler/mod.rs` (grep `membership`; 155-186)
- `openraft/src/engine/handler/vote_handler/accept_vote_test.rs` (grep)
- `openraft/src/engine/tests/elect_test.rs` (1-140)
- `openraft/src/engine/tests/handle_vote_req_test.rs` (grep)
- `openraft/src/engine/tests/handle_vote_resp_test.rs` (grep; 136-240)
- `openraft/src/engine/tests/startup_test.rs` (1-80, 236-272)
- `openraft/src/proposer/candidate.rs` (full)
- `openraft/src/membership/membership_impl_quorum_set.rs` (1-40)
- `openraft/src/membership/membership.rs` (270-345)
- `openraft/src/quorum/quorum_set_impl.rs` (1-60)
- `openraft/src/errors/mod.rs` (grep `InProgress`)
- `openraft/src/docs/data/vote.md` (full)
- `openraft/src/docs/data/leader-lease.md` (1-80)
- `openraft/src/docs/data/io_id.md` (full)
- `openraft/src/docs/data/log_io_progress.md` (full, 56 lines)
- `openraft/src/docs/data/effective-membership.md` (full)
- `openraft/src/docs/protocol/io_ordering.md` (full)
- `openraft/src/docs/cluster_control/joint-consensus.md` (full)
- `openraft/src/docs/cluster_control/dynamic-membership.md` (1-80)
- `openraft/src/docs/components/engine-runtime.md` (full)
- `tests/tests/life_cycle/t50_leader_restart_leader_restore_disabled.rs` (full)

### Directory listings and grep-only sweeps (no file content counted beyond the hits)
- Directory listings: `source/`, `openraft/src/`, `openraft/src/docs/**`, `openraft/src/engine/tests/`,
  `engine/handler/vote_handler/`, `raft_state/`, `raft_state/io_state/`, `raft_state/tests/`,
  `raft_state/membership_state/`, `quorum/`, `tests/tests/`, `tests/tests/elect/`, `tests/tests/life_cycle/`
- `grep -rn` over `openraft/src` (`*.rs`, `*.md`) for persist/flush-before-respond phrases
- grep for `fn save_vote`; for `SendVote` in test files; for `IOFlushed` in tests and non-tests; for
  `allow_log_reversion`; for `change_handler()|change_membership|ensure_committed`
- `grep -rli` over `tests/tests` for vote/persist/save_vote/flush (file names only)
- `grep -n` over `raft-essentials.md`, `derived-from-async-raft.md`, `README.md` for stable/persist/durab
- `grep -rn -i` over the whole source for `byzantine|forged|forge|authenticat` (no hits)

### Scratch files written (`/work/out/tmp/`)
- `h.sh`: logging wrapper around `tools/hist.sh`
- `hist-log.txt`: raw command log
- `36d2c115.diff`: output of `tools/hist.sh show 36d2c115`
- `annotate.py`: inserts the blocks (insert-only)
- `check.py`, `check-out.txt`: coverage and evidence-location checks
- `sany.txt`: SANY output
