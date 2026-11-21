# Provenance

Everything here came from `/work`. I used no network access and did not run `git` directly.
After the first two calls, every `tools/hist.sh` call went through a logging wrapper, `out/tmp/h.sh`. The wrapper calls `/work/tools/hist.sh` with the same arguments and appends the command line to `out/tmp/hist_commands.log`. The list below is that log, with the first two calls (made before the wrapper existed) prepended. Arguments are shown in shell-quoted form as `printf %q` wrote them.

Some outputs were piped through `head`, `grep`, `sed -n` or `wc -l` to keep them short. That is noted where it mattered.

## `tools/hist.sh` commands run (in order)

```
1  tools/hist.sh log --oneline            (piped to head -5; run directly, before the wrapper existed)
2  tools/hist.sh log --oneline            (piped to wc -l; run directly, before the wrapper existed)
3  tools/hist.sh log --oneline -3
4  tools/hist.sh blame -L 6\,27 openraft/src/membership/membership_state.rs
5  tools/hist.sh blame -L 5\,12 openraft/src/vote/leader_id.rs
6  tools/hist.sh blame -L 356\,372 openraft/src/engine/engine_impl.rs
7  tools/hist.sh log -SCommitted\ index\ can\ not --oneline
8  tools/hist.sh log -Sat\ most\ one\ outstanding --oneline
9  tools/hist.sh log -Sdirty\ and\ stupid --oneline
10 tools/hist.sh log -SMismatching\ term\ can\ not\ prevent --oneline
11 tools/hist.sh show ef152f5 --stat
12 tools/hist.sh show ef152f5
13 tools/hist.sh grep -n commit-index\ must\ not\ advance ef152f5\^ -- openraft/src/core/append_entries.rs
14 tools/hist.sh log -Scommit-index\ must\ not\ advance --oneline
15 tools/hist.sh log -1 --format=%h\ %s ef152f5\^
16 tools/hist.sh show a68a9a9 --stat --format=%h\ %ad%n%B
17 tools/hist.sh show 58f2491 --stat --format=%h\ %ad%n%B
18 tools/hist.sh show 58f2491:openraft/src/vote/vote.rs
19 tools/hist.sh show a68a9a9 -- openraft/src/vote/vote.rs
20 tools/hist.sh log -SMismatching\ term --oneline
21 tools/hist.sh log -Shas_pending_config --oneline
22 tools/hist.sh log -Sis\ not\ committed\ yet --oneline -- openraft/src/core/admin.rs
23 tools/hist.sh log -SThe\ second\ last\ membership\ log\ has\ to\ be\ committed --oneline
24 tools/hist.sh log -STODO\(xp\):\ remove\ this\ line --oneline -- openraft/src/core/replication.rs
25 tools/hist.sh show 3511e43
26 tools/hist.sh log -Smatched.term\ ==\ self.core.current_term --oneline
27 tools/hist.sh log -Sleader_id\ ==\ self.core.engine.state.vote.leader_id\(\) --oneline
28 tools/hist.sh show 0135e3b --format=%h\ %ad%n%B
29 tools/hist.sh show 0135e3b
30 tools/hist.sh log -1 --format=%h 0135e3b\^
31 tools/hist.sh grep -n will\ never\ be\ less\ than\ this\ value\\\|only\ log\ entries\ from\ the\ leader\\\|Determine\ the\ value\ for\ .current_commit 0135e3b\^ -- async-raft/src/core/replication.rs
32 tools/hist.sh show -s --format=%h\ parent=%p\ %s 0135e3b
33 tools/hist.sh show -s --format=%h\ parent=%p\ %s ef152f5
34 tools/hist.sh grep -n will\ never\ be\ less\ than\ this\ value\\\|only\ log\ entries\ from\ the\ leader 1451f96 -- async-raft/src/core/replication.rs
35 tools/hist.sh grep -n commit-index\ must\ not\ advance 2eaab71 -- openraft/src/core/append_entries.rs
36 tools/hist.sh log -Sself.state.vote.node_id\ ==\ self.id\ \&\&\ self.state.vote.committed --oneline
37 tools/hist.sh log -Sdebug_assert\!\(self.core.engine.state.vote.committed\) --oneline
38 tools/hist.sh log -SOnly\ when\ a\ committed\ vote\ is\ seen --oneline
39 tools/hist.sh log -SA\ leader\ without\ commit\ vote\ is\ a\ Candidate --oneline
40 tools/hist.sh show -s --format=%h\ %ad%n%B f882e11
41 tools/hist.sh show -s --format=%h\ %ad%n%B 453e80d
42 tools/hist.sh show -s --format=%h\ %ad%n%B 3fd1d8a
43 tools/hist.sh show -s --format=%h\ %ad%n%B e87983d
44 tools/hist.sh show -s --format=%h\ %ad%n%B f56b910
45 tools/hist.sh show f56b910
46 tools/hist.sh log -Snot\ committed\ yet --oneline
47 tools/hist.sh log -SCan\ not\ process\ the\ next\ one --oneline
48 tools/hist.sh show -s --format=%h\ %ad%n%B 7f34793
49 tools/hist.sh log -Sthe\ matched\ increments\ monotonically --oneline
50 tools/hist.sh log -Sstd::cmp::max\(committed.cloned\(\) --oneline
51 tools/hist.sh log -SCommitted\ means:\ a\ log\ that\ is\ replicated\ to\ a\ quorum --oneline
52 tools/hist.sh show -s --format=%h\ %ad%n%B 9915089
53 tools/hist.sh show 4a83c76
54 tools/hist.sh show -s --format=%B 58f2491
55 tools/hist.sh show -s --format=%B f882e11
56 tools/hist.sh show -s --format=%B 9915089
57 tools/hist.sh show -s --format=%B 3fd1d8a
58 tools/hist.sh show -s --format=%B 7f34793
59 tools/hist.sh show -s --format=%B a68a9a9
60 tools/hist.sh show 2eaab71:openraft/src/core/append_entries.rs
61 tools/hist.sh show 1451f96:async-raft/src/core/replication.rs
62 tools/hist.sh show 58f2491:openraft/src/vote/vote.rs
```

Notes on the commands:
- Commands 15 and 30 (`log -1 ... <commit>^`) returned the base commit. `hist.sh log` always prepends `base`, so they did not give the parent. Commands 32 and 33 (`show -s --format=%p`) gave the parents instead: 0135e3b → 1451f96, ef152f5 → 2eaab71. Every history location cited in the model uses those parent hashes.
- Commands 54-62 re-check that each history quote cited in the model or in `concerns.md` appears verbatim. Messages were compared with whitespace normalised, because commit messages wrap lines.

## History used as evidence

| Commit | What was used | Used for |
|---|---|---|
| a68a9a9 (message; diff of `openraft/src/vote/vote.rs`) | "in a `term`, it allows to elect more than one leader", "A node is able to grant more than one vote within one term"; the diff deletes "Two committed votes have to be the same" | ElectionSafety (note; C1) |
| 58f2491 (message; `58f2491:openraft/src/vote/vote.rs:80`) | "A Leader has a `Vote` that is committed"; the old rule "Two committed votes have to be the same" | ActiveLeaderHasCommittedVote; ElectionSafety (note) |
| f882e11 (message) | "the `vote` should be committed before entering leader state" | ActiveLeaderHasCommittedVote |
| 2eaab71:openraft/src/core/append_entries.rs:56 (parent of ef152f5) | "commit-index must not advance the last known consistent log" (comment deleted by ef152f5) | CommitWithinLocalLog |
| 1451f96:async-raft/src/core/replication.rs:285-286 (parent of 0135e3b) | "The output of this function will never be less than this value."; "only log entries from the leader’s current term are committed" (doc deleted by 0135e3b) | CommitWitnessSound |
| 9915089 (message) | "This field can only be updated monotonically." (`matched`) | CommitWitnessSound |
| 3fd1d8a (message) | "the `last()` is the effective one but may not be committed." | MembershipOrder |
| 7f34793 (message) | "check if a membership is committed by comparing the log index and its committed index" | OneOutstandingMembership |
| 3511e43, 0135e3b, 4060ba1, ef152f5, f56b910, 81cd344, e87983d, d7afc72, 453e80d, 4a83c76 | read while tracing where comments came from; nothing additional cited | — |

## Files read

Model (read-only originals): `spec-original/base.tla`, `MC.tla`, `Trace.tla`, `base.cfg`, `MC.cfg`, `MC_hunt_s1_progress.cfg`, `MC_hunt_s2_membership.cfg`, `MC_hunt_s3_follower_commit.cfg`, `MC_hunt_s4_election.cfg`, `MC_reach_commit.cfg`, `MC_reach_leader.cfg`, `MC_reach_membership.cfg`, `MC_scale.cfg`, `Trace.cfg`. Also `tools/hist.sh` (read the script).

Source tree (`source/`). Read in full unless a range is given:
- `raft-essentials.md`
- `derived-from-async-raft.md`
- `change-log.md` (lines 60-72, 136-156, 329-380, plus `grep` for vote/commit terms)
- `README.md` (`grep` only)
- `guide/src/SUMMARY.md`, `architecture.md`, `replication.md`, `effective-membership.md`, `dynamic-membership.md`, `internal.md`, `cluster-controls.md`
- `openraft/src/engine/engine_impl.rs`
- `openraft/src/vote/vote.rs`, `openraft/src/vote/leader_id.rs`
- `openraft/src/leader/leader.rs`
- `openraft/src/raft_state.rs`
- `openraft/src/membership/membership_state.rs`, `openraft/src/membership/membership_state_test.rs`
- `openraft/src/membership/membership.rs` (doc/fn `grep`, lines 305-348)
- `openraft/src/progress/mod.rs`
- `openraft/src/core/replication.rs`
- `openraft/src/core/leader_state.rs`
- `openraft/src/core/admin.rs` (lines 100-260)
- `openraft/src/core/raft_core.rs` (lines 150-330)
- `openraft/src/storage/helper.rs`
- `openraft/src/quorum/quorum_set.rs`, `quorum/mod.rs`, `quorum/quorum_set_impl.rs` (1-30), `quorum/joint.rs` (40-70)
- `openraft/src/docs/mod.rs`
- `openraft/src/error.rs` (365-380, plus `grep`)
- `openraft/src/raft.rs` (430-470, 820-840, plus `grep`)
- `openraft/src/engine/internal_handle_vote_req_test.rs` (1-200)
- `openraft/src/engine/follower_commit_entries_test.rs` (1-160)
- `openraft/src/engine/update_committed_membership_test.rs` (40-160)
- `openraft/src/engine/elect_test.rs` (36-58, plus `grep`)
- `openraft/src/engine/handle_vote_resp_test.rs` (205-242, plus `grep`)
- `openraft/tests/fixtures/mod.rs` (700-735)
- `openraft/tests/append_entries/t30_append_inconsistent_log.rs` (1-40, comments only)

Repository-wide `grep` searches over `source/`, for: "at most one leader", "one leader", "same term", "two leader", "brain split"/"split brain"; "monoton", "never decrease", "must not decrease", "can not decrease", "go backward"; "InProgress", "in_progress", "pending" (in tests); "committed", "uncommitted", "not yet committed", "previous one" (in `error.rs` and `raft.rs`); "a68a9a9", "elect more than", "grant more than", "commit" (in `change-log.md`).

## Scratch work (`out/tmp/`)

- `h.sh`: the logging wrapper. `hist_commands.log`: its log.
- `check.py` / `check_output.txt`: the structural checks (see `check.md`).
- `sany_*.txt`: SANY output for the annotated modules. `sanytest/`: a one-line module confirming that SANY accepts non-ASCII characters in comments.
- `tlc_crash/`, `tlc_witness/`: TLC runs on copies of the original `base.tla` and `MC.tla`, each with one extra scratch `.cfg`, cited in `concerns.md` C2 and C3.
