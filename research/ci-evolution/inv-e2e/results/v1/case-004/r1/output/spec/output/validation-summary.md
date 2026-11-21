# Validation handoff (incremental run, update d7176ef9)

- Source: `artifact/` HEAD `d7176ef916c7d2e3f2a0eed612875d7ce3e646b1` (`update`), parent
  `d86101c7c585656d90d55e30f2e6c923b0f65e18` (`baseline`), plus `harness/instrumentation.patch`.
- Toolchain: `cargo 1.100.0` stable (pinned nightly unavailable offline; recorded in `harness.log`).
- Harness command: `timeout 60m harness/run.sh` -> log `spec/output/harness.log`
  (12 unit traces + 22 window traces, all nonempty).
- Trace validation command: `scripts/validate_traces.sh r3` -> `spec/output/trace-validation-r3/`
  (`summary.tsv`, one TLC log per trace). Result: **34/34 PASS**, each log contains
  `Finished checking temporal properties` and `Model checking completed. No error has been found.`
  under `PROPERTIES TraceMatched` with full `ValidatePostState`.
- Field-consumption negative control: `python3 -I scripts/field_consumption_check.py $PWD` ->
  `spec/output/field-consumption/summary.tsv`: 27/27 single-field/argument mutations REJECTED.

## Fresh trace inventory

| Trace | Events | Layer | Scenario / purpose |
|---|---:|---|---|
| election, vote-request, follower-append, learner-membership, joint-membership, uniform-membership, partial-replication, restart | 4,2,2,2,2,2,4,2 | unit | prior V0 regression scenarios rerun on the update revision |
| elect-learner | 3 | unit | U1: Engine effect of TransferLeader on a learner; real panic recorded |
| elect-absent | 2 | unit | U1: absent target, candidate dropped |
| follower-membership | 2 | unit | repair R3: follower applies membership entries |
| vote-request-logid | 3 | unit | repair R1: full-LogId freshness, reject + grant |
| window/t14-transfer-to-voter (9 files) | 2 each | RaftCore | U2/U3: lease-only at n1, transfer-elect at n2, vote requests at n0/n1, self + remote grants and establishment at n2, stale-vote transfer ignored at n1 |
| window/t99-transfer-to-learner (13 files) | 2 each | RaftCore | U1: lease-only at n0..n2, transfer-elect at learner n3, **VoteResponsePanic at n3**, peers grant term-2 vote (old leader steps down), re-election |

## Coverage of update actions and interactions

- Affected action `HandleTransferLeader`: all three branches observed in real RaftCore
  (elect: n2 voter, n3 learner; lease-only: n0/n1/n2; ignored: n1 stale vote).
- `Elect` from voter, present learner and absent node observed.
- First consumers: peer `handle_vote_request` with lease disabled (grant), candidate
  `handle_vote_resp` (self-grant, remote grants, establishment), and the learner panic.
- Not observed by traces (model-checked only): crash/restart around the transfer (U4), commit by the
  new leader, follower append of the new leader's entries at RaftCore level (unit layer covers the
  handler). Reason: the window layer observes only the transfer and vote steps; these are recorded
  as validation gaps, not passes.

## Archived traces

`traces/archived-v0/*.ndjson` are the immutable exact-old traces; superseded for validation by the
fresh reruns of the same scenarios (same names in `traces/`). They lack `last_term`/`last_node`
(VoteRequest) and `entries` (FollowerAppend) required by the repaired Trace wrappers.

## Semantic spec changes made during validation

Yes: `CoreVoteResponsePanic`, the quorum-member guard in `ReceiveVoteResponse`, the broadened
`ReceiveVoteReject`, and the Trace-only `accVoteIO` observer (see `spec/changelog.md` Round 1).
The final full-suite replay (r3) was run on the final validation candidate.

## Final regression gate

`scripts/validate_traces.sh final` on the final artifacts: 34/34 PASS
(`spec/output/trace-validation-final/summary.tsv`).

## Harness reproducibility check (final scripts)

`harness/run.sh` was rerun unchanged from a scratch copy (`build/harness-check/`, clean worktree of
d7176ef9). It exited 0, produced 12 unit and 22 window traces (`build/harness-check/run.out`), and all
34 replay successfully against the final `Trace.tla` (`build/harness-check/spec/output/tv/summary.tsv`),
including a fresh `VoteResponsePanic` window for learner 3. The recorded `traces/` set is the one
validated above; the rerun traces are kept separately because window file sequence numbers vary
between runs.
