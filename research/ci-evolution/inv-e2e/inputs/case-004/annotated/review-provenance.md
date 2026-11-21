# Provenance of the review

Everything below was read or run inside `/work`. I made no network access and ran no `git` command directly; all history access went through `tools/hist.sh`. Scratch scripts are in `out/tmp/`.

## `tools/hist.sh` commands (in the order run)

| # | Command | Purpose |
|---|---|---|
| 1 | `tools/hist.sh show --stat 942ec78b` | verify the 942ec78b message quoted in IOOrder and DurableStateBounded |
| 2 | `tools/hist.sh show 90c29ccb` (first 120 lines) | verify the 90c29ccb message quoted in CommitWithinAccepted |
| 3 | `tools/hist.sh show 90c29ccb -- openraft/src/engine/handler/following_handler/mod.rs` | see the removed `max_committed` comment and the added `min(accepted, leader_committed)` clamp |
| 4 | `tools/hist.sh log --oneline -1 90c29ccb^` | find the parent (`hist.sh log` always starts from base, so this printed the base commit; superseded by #6) |
| 5 | `tools/hist.sh log --oneline -3 5a8b6758` | same; printed the base history, so not informative |
| 6 | `tools/hist.sh show --no-patch --format='%H parents=%P' 90c29ccb` | confirm that 5a8b6758 is the parent of 90c29ccb |
| 7 | `tools/hist.sh show --no-patch --format='%H %s' base` | identify the base commit (7fa0f9b7) |
| 8 | `tools/hist.sh show --no-patch --format='%H %s' 5a8b6758` | identify 5a8b6758 |
| 9 | `tools/hist.sh show 5a8b6758:openraft/src/engine/handler/following_handler/mod.rs` (lines 105-125) | verify the quote at line 113 cited in CommitWithinAccepted |
| 10 | `tools/hist.sh show --stat 36d2c115` | verify the 36d2c115 message quoted in LeaderVoteCommitted (also cited in the CandidateGrantSound note) |
| 11 | `tools/hist.sh log -S'update_local_progress' --oneline -- openraft/src/engine/handler/replication_handler/mod.rs openraft/src/engine/engine_impl.rs openraft/src/engine/mod.rs` | MatchWithinLeaderLog: search for a stated rule on the leader's own progress entry |
| 12 | `tools/hist.sh show --no-patch --format='=== %h %s%n%b' 340ec16d` | read that commit's message |
| 13 | `tools/hist.sh show --no-patch --format='=== %h %s%n%b' a9f696a9` | read that commit's message |
| 14 | `tools/hist.sh show --no-patch --format='=== %h %s%n%b' e69aea1c` | read that commit's message |
| 15 | `tools/hist.sh show 340ec16d` (added `///` comment lines only) | look for a stated rule; only a narrating doc comment was found |
| 16 | `tools/hist.sh show a9f696a9 --stat` | read the full message and the files it touched |
| 17 | `tools/hist.sh show a9f696a9` (added/removed comment lines only) | look for a stated rule; none was counted |
| 18 | `tools/hist.sh log -S'std::cmp::min(accepted, leader_committed)' --oneline -- openraft/src/engine/handler/following_handler/mod.rs` | re-run the search the CommitWithinAccepted note claims; result: 90c29ccb, as the note says |
| 19 | `tools/hist.sh log -S'pub(crate) type LeaderState<C>' --oneline` | re-run the search the LeaderVoteCommitted note claims; result: 36d2c115, as the note says |

I did not cite commits 340ec16d, a9f696a9 or e69aea1c in the model. The self-progress evidence I added to MatchWithinLeaderLog comes from `log_pointers.md`, a file the block already cited.

## Files read

### Task and model files
- `/work/ANNOTATION-RULES.md` (full)
- `/work/tools/hist.sh` (full)
- `/work/spec-annotated/base.tla`, `MC.tla`, `Trace.tla`, `base.cfg`, `MC.cfg`, `Trace.cfg` (full)
- `/work/spec-original/*` (compared against `spec-annotated/` and `out/spec-reviewed/` on non-comment lines; `.cfg` files compared byte for byte)

### Source files read in context (line ranges)
- `source/openraft/src/docs/data/log_pointers.md` (whole file)
- `source/openraft/src/raft_state/io_state/io_progress.rs` 1-60
- `source/openraft/src/engine/command.rs` 60-100
- `source/openraft/src/engine/handler/following_handler/commit_entries_test.rs` 40-125
- `source/openraft/src/docs/protocol/log_replication.md` 1-20, 95-175
- `source/openraft/src/progress/entry/mod.rs` 20-60, 255-285
- `source/openraft/src/replication/mod.rs` 840-870
- `source/openraft/src/engine/handler/replication_handler/mod.rs` 25-45, 95-130, 160-260, 425-470
- `source/openraft/src/engine/handler/replication_handler/update_matching_test.rs` 50-140
- `source/openraft/src/raft_state/mod.rs` 45-65, 335-390
- `source/openraft/src/docs/data/vote.md` 1-80
- `source/openraft/src/proposer/leader.rs` 1-60
- `source/openraft/src/engine/engine_impl.rs` 118-142, 345-402, 630-672
- `source/openraft/src/proposer/candidate.rs` 80-125
- `source/openraft/src/engine/handler/vote_handler/mod.rs` 85-240
- `source/openraft/src/engine/tests/handle_vote_resp_test.rs` 140-225 (plus a scan for the enclosing `fn test_` names)
- `source/openraft/src/raft_state/membership_state/mod.rs` 10-40, 210-226
- `source/openraft/src/docs/data/effective-membership.md` 1-30
- `source/openraft/src/docs/data/extended-membership.md` 80-160
- `source/openraft/src/storage/helper.rs` 165-220
- `source/openraft/src/raft_state/membership_state/membership_state_test.rs` 100-170 (plus `fn test_` name scan)
- `source/openraft/src/membership/membership.rs` 15-50, 95-240, 395-425 (plus `fn test_` name scan)
- `source/openraft/src/error.rs` 600-615
- `source/openraft/src/raft_state/membership_state/change_handler.rs` 15-60
- `source/openraft/src/core/raft_core.rs` 1225-1275, 1320-1335
- `source/openraft/src/storage/v2.rs` 20-120
- `source/raft-essentials.md` 40-95 (and a grep for matching/safety/committed)
- `source/openraft/src/docs/data/leader_id.md` 1-60
- `source/openraft/src/vote/leader_id/leader_id_adv.rs` 1-30
- `source/openraft/src/vote/vote.rs` (grep for `PartialOrd for Vote`)

### Files opened by scripts
- `out/tmp/checkquotes.py` and `out/tmp/checkquotes_reviewed.py` opened every cited file and checked each quote at the cited line: `core/raft_core.rs`, `docs/data/{effective-membership,extended-membership,leader_id,log_pointers,vote}.md`, `docs/protocol/log_replication.md`, `engine/command.rs`, `engine/engine_impl.rs`, `engine/handler/following_handler/{mod,commit_entries_test}.rs`, `engine/handler/replication_handler/{mod,update_matching_test}.rs`, `engine/handler/vote_handler/mod.rs`, `engine/tests/handle_vote_resp_test.rs`, `error.rs`, `membership/membership.rs`, `progress/entry/mod.rs`, `proposer/{candidate,leader}.rs`, `raft_state/io_state/io_progress.rs`, `raft_state/membership_state/{change_handler,membership_state_test,mod}.rs`, `raft_state/mod.rs`, `replication/mod.rs`, `storage/{helper,v2}.rs`, `vote/leader_id/leader_id_adv.rs` (all under `source/openraft/src/`), and `source/raft-essentials.md`.
- The inline watch-target check opened every `watch:` file to confirm that the named symbol exists. Beyond the files above, this added `core/server_state.rs`, `engine/handler/server_state_handler/mod.rs`, `quorum/joint.rs` and `vote/vote.rs`.

### Greps over the source tree
- `grep -rn -i "ndjson\|TraceLog" source/`: no hits, which confirms the TraceMatched note.
- `grep -rn -i "local progress\|progress of local\|leader itself\|leader's own\|own progress\|self.progress\|local log" openraft/src` (`.md`, `.rs`): searched for a non-impl statement on the leader's own progress entry.
