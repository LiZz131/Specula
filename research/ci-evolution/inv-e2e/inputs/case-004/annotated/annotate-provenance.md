# Provenance

All work used only `/work`. No network access, no direct `git`. History was read only through `/work/tools/hist.sh`.

From the first `log` command onward I ran it through a logging wrapper, `/work/out/tmp/h.sh`, which appends the arguments to `/work/out/tmp/hist_commands.log` and then `exec`s `/work/tools/hist.sh`. The first three commands below were logged by hand.

## `tools/hist.sh` commands I ran (in order)

| # | Command | Purpose / result |
|---|---|---|
| 1 | `tools/hist.sh` | usage text |
| 2 | `tools/hist.sh log --oneline -5` | base = `7fa0f9b7 Refactor: Use stored lease in RaftState.vote for election decisions` |
| 3 | `tools/hist.sh log --oneline` (piped to `wc -l`) | 2120 commits |
| 4 | `tools/hist.sh log --oneline` (piped to `grep -n 955ebf1`) | baseline id named in `base.tla` header: **not found** (concerns C12) |
| 5 | `tools/hist.sh log -1 --format='%H %ad %s'` | `7fa0f9b77b37c4bf2e63c8601160a3e10c3e17e3`, Thu Aug 1 2024 |
| 6 | `tools/hist.sh show ada27b44 --stat` | commit splitting `Command::Commit` into `SaveCommitted` and `Apply` |
| 7 | `tools/hist.sh show ada27b44` (grep for added comments) | `SaveCommitted` doc comment; no ordering rule beyond `engine/command.rs:68-77` |
| 8 | `tools/hist.sh log -S'std::cmp::min(accepted, leader_committed)' --oneline -- openraft/src/engine/handler/following_handler/mod.rs` | `90c29ccb Improve: follower stores the accepted log id` |
| 9 | `tools/hist.sh log -S'less_equal!(self.committed(), self.last_log_id())' --oneline -- openraft/src/raft_state/mod.rs` | `808110de Refactor: move RaftState to dir raft_state` (a move only; not used) |
| 10 | `tools/hist.sh show 90c29ccb --stat` | message: "allow followers to commit only those logs that have been replicated by their current leader" |
| 11 | `tools/hist.sh show 90c29ccb -- openraft/src/engine/handler/following_handler/mod.rs` | removed comment "A follower can only commit the entries that are replicated by the leader." |
| 12 | `tools/hist.sh show 90c29ccb^:openraft/src/engine/handler/following_handler/mod.rs` (piped to `grep -n`) | removed comment is at line 113 of the parent |
| 13 | `tools/hist.sh log -1 --format=%h 90c29ccb^` | (printed the base, because `hist.sh log` prepends `base`; discarded) |
| 14 | `tools/hist.sh show -s --format='%h %P' 90c29ccb` | parent = `5a8b67585360fa01fcf38705591d2df58e89182f` |
| 15 | `tools/hist.sh log -S'fn save_committed' --oneline -- openraft/src` | `942ec78b Feature: save committed log id` (oldest), `23e856b1`, `d7a9810f` |
| 16 | `tools/hist.sh log -S'All write-IO must be serialized' --oneline -- openraft/src` | `8d7854b5 Chore: add doc comment to v2 storage api` |
| 17 | `tools/hist.sh show 942ec78b --stat` | message: "Save the committed log id to storage before Raft apply log entries." / "re-apply log entries ... to the committed log id" |
| 18 | `tools/hist.sh show 942ec78b` (grep for added comments) | `save_committed` doc comments; TODO in `raft_core` |
| 19 | `tools/hist.sh show 8d7854b5` | origin of `storage/v2.rs:25-36` ("All write-IO must be serialized ...") |
| 20 | `tools/hist.sh log -S'It grants the input vote and persists it' --oneline` | `8c7c05c3` (rename only) |
| 21 | `tools/hist.sh log -S'Leadership is granted by a quorum and the vote is committed' --oneline` | `f4564fec Refactor: fix handling of non-voter leader` |
| 22 | `tools/hist.sh log -S'Committed means: a log that is replicated to a quorum' --oneline` | `ca8a09c1`, `4060ba16` |
| 23 | `tools/hist.sh show -s --format=%B 942ec78b` (piped to `cat -A`) | exact message line breaks for the quotes |
| 24 | `tools/hist.sh show -s --format=%B 90c29ccb` | exact message text for the quote |
| 25 | `tools/hist.sh log -S'debug_assert!(self.leader.is_none())' --oneline -- openraft/src/engine/engine_impl.rs` | `36d2c115 Refactor: Enhance Election and Replication` |
| 26 | `tools/hist.sh log -S'pub(crate) type LeaderState<C>' --oneline -- openraft/src` | `36d2c115` |
| 27 | `tools/hist.sh show -s --format=%B 36d2c115` | message: "Upon election completion, `Engine.candidate` is cleared, and a new `Leader` is assigned to `Engine.leader`." and "re-creating the Leader upon startup" |

The wrapper's raw log is `/work/out/tmp/hist_commands.log`.

## `tools/hist.sh` commands run by the checker script

`/work/out/tmp/check_evidence.py` calls `/work/tools/hist.sh` directly, not through the wrapper, to verify history quotes. It ran 4 times:

| Run | Calls |
|---|---|
| 1 (3 history lines unparsed) | `tools/hist.sh show 5a8b6758:openraft/src/engine/handler/following_handler/mod.rs` |
| 2 | `tools/hist.sh show -s --format=%B 942ec78b` (×2), `tools/hist.sh show -s --format=%B 90c29ccb`, `tools/hist.sh show 5a8b6758:openraft/src/engine/handler/following_handler/mod.rs` |
| 3 (after adding the 36d2c115 line) | as run 2, plus `tools/hist.sh show -s --format=%B 36d2c115` |
| 4 (final) | as run 3 |

## Files read

### Model and tools

- `/work/spec-original/base.tla`, `MC.tla`, `Trace.tla`, `base.cfg`, `MC.cfg`, `Trace.cfg` (all in full)
- `/work/tools/hist.sh` (in full); `/work/tools/network-guard/` and `/work/lib/` (listing only)

### Source: documentation (read in full unless noted)

- `source/openraft/src/docs/data/log_pointers.md`
- `source/openraft/src/docs/data/vote.md`
- `source/openraft/src/docs/data/effective-membership.md`
- `source/openraft/src/docs/data/extended-membership.md`
- `source/openraft/src/docs/data/leader_id.md`
- `source/openraft/src/docs/cluster_control/dynamic-membership.md`
- `source/openraft/src/docs/protocol/log_replication.md`
- `source/raft-essentials.md` (grep for commit/leader/vote/term/log-matching lines, then the matched lines)
- Directory listing of `source/openraft/src/docs/`. `grep` over `docs/protocol/*.md`, `docs/data/*.md`, `README.md`, `openraft/README.md`, `openraft/src/lib_readme.md` for "identical|same index|state machine safety|log matching|consisten".

### Source: code (line ranges as read)

- `source/openraft/src/raft_state/mod.rs` (full)
- `source/openraft/src/raft_state/io_state.rs` (full)
- `source/openraft/src/raft_state/io_state/io_progress.rs` (full)
- `source/openraft/src/raft_state/membership_state/mod.rs` (full)
- `source/openraft/src/raft_state/membership_state/change_handler.rs` (full)
- `source/openraft/src/raft_state/membership_state/membership_state_test.rs` (grep; lines 108-146)
- `source/openraft/src/raft_state/tests/validate_test.rs` (full)
- `source/openraft/src/engine/command.rs` (lines 1-130; grep)
- `source/openraft/src/engine/engine_impl.rs` (lines 55-480, 585-720, 754-805; grep)
- `source/openraft/src/engine/handler/vote_handler/mod.rs` (lines 80-275)
- `source/openraft/src/engine/handler/replication_handler/mod.rs` (lines 40-340)
- `source/openraft/src/engine/handler/replication_handler/update_matching_test.rs` (grep; lines 60-144)
- `source/openraft/src/engine/handler/following_handler/mod.rs` (lines 40-200)
- `source/openraft/src/engine/handler/following_handler/commit_entries_test.rs` (grep; lines 60-126)
- `source/openraft/src/engine/handler/leader_handler/mod.rs` (lines 40-110)
- `source/openraft/src/engine/handler/establish_handler/mod.rs` (full)
- `source/openraft/src/engine/handler/server_state_handler/mod.rs` (full)
- `source/openraft/src/engine/tests/handle_vote_resp_test.rs` (grep; lines 140-237)
- `source/openraft/src/core/raft_core.rs` (lines 1540-1625 fn scan, 1590-1760; grep)
- `source/openraft/src/core/server_state.rs` (grep `enum ServerState`)
- `source/openraft/src/proposer/candidate.rs` (lines 1-117)
- `source/openraft/src/proposer/leader.rs` (grep of all comments)
- `source/openraft/src/proposer/leader_state.rs` (grep)
- `source/openraft/src/progress/mod.rs` (lines 100-160)
- `source/openraft/src/progress/entry/mod.rs` (grep; lines 25-40, 265-297)
- `source/openraft/src/replication/mod.rs` (grep; lines 840-870)
- `source/openraft/src/membership/membership.rs` (grep; lines 14-36, 119-230, 410-421)
- `source/openraft/src/error.rs` (grep `EmptyMembership`, lines ~606-617)
- `source/openraft/src/storage/v2.rs` (lines 1-140)
- `source/openraft/src/storage/helper.rs` (lines 40-230)
- `source/openraft/src/vote/vote.rs` (lines 1-80; grep `is_same_leader`)
- `source/openraft/src/vote/leader_id/leader_id_adv.rs` (lines 1-40)
- `source/openraft/src/quorum/*.rs` (grep `fn is_quorum`)
- Directory listings of `source/`, `source/openraft/src/` and its `engine/`, `engine/handler/*`, `engine/tests`, `raft_state/*`, `progress/*`, `membership`, `storage`, `proposer`, `vote`, `vote/leader_id`, `core`, `quorum`.
- `grep -rln -i "ndjson\|TraceLog\|tla"` over `source/` (`*.rs`, `*.toml`, `*.md`): no trace emitter found.

## Tools run besides `hist.sh`

- **SANY** on `out/spec-annotated/{base,MC,Trace}.tla` (see check.md).
- **TLC on scratch copies only.** The model directories were not touched:
  - `out/tmp/tlc_mc/`: copy of the original `MC.tla`, `MC.cfg`, `base.tla` → no error, 286,148 distinct states;
  - `out/tmp/tlc1/SplitBrain.tla/.cfg`: restricted base actions → `CommittedLogAgreement` violated;
  - `out/tmp/tlc2/DurableProbe.tla/.cfg` → `DurableStateBounded` violated;
  - `out/tmp/tlc2/DurableProbe2.tla/.cfg` → `CommitWithinAccepted` violated.
- **Scripts in `out/tmp/`:**
  - `h.sh`: hist.sh logging wrapper;
  - `insert_blocks.py`: inserts the comment blocks above definitions, from `blocks_base.txt`, `blocks_mc.txt`, `blocks_trace.txt`. `blocks_base.txt` predates later edits made directly in `spec-annotated/base.tla`: the 36d2c115 evidence line in `LeaderVoteCommitted` and the reworded notes of `TypeOK`, `MembershipWellFormed`, `CandidateGrantSound` and `LeaderVoteCommitted`;
  - `check_evidence.py`: block and evidence checks.

## Knowledge not taken from /work

None was used as evidence. Every evidence line cites a file and line in `/work/source`, or a commit reachable through `tools/hist.sh`.
