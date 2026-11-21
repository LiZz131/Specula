# Provenance

Everything below was done inside `/work`. I made no network access and never ran `git` directly. Every
history query went through `tools/hist.sh`, via a logging wrapper (`out/tmp/h.sh`) that appends each
invocation to `out/tmp/hist_cmds.log` and then `exec`s `/work/tools/hist.sh` with the same arguments.
The wrapper's log drops shell quoting. Below, the commands are shown with the quoting I used; shell pipes
such as `| head` are in brackets.

## `tools/hist.sh` commands (all 83, in order)

| # | Command | Purpose / result |
|---|---|---|
| 1 | `hist.sh log --oneline` [`\| head -5`] | base = dafdef8 |
| 2 | `hist.sh log --oneline` [`\| wc -l`] | 789 commits |
| 3 | `hist.sh log --oneline -- read_only.go` | f1dae53 only |
| 4 | `hist.sh log -S'ReadIndex' --oneline` [`\| head -40`] | f9382a4, 06b9fc9, b1eed33, f1dae53, 830e889, 9392e5d, d935166 |
| 5 | `hist.sh show f9382a4` [`\| head -200`] | read-index eligibility guard + TestReadOnlyForNewLeader |
| 6 | `hist.sh show f1dae53 --stat` | safe read-only request commit |
| 7 | `hist.sh show f1dae53 -- raft.go read_only.go README.md node.go doc.go` [`\| head -400`] | message "Implement raft readonly request described in raft thesis 6.4" |
| 8 | `hist.sh show d935166` [`\| head -150`] | original read-only query (lease) |
| 9 | `hist.sh show 9392e5d` [`\| head -80`] | ReadIndex Node API comment origin |
| 10 | `hist.sh log -S'one leader' --oneline` [`\| head -8`] | none |
| 11 | `hist.sh log -S'Log Matching' --oneline` | none |
| 12 | `hist.sh log -S'log matching' --oneline` | none |
| 13 | `hist.sh log -S'Leader Completeness' --oneline` | none |
| 14 | `hist.sh log -S'State Machine Safety' --oneline` | none |
| 15 | `hist.sh log -S'Election Safety' --oneline` | none |
| 16 | `hist.sh log -S'at most one leader' --oneline` | none |
| 17 | `hist.sh log -S'Invariant: applied' --oneline` | bdc5f38 |
| 18 | `hist.sh log -S'never decrease commit' --oneline` | c405634 |
| 19 | `hist.sh log -S'stable storage on a quorum' --oneline` | bdc5f38 |
| 20 | `hist.sh show bdc5f38 --stat` | log storage interface |
| 21 | `hist.sh show bdc5f38 -- log.go` [`\| grep`] | added "Invariant: applied <= committed" and "Invariant: committed < unstable" |
| 22 | `hist.sh log -S'Invariant: committed < unstable' --oneline` | e769766, bdc5f38 |
| 23 | `hist.sh log -S'committed < unstable' --oneline` | e769766, 14694fb, bdc5f38 |
| 24 | `hist.sh show e769766` [`\| head -40`] | "raft: remove wrong invariant" |
| 25 | `hist.sh show c405634` [`\| head -60`] | handleHeartbeat / commitTo "never decrease commit" |
| 26 | `hist.sh log -S'state.commit %d is out of range' --oneline` | 5e1859c |
| 27 | `hist.sh log -S'is out of range [%d, %d]' --oneline -- raft.go` | 5e1859c |
| 28 | `hist.sh show 5e1859c` [`\| head -80`] | "raft: panic if loaded commit is out of range" |
| 29 | `hist.sh log -S'r.Vote == m.From' --oneline -- raft.go` | 3cd0896 |
| 30 | `hist.sh log -S'isUpToDate' --oneline -- log.go raft.go` | 76f7f7a, 3cd0896, 6b05b1a, b34f60a |
| 31 | `hist.sh log -S'findConflict' --oneline -- log.go` [`\| tail -5`] | 60c280b, 3cd0896, 6b05b1a, b2431fa |
| 32 | `hist.sh log -S'conflict with committed entry' --oneline` | c8197ab, 255b5d1, 3cd0896, 6b05b1a, b2431fa |
| 33 | `hist.sh log -S'recvAck' --oneline` | f1dae53 |
| 34 | `hist.sh log -S'ackCount' --oneline` | f1dae53 |
| 35 | `hist.sh log -S'MUST NOT forward' --oneline` | c4c32e1 |
| 36 | `hist.sh log -S'maybeCommit(maxIndex, term uint64)' --oneline` | 7be314f |
| 37 | `hist.sh show 76f7f7a` [`\| head -40`] | isUpToDate comment (narration) |
| 38 | `hist.sh show c4c32e1` [`\| head -60`] | heartbeat commit "MUST NOT forward" comment origin |
| 39 | `hist.sh show b2431fa` [`\| head -30`] | conflict-with-committed panic origin |
| 40 | `hist.sh log --oneline --reverse` [`\| head -5`] | oldest commits |
| 41 | `hist.sh log -S'guarantee' --oneline` [`\| head -12`] | f1dae53, f224f90, 4b3a7ff, 13e6398, c14132b |
| 42 | `hist.sh log -S'Safety' --oneline` [`\| head -12`] | none |
| 43 | `hist.sh log -S'safety' --oneline` [`\| head -12`] | ed3d491, f224f90, 15f49dc, c14132b, 4702fa0, f1313cd |
| 44 | `hist.sh show ed3d491` [`\| head -80`] | leader lease / checkQuorum (not relevant to the checked properties) |
| 45 | `hist.sh log -G'(?i)vote for at most\|only vote\|vote once\|one vote' --oneline` [`\| head`] | regex error, no result |
| 46 | `hist.sh log -G'Reference: section 5' --oneline` [`\| head`] | 5c55fdf, d747117, 26ae9a2, 0b2b904 |
| 47 | `hist.sh log -S'persisted to disk' --oneline` [`\| head`] | f224f90, 36aa7a3 |
| 48 | `hist.sh log -G'vote for at most\|only vote\|vote once\|one vote' --oneline` [`\| head`] | 0b2b904 |
| 49 | `hist.sh show 0b2b904` [`\| head -30`] | paper tests §5.2 |
| 50 | `hist.sh show 5c55fdf` [`\| head -20`] | paper tests §5.4.1 |
| 51 | `hist.sh log -S'TestLeaderOnlyCommitsLogFromCurrentTerm' --oneline` | 5c55fdf |
| 52-58 | `hist.sh log -1 --format='%h %s%n%b' <c>` for d747117, 0b2b904, 5c55fdf, 5e1859c, f1dae53, e769766, c4c32e1 | output was for base only (the wrapper always passes `base`), discarded |
| 59-66 | `hist.sh show -s --format='%h %ad %s%n%b' --date=short <c>` for d747117, 0b2b904, 5c55fdf, 5e1859c, f1dae53, e769766, c4c32e1, bdc5f38 | commit messages used for `history` evidence |
| 67 | `hist.sh log -S'delete(ro.pendingReadIndex' --oneline -- read_only.go` | f1dae53 |
| 68 | `hist.sh log -S'r.readOnly = newReadOnly' --oneline -- raft.go` | f1dae53 |
| 69 | `hist.sh log -S'addRequest(r.raftLog.committed' --oneline -- raft.go` | f1dae53 |
| 70 | `hist.sh log -S'appliedTo(prevHardSt.Commit)' --oneline -- node.go` | 113ebb1 |
| 71 | `hist.sh log -S'r.raftLog.commitTo(m.Commit)' --oneline -- raft.go` | c405634 |
| 72 | `hist.sh blame -L 32,38 log.go` | committed/applied comments date from bdc5f38 (2014-11-03) |
| 73 | `hist.sh show -s --format='%h %ad%n%B' --date=short 113ebb1` | Advance interface message (used in concerns C7) |
| 74-78 | `hist.sh show -s --format=%B <c>` for 5e1859c, 0b2b904, 5c55fdf, d747117, f1dae53 | issued by `out/tmp/check_blocks.py` (first run) to verify history quotes |
| 79-83 | same five commands | issued by `out/tmp/check_blocks.py` (second run, after the note edit) |

## Files read

### Model (`spec-original/`, read only)
* `base.tla`, `MC.tla`, `Trace.tla`: read in full.
* All 15 `.cfg` files: read in full (`MC.cfg`, `MC_complete_core.cfg`, `MC_hunt_s1..s5*.cfg`,
  `Reach_s1..s5*.cfg`, `Trace.cfg`, `Trace_quorum_loss.cfg`, `base.cfg`).

### Source (`source/`, read only)
| File | Extent |
|---|---|
| README.md | full |
| design.md | full |
| doc.go | full |
| read_only.go | full |
| raft.go | lines 30-1253 (whole file except the license/imports header) |
| log.go | lines 15-330 |
| node.go | lines 15-200, 270-400, 495-530 |
| rawnode.go | lines 50-75, 250-265; function list via grep |
| raftpb/raft.proto | full |
| raft_paper_test.go | lines 14-38, 186-300, 470-545, 590-935; grep of comments/tests |
| raft_test.go | lines 290-300, 380-400, 540-700, 1720-1935; grep of test names |
| log_test.go | lines 140-270, 436-475; grep |
| node_test.go | lines 140-260 |
| rafttest/node_test.go | lines 20-200 |
| rafttest/doc.go | lines 14-40 |
| grep-only hits | rawnode_test.go, rafttest/network_test.go, rafttest/node.go, log_unstable.go, progress.go, design.md, plus a tree-wide grep for "one leader / at most one / split brain / Election Safety / Log Matching / Leader Completeness / State Machine Safety / linearizab / out of range / Invariant / appliedTo" |

### Tools
* `tools/hist.sh`: read (header/usage) and run through the wrapper.
* `lib/tla2tools.jar`, `lib/CommunityModules-deps.jar`: used for SANY and TLC.

## Scratch work (`out/tmp/`)
* `h.sh`: logging wrapper for `tools/hist.sh`. `hist_cmds.log` is its log.
* `annotate.py`: copies `spec-original/` to `out/spec-annotated/` and inserts the comment blocks.
* `check_blocks.py` / `check_blocks.out`: block-count, quote, location and field checks.
* `sany_*.out`: SANY outputs for the annotated and original modules.
* `diffstates.py`: prints per-state variable diffs of a TLC counterexample.
* `tlc/`: a copy of the original `.tla` files used **only** for the TLC probes in concerns C1.
  * `Probe_forward_restart.cfg`, `Probe_forward_only.cfg`.
  * `ProbeMC.tla`: a copy of `MC.tla` with the module name changed and `ClientReadIndex` restricted to
    local requesters.
  * `probe.out`, `probe2.out` and `*_state_diffs.txt`: the probe outputs.
  * The deliverable model was not touched by these runs.
