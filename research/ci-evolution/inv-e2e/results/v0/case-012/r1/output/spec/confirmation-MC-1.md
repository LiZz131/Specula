# MC-1 evidence: joint-membership entry committed without a joint quorum

Status of evidence (this run; the formal bug-confirmation controller is not
available in this task): **reproduced on the updated revision through the real
runtime; baseline control does not reproduce.** The verdict label is left to the
confirmation phase; all evidence needed for it is listed here.

Source identity: updated revision = neutral commit `aa05a38` (`artifact/`
HEAD); baseline = `ce863f4` (`artifact/` HEAD~1). Trees used for runs are
`git archive` exports of those commits (`repro-new-source/`,
`old-control-source/`) plus only the test file below. Toolchain: stable rustc
1.100.0 (the repository pins a nightly that is not installable here).

## 1. Model checking (Case C classification)

- Counterexample (11 states, full `MCNext`, final artifacts): `spec/output/upd-hunt-u1-consequence-final.log` (earlier symmetric instance `spec/output/upd-hunt-u1-consequence-bfs.log`);
  structural precursor (8 states): `spec/output/upd-hunt-u1-bfs.log`; same
  mechanism in the inherited V0 hunt `spec/output/mc-hunt-s2-bfs.log` (leader n2,
  goal {n1,n3}).
- Fidelity of the actions on the path: `VecProgress::update`,
  `upgrade_quorum_set`, `Engine::update_progress`, `leader_append_entries` and
  `update_effective_membership` are validated against fresh implementation
  traces including the exact vector order and cached committed value
  (`spec/output/trace-validation-final.summary`; 27/27 pass; single-field
  mutants rejected: `spec/output/trace-validation-mutant.summary`).
- Engine-level real execution of the same mechanism: trace
  `traces/membership_change_then_acks.ndjson` (harness test
  `engine::specula_trace_test::specula_trace_leader_membership_change_then_acks`):
  after the joint append the leader progress is `[1:(1,1), 2:(1,2), 3:None]` with
  committed `None`; `update_progress(3,(1,2))` sets engine committed to index 2
  while node 1 holds only index 1. The model replays this trace exactly.

## 2. Runtime reproduction (updated revision)

Test: `harness/repro/t90_specula_joint_commit_repro.rs` (in-repo `RaftRouter`
fixture; real `RaftCore`/`LeaderState`/replication streams/memstore). Command:
`bash harness/repro/run_repro.sh` (or the cargo command recorded in the logs).

Schedule: leader 3 forms `{1,2,3}`; isolate 2; one client write (index 6)
acknowledged by 1; isolate 1, restore 2; leader calls
`change_membership({1,2})` → joint `[{1,2,3},{1,2}]` at index 7.
Assertion (the joint-consensus rule, as in the existing
`t30_commit_joint_config` tests): the joint entry must not be committed while
node 1 is isolated.

Observed (`spec/output/repro-new-runtime.log`):

```
SPECULA_REPRO joint_index=7 leader3.last_log=Some(7) leader3.last_applied=Some(LogId { leader_id: LeaderId { term: 1, node_id: 3 }, index: 7 }) leader3.membership=EffectiveMembership { log_id: Some(... index: 7 }), membership: Membership { configs: [{1, 2, 3}, {1, 2}], ... } node1.last_log=Some(6) ...
test ... specula_joint_config_must_not_commit_without_new_component_majority ... FAILED
```

Repeated 5 more times, 5/5 reproduce (`spec/output/repro-new-runtime-repeat.log`); packaged run `bash harness/repro/run_repro.sh` → `spec/output/repro-run_repro.log` (updated: 2/2 tests fail; baseline: 2/2 pass).

## 2b. Consequence: applied-entry divergence (updated revision, 5 voters)

Test: `harness/repro/t91_specula_joint_commit_divergence.rs`. Leader 3 forms
`{1,2,3,4,5}`; isolate 2,4; one write (index 8) acknowledged by 1 and 5;
isolate 1,5, restore 2; `change_membership({1,2,4})` → joint
`[{1,2,3,4,5},{1,2,4}]` at index 9. Then isolate 3,2 and restore 1,4,5.
Safety requirement: two nodes never apply different log ids at one index.

Observed (`spec/output/repro-new-divergence.log`, repeats in
`spec/output/repro-new-divergence-repeat.log`, packaged run
`spec/output/repro-new-runtime-both.log`):

```
SPECULA_DIVERGENCE joint_index=9 joint_committed_by_3=true node3.last_applied=Some(LogId { leader_id: LeaderId { term: 1, node_id: 3 }, index: 9 }) node1.last_applied=Some(LogId { leader_id: LeaderId { term: 3, node_id: 1 }, index: 9 }) ...
```

6/6 runs diverge. Baseline (`spec/output/repro-old-control-divergence.log`):
`joint_committed_by_3=false node3.last_applied=...index: 8`, test passes.

## 3. Baseline control (same test, same schedule)

`spec/output/repro-old-control-runtime.log`:

```
SPECULA_REPRO joint_index=7 leader3.last_log=Some(7) leader3.last_applied=Some(LogId { ... index: 6 }) ... node1.last_log=Some(6) node2.last_log=Some(7)
test ... ok
```

Helper-level control (`harness/repro/old_control_commit_rule_test.rs`,
`spec/output/old-control-commit-rule.log`): the baseline commit rule
(`get_match_log_ids` + `greatest_majority_value`) on the exact acknowledgement
state of §1 yields commit index 1, not 2.

## 4. Attribution

Update-introduced (the update made `VecProgress` the leader commit authority;
the helper was test-only in the baseline). The path crosses Affected Actions
`LeaderAppendEntries` (`ProposeMembership`), `HandleUpdateMatched`
(`update_progress`).
