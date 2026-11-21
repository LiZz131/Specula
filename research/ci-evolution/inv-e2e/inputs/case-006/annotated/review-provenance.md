# Provenance — every history command run and every file read

Only `/work` was used. No network access, no direct `git`. Scratch files are in `/work/out/tmp/`.

## `tools/hist.sh` commands (all run from `/work`)

| # | Command | Purpose / result |
|---|---|---|
| 1 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 0b2b904 \| head -30` | Cited by ElectionSafety. Subject "raft: add tests based on section 5.2 in raft paper"; changes raft_paper_test.go and raft_test.go only. |
| 2 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 5e1859c \| head -30` | Cited by CommitWithinLog. Subject "raft: panic if loaded commit is out of range". |
| 3 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' e769766 \| head -30` | Cited in the CommitWithinLog note. "raft: remove wrong invariant" plus body. |
| 4 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' d747117 \| head -30` | Cited by LogMatching. Subject "raft: add tests based on section 5.3 in raft paper". |
| 5 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 5c55fdf \| head -30` | Cited by LeaderCompleteness. Subject "raft: add paper tests for section 5.4.1". |
| 6 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' 76f7f7a \| head -30` | Cited in the LeaderCompleteness note. "raft: comments for isUpToDate". |
| 7 | `tools/hist.sh show --stat --format='%H%n%an %ad%n%B' f1dae53 \| head -30` | Cited by ReadDeliveryJustified. "raft: support safe readonly request" plus body naming thesis §6.4. |
| 8 | `tools/hist.sh show 5e1859c \| sed -n '1,40p'` | Diff adds the loadState range panic (`state.Commit > r.raftLog.lastIndex()`). |
| 9 | `tools/hist.sh show e769766 \| sed -n '1,40p'` | Diff removes `// Invariant: committed < unstable` from log.go. |
| 10 | `tools/hist.sh show d747117 -- log.go` | log.go part of d747117 (adds a load offset panic); no Log Matching statement. |
| 11 | `tools/hist.sh show f1dae53 -- README.md raft.go \| grep -E '^[+-]' \| grep -E '//\|^\+ -\|^- ' \| head -40` | Comments and README lines added by f1dae53. These are the same texts as README:28-33 and raft.go:47-55/164-173 at base. The commit message itself states no quorum rule. |
| 12–25 | for each `P` in "one leader", "at most one leader", "Election Safety", "Log Matching", "log matching", "State Machine Safety", "Leader Completeness": `tools/hist.sh log -i -F --grep="P" --oneline` and `tools/hist.sh log -S"P" --oneline` | Checks the search claims in the annotator's notes. All 14 commands returned 0 commits. |
| 26 | `tools/hist.sh show 76f7f7a \| sed -n '1,40p'` | Confirms that 76f7f7a added the isUpToDate comment (LeaderCompleteness note). |
| 27 | `tools/hist.sh show 0b2b904 --stat --format=%B \| head -5` | Re-read the commit message text for the note wording. |
| 28 | `tools/hist.sh show 5c55fdf --stat --format=%B \| head -3` | Re-read the commit message text for the note wording. |

No `hist.sh blame` or `hist.sh grep` was run. No block was left with only `impl` evidence, so no `log -S'<identifier>'` search on implementing code was needed.

## Files read

### Task and model
- `/work/ANNOTATION-RULES.md`: full.
- `/work/tools/hist.sh`: full (`cat`).
- `/work/spec-original/*.cfg`: all 16 files, full (MC, MC_complete_core, MC_hunt_s1…s5, Reach_s1…s5, Trace, Trace_quorum_loss, base).
- `/work/spec-annotated/base.tla`, `MC.tla`, `Trace.tla`: full.
- `/work/spec-original/*` vs `/work/spec-annotated/*`: all 19 files compared with `cmp`; the 3 `.tla` files diffed to list the annotator's added lines.
- Directory listings only: `/work`, `/work/out`, `/work/lib`, `/work/tools`, `/work/tools/network-guard`, `/work/.cache`, `/work/source`.

### Source tree (`/work/source/`)
- `README.md`: full (lines 1-195).
- `raft_paper_test.go`: lines 1-30, 180-270, 385-771, 770-936; `grep -n "^// Test\|Reference: section"`.
- `raft_test.go`: lines 600-700, 1715-1860.
- `log_test.go`: lines 150-275, 435-475.
- `log.go`: lines 20-130, 180-290.
- `read_only.go`: full (1-118).
- `raft.go`: lines 40-60, 155-175, 420-500, 755-778, 822-940, 1005-1025, 1072-1083, 1190-1202.
- `node.go`: lines 40-70, 120-175, 280-300, 350-390, 500-537.
- `doc.go`: lines 14-30, 240-260.
- `raftpb/raft.pb.go`: `grep -n "HardState struct" -A6` (lines 256-261, the Term/Vote/Commit fields).
- `raftpb/raft.proto`: `grep -n HardState` (line 72).
- `wc -l` over `*.go *.md raftpb/* rafttest/*` (sizes only).
- Targeted greps: `grep -nF` of every cited quote in its cited file. These cover all 43 `source/` evidence lines of the annotated copy; the `log.go:32` quote is cited twice and was grepped once. One more grep covered `node.go:157`, which is cited in a note. `grep -rniF` for the 7 search phrases above across the tree; `grep -n "appends the proposal\|as a new entry" *.go`.

### Tools and output
- `/work/lib/tla2tools.jar`, `/work/lib/CommunityModules-deps.jar`: used only to run SANY.
- `/work/out/tmp/apply_review.py` (written by me): applies the comment edits; each replacement must match exactly once.
- `/work/out/tmp/check_blocks.py` (written by me): block, review-line and evidence-location checks.
- `/work/out/tmp/sany_*.txt`: SANY outputs. `/work/out/tmp/orig/`: a scratch copy of the original `.tla` files for a baseline SANY run.

The Go toolchain (`/usr/local/go`) was checked for availability with `which go` / `go version` but not used. The test analysis of `log_test.go:228-250` is by reading the code.
