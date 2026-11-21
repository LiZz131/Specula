# Provenance

Everything used came from `/work`. There was no network access and `git` was never run directly. Scratch files are in `/work/out/tmp/`.

## `tools/hist.sh` commands (in order run)

| # | Command | Purpose / result |
|---|---|---|
| 1 | `tools/hist.sh` (no args) | usage |
| 2 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' ee460f37` (piped to `head -80`) | message for GrantedResponseAfterDurable / DurableVoteNotAhead |
| 3 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 88754e09` (`head -80`) | message for GrantedResponseAfterDurable / VoteRequestAfterDurable |
| 4 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 36d2c115` (`head -80`) | message for GrantedResponseAfterDurable / VoteRequestAfterDurable / CertifiedLeaderHasFrozenQuorum |
| 5 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 3fd1d8aa` (`head -80`) | message for MembershipAtMostOneOutstanding |
| 6 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 2666d3d3` (`head -80`) | commit named in DurableVoteNotAhead note |
| 7 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 4060ba16` (`head -80`) | commit named in VoteRequestAfterDurable note |
| 8 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 453e80d1` (`head -80`) | commit named in VoteRequestAfterDurable note |
| 9 | `tools/hist.sh log -S'Demote the vote in memory only' --oneline -- openraft/src/engine/engine_impl.rs` | → f4b5f61d |
| 10 | `tools/hist.sh show --format='%H%n%an %ad%n%B' f4b5f61d -- openraft/src/engine/engine_impl.rs openraft/src/config/config.rs` (`head -120`) | leader-restore commit message and config doc diff |
| 11 | `tools/hist.sh log -S'flushed <= submitted <= accepted' --oneline` | → 2666d3d3, ee460f37 (reproduces DurableVoteNotAhead note) |
| 12 | `tools/hist.sh log -S'fn new_candidate' --oneline -- openraft/src/engine/engine_impl.rs` | → 36d2c115 (reproduces CertifiedLeader note) |
| 13 | `tools/hist.sh log -S'quorum_set' --oneline -- openraft/src/proposer/candidate.rs` | → 36d2c115 (reproduces CertifiedLeader note) |
| 14 | `tools/hist.sh log -S'SendVote' --oneline` (`head -20`) | first 20 hits include 1e00adfe, 15f927e1, ee460f37, 36d2c115, 88754e09, 453e80d1 (VoteRequest note); 4060ba16 was not among the first 20 |
| 15 | `tools/hist.sh log -S'spawn_parallel_vote_requests' --oneline` | → 453e80d1, 27f589f5, 4792350d |
| 16 | `tools/hist.sh log -S'save_vote(&vote)' --oneline` | → cfcfc071, 88754e09 |
| 17 | `tools/hist.sh show 36d2c115 -- openraft/src/core/raft_core.rs` (grep for `Command::SaveVote`) | confirms the local self-grant `VoteResponse` was added after `save_vote` |
| 18 | `tools/hist.sh log -1 --format=%B <c>` for ee460f37, 88754e09, 36d2c115, 3fd1d8aa | **discarded**: the wrapper prepends `base`, so this printed the base commit's message |
| 19 | `tools/hist.sh show -s --format=%B <c>` for ee460f37, 88754e09, 36d2c115, 3fd1d8aa | whitespace-normalized quote check of the four `history` evidence lines (all found) |
| 20 | `tools/hist.sh show -s --format=%B f4b5f61d` | quote check for the DurableVoteNotAhead note |

## Files read

### Rules, tooling, model
- `/work/ANNOTATION-RULES.md` (full)
- `/work/tools/hist.sh` (full)
- `/work/spec-original/MC.cfg`, `MC-membership.cfg`, `Trace.cfg`, `base.cfg` (full)
- `/work/spec-original/base.tla` (full)
- `/work/spec-original/{MC,Trace,base}.tla` vs `/work/spec-annotated/*` (diff)
- `/work/spec-annotated/MC.tla`, `/work/spec-annotated/Trace.tla` (full)
- `/work/out/spec-reviewed/base.tla` lines 555-754 (before editing), plus diffs after editing
- `/work/source/CLAUDE.md` (loaded automatically as session context; not used as evidence)

### Source (`/work/source/...`), with ranges
- `openraft/src/raft_state/io_state/io_progress.rs` 1-80
- `openraft/src/docs/data/log_io_progress.md` (full)
- `openraft/src/docs/data/io_id.md` (full)
- `openraft/src/raft_state/io_state/io_id.rs` 1-120
- `openraft/src/raft_state/io_state.rs` (all comment lines, ~22-114)
- `openraft/src/docs/data/log_pointers.md` 1-75 (plus a grep of the whole file)
- `openraft/src/storage/v2/raft_log_storage.rs` 40-128
- `openraft/src/engine/handler/vote_handler/mod.rs` 95-200
- `openraft/src/docs/data/vote.md` (full)
- `openraft/src/raft_state/mod.rs` 415-475 (plus a grep for `accepted|accept_log_io`)
- `openraft/src/engine/tests/elect_test.rs` 1-110
- `openraft/src/engine/tests/handle_vote_resp_test.rs` 1-240
- `openraft/src/core/raft_core.rs` 515-560, 845-870, 1085-1130, 1160-1175, 1370-1378, 1470-1505, 2115-2215
- `openraft/src/engine/command.rs` 330-420
- `openraft/src/engine/engine_impl.rs` 100-200
- `openraft/src/engine/engine_output.rs` 14-24
- `openraft/src/config/config.rs` 490-510 (plus a grep for `enable_leader_restore`)
- `openraft/src/proposer/candidate.rs` 85-135
- `raft-essentials.md` 40-60, 95-115 (plus a grep for `stable storage|before responding|persist`)
- `openraft/src/quorum/quorum_set_impl.rs` 20-50
- `openraft/src/raft_state/membership_state/mod.rs` 15-60, 110-210, 265-281
- `openraft/src/raft_state/membership_state/change_handler.rs` 1-68
- `openraft/src/raft_state/membership_state/change_handler_test.rs` 1-70
- `openraft/src/raft_state/membership_state/membership_state_test.rs` 85-120
- `openraft/src/docs/cluster_control/dynamic-membership.md` 25-60
- `openraft/src/docs/data/effective-membership.md` (full)
- `openraft/src/docs/protocol/io_ordering.md` (grep for `vote|before|must`)
- Directory listings: `openraft/src/docs/data`, `openraft/src/docs/protocol`, top of `source/`

### Script-driven reads (quote, line and symbol checks)
- `out/tmp/checkquotes.py` and `out/tmp/checkquotes2.py` opened every file cited by a `source/` evidence line and looked at the cited line ±5. That covers the files above plus `openraft/src/storage/helper.rs` (line 89).
- Watch-symbol existence greps over: `io_progress.rs`, `vote_handler/mod.rs`, `raft_core.rs`, `engine_impl.rs`, `storage/helper.rs`, `following_handler/mod.rs`, `raft_log_storage.rs`, `command.rs`, `engine_output.rs`, `raft_state/mod.rs`, `server_state_handler/mod.rs`, `proposer/candidate.rs`, `quorum_set_impl.rs`, `membership/membership_impl_quorum_set.rs`, `membership_state/mod.rs`, `change_handler.rs`, `config/config.rs`.
- Greps over `openraft/src`: `byzantine|forged|authenticat` (no matches); `persisted vote|saved vote|vote.*persist|persist.*vote`; `in memory|in-memory` in `docs/`; respond/reply comments containing `after|until|wait|flush|persist|must` in `raft_core.rs`, `command.rs`, `engine_output.rs`, `engine_impl.rs`, `vote_handler/mod.rs`.

### Tools
- `/work/lib/tla2tools.jar`, `/work/lib/CommunityModules-deps.jar` (SANY)
- Scratch: `out/tmp/checkquotes.py`, `out/tmp/checkquotes2.py`, `out/tmp/structcheck.py`, `out/tmp/sany_{base,MC,Trace}.log`
