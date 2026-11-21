# Provenance

Every `tools/hist.sh` command run during this review, every file read, and every scratch file written. All work used `/work` only: no network, and no direct `git`.

## `tools/hist.sh` commands (in order run, from `/work`)

| # | Command | What it returned / why |
|---|---|---|
| 1 | `tools/hist.sh log -1 --format='%H%n%ad%n%B' <c>` for each of `58f2491 f882e11 9915089 3fd1d8a 7f34793 a68a9a9 0135e3b 2eaab71 1451f96` | Each printed the **base** commit (143a685, "Merge pull request #436 …"), because `hist.sh log` always prepends `base`. The output was discarded and rerun with `show -s` (#2). |
| 2 | `tools/hist.sh show -s --format='%H%n%ad%n%B' <c>` for each of `58f2491 f882e11 9915089 3fd1d8a 7f34793 a68a9a9 0135e3b 2eaab71 1451f96` | Messages of the cited commits. Confirmed the quotes "A Leader has a `Vote` that is committed" (58f2491), "the `vote` should be committed before entering leader state" (f882e11), "This field can only be updated monotonically." (9915089), "the `last()` is the effective one but may not be committed." (3fd1d8a), "check if a membership is committed by comparing the log index and its committed index" (7f34793), and "in a `term`, it allows to elect more than one leader" / "A node is able to grant more than one vote within one term" (a68a9a9). 0135e3b: "refactor: simplify joint commit index calculation". 2eaab71 and 1451f96 are cited by file:line (#3, #4). |
| 3 | `tools/hist.sh show 2eaab71:openraft/src/core/append_entries.rs` (lines 40–75 viewed) | Line 56: "Caveat: [commit-index must not advance the last known consistent log](…)". Quote confirmed. |
| 4 | `tools/hist.sh show 1451f96:async-raft/src/core/replication.rs` (lines 270–320 viewed) | Lines 285–286: "The output of this function will never be less than this value." and "only log entries from the leader’s current term are committed". Quotes confirmed. |
| 5 | `tools/hist.sh show 58f2491:openraft/src/vote/vote.rs` (lines 60–100 viewed) | Line 80: "Two committed votes have to be the same". The ElectionSafety note's claim is confirmed. |
| 6 | `tools/hist.sh show a68a9a9 -- openraft/src/vote/vote.rs` (grep "Two committed votes") | The line appears as removed (`-`) in a68a9a9. The note's claim is confirmed. |
| 7 | `tools/hist.sh show 0135e3b --stat` | Touches async-raft/src/core/replication.rs, membership_test.rs and raft.rs. |
| 8 | `tools/hist.sh show 0135e3b -- async-raft/src/core/replication.rs` (first 120 lines) | `calc_members_commit_index` / `calculate_new_commit_index` were removed, and with them the doc line from 1451f96. The new `calc_commit_index` returns `greatest_majority_value(...)` or the current value. |
| 9 | `tools/hist.sh log -S'std::cmp::max(committed.cloned()' --oneline -- openraft/src/core/replication.rs` | `4a83c76 Refactor: use Option<LogId> every where` |
| 10 | `tools/hist.sh log -S'TODO(xp): remove this line' --oneline -- openraft/src/core/replication.rs async-raft/src/core/replication.rs` | `4a83c76` |
| 11 | `tools/hist.sh show -s --format='%h %ad%n%B' 4a83c76` | Message: Option<LogId> refactor. Says nothing about commit monotonicity. |
| 12 | `tools/hist.sh show 4a83c76 -- openraft/src/core/replication.rs` (grep -B8 -A8 'remove this line') | Shows `std::cmp::max(committed.cloned(), self.core.committed)` added under `// TODO(xp): remove this line`. |
| 13 | `tools/hist.sh show 0135e3b:async-raft/src/core/replication.rs` (lines 105–170 viewed) | `handle_update_matched` at 0135e3b updates `commit_index` only `if commit_index > self.core.commit_index`. |
| 14 | `tools/hist.sh log -S'will never be less than this value' --oneline -- async-raft/src/core/replication.rs openraft/src/core/replication.rs` | `0135e3b` (removed), `c479c78` (added). Confirms the CommitWitnessSound clause and note. |
| 15 | `tools/hist.sh log -S'Mismatching term' --oneline -- openraft/src/core/replication.rs async-raft/src/core/replication.rs` | `3511e43 change: rename MembershipConfig to Membership` |
| 16 | `tools/hist.sh log -S'matched.term == self.core.current_term' --oneline` | `7d24fc8`, `0135e3b` |
| 17 | `tools/hist.sh log -S'monotonically' --oneline -- openraft/src/core/replication.rs async-raft/src/core/replication.rs openraft/src/replication/mod.rs async-raft/src/replication/mod.rs openraft/src/progress/mod.rs` | `e2df554`, `9915089` |
| 18 | `tools/hist.sh show -s --format='%h %ad%n%B' 3511e43` | Message: "change: rename MembershipConfig to Membership" (no body). |
| 19 | `tools/hist.sh show 3511e43` (grep -B3 -A6 'Mismatching term') | Adds the "Mismatching term … Thus it is not considered as committed." comment above `if matched.term == self.core.current_term`. Says nothing about matched terms after a commit. |
| 20 | `tools/hist.sh show -s --format='%h %ad%n%B' e2df554` | "Refactor: add Progress to track replication state and to calculate committed log id". Describes the update algorithm. Says nothing about a matched value keeping its term. |

Searches #15–#20 found no statement that a matched position keeps the committing term. That is the basis for the new `clause matched-term-kept: unknown` in CommitWitnessSound.

## Files read under `/work`

- `ANNOTATION-RULES.md`: full.
- `tools/hist.sh`: full. `ls tools/network-guard`.
- `spec-original/`: all 11 `.cfg` files (full), `base.tla` (full).
- `spec-annotated/`:
  - `MC.tla` and `Trace.tla`: full.
  - `base.tla`: lines 580–767.
  - `diff spec-original/X spec-annotated/X` for `MC.tla`, `Trace.tla` and `base.tla`; `cmp` for every file.
- `out/spec-reviewed/`, the review copy (read before and after editing):
  - `MC.tla`: 104–145. `Trace.tla`: 234–239.
  - `base.tla`: 584–589, the OneOutstandingMembership block, and the final changed blocks.

## Files read under `/work/source`

### Cited evidence locations, each read ±3 lines

- `source/change-log.md`: 361–367
- `source/derived-from-async-raft.md`: 5–11
- `source/guide/src/dynamic-membership.md`: 131–137
- `source/guide/src/effective-membership.md`: 2–8, 10–16, 15–21
- `source/guide/src/replication.md`: 7–13, 71–77
- `source/openraft/src/core/admin.rs`: 134–142
- `source/openraft/src/core/leader_state.rs`: 69–75
- `source/openraft/src/core/replication.rs`: 123–129, 147–153, 184–193, 206–216
- `source/openraft/src/engine/elect_test.rs`: 44–50
- `source/openraft/src/engine/engine_impl.rs`: 211–217, 234–240, 309–315, 331–337, 353–362, 367–373, 452–458, 555–561, 811–817, 894–900
- `source/openraft/src/engine/follower_commit_entries_test.rs`: 137–143
- `source/openraft/src/engine/handle_vote_resp_test.rs`: 230–236
- `source/openraft/src/engine/update_committed_membership_test.rs`: 83–89
- `source/openraft/src/error.rs`: 369–375
- `source/openraft/src/leader/leader.rs`: 8–14, 38–44
- `source/openraft/src/membership/membership_state.rs`: 6–21
- `source/openraft/src/progress/mod.rs`: 1–7
- `source/openraft/src/raft_state.rs`: 31–37, 42–48, 75–81
- `source/openraft/src/storage/helper.rs`: 95–101
- `source/openraft/src/vote/vote.rs`: 5–11, 56–62
- `source/raft-essentials.md`: 5–11, 76–87, 95–109

### Wider context reads

- `source/openraft/src/vote/leader_id.rs`: 1–33 (`head -60`)
- `source/openraft/src/vote/vote.rs`: 1–67 (`head -100`)
- `source/openraft/src/leader/leader.rs`: full
- `source/raft-essentials.md`: 20–30, 50–58. These verify the ElectionSafety note's :25 and :54.
- `source/guide/src/cluster-controls.md`: 10–16
- `source/openraft/tests/fixtures/mod.rs`: 718–728
- `source/openraft/src/engine/handle_vote_resp_test.rs`: 180–250
- `source/openraft/src/engine/elect_test.rs`: 1–80
- `source/openraft/src/membership/membership_state.rs`: 1–41
- `source/guide/src/effective-membership.md`: 1–40 (`head -40`)
- `source/guide/src/dynamic-membership.md`: 120–145
- `source/openraft/src/engine/update_committed_membership_test.rs`: 1–140
- `source/openraft/src/core/replication.rs`: 90–235
- `source/openraft/src/engine/engine_impl.rs`: 225–380, 420–630
- `source/openraft/src/core/admin.rs`: 128–200
- `source/openraft/src/raft_state.rs`: 20–95
- `source/openraft/src/core/raft_core.rs`: 175–215
- `source/openraft/src/storage/helper.rs`: 60–168

### Searches over `source/`

- `grep -rn -i "at most one leader\|one leader\|split brain\|brain split\|two leader" --include=*.rs --include=*.md source/`
- `grep -n "at most one candidate" source/raft-essentials.md`
- `grep -n "fn test_" source/openraft/src/engine/handle_vote_resp_test.rs source/openraft/src/engine/follower_commit_entries_test.rs`. This confirms the test names `test_handle_vote_resp` (fn at :37) and `test_follower_commit_entries_gt_last_entry` (fn at :135).
- `grep -n -i "commitIndex\|commit index\|monoton" source/raft-essentials.md source/guide/src/*.md`
- `grep -rn -i "monoton" --include=*.rs source/openraft/src`
- `grep -rn "VecProgress\|mod progress\|progress::" --include=*.rs source/openraft/src`. VecProgress is used only in progress/ tests and the bench.
- `grep -n -i "state machine safety\|log matching\|leader completeness\|same index\|identical" source/raft-essentials.md`

## Scratch files (`/work/out/tmp/`)

- `locs.txt`: the list of cited `source/` locations.
- `checkquotes.py`: the quote, word-count and arrow checker. Run with `python3 -I` on `spec-annotated/base.tla` and `out/spec-reviewed/base.tla`.
- `sany.txt` and `sany_base.log`, `sany_MC.log`, `sany_Trace.log`: SANY output.
