# Validation handoff (Validation 4)

- Source under test: `artifact/` commit `update` d7176ef916c7d2e3f2a0eed612875d7ce3e646b1
  (parent `baseline` d86101c = V0 exact-old). Toolchain `cargo +stable` 1.100.0.
- Harness command: `harness/run.sh` (applies `harness/instrumentation.patch` to a fresh copy,
  builds, runs 9 unit + 2 integration scenarios, writes fresh traces). Log:
  `spec/output/harness.log`, `spec/output/run-sh.stdout`.
- Harness provenance: V0 patch reused (applies cleanly; kept as
  `harness/instrumentation.v0.patch`); rebased patch only adds update fields/probes (see
  `harness/INSTRUMENTATION.md`). No V0 component replaced.
- Fresh traces (20, all nonempty): `spec/output/trace-inventory.txt` (name, lines, sha256 prefix).
  - 8 V0 regression scenarios rerun on the update tree: election, vote-request,
    follower-append, learner/joint/uniform-membership, partial-replication, restart.
  - update unit scenario: lease-touch (U-S2).
  - RaftCore chains: `core-t14-*` (5, the update's own `t14_transfer_leader`),
    `core-learner-*` (6, U-S1 `t14_specula_transfer_to_learner`). Raw hook output:
    `traces/raw-core/`.
- Archived V0 traces (`traces/archived-v0/`, 8 files): disposition **superseded** — each
  scenario was rerun on the new implementation; V0 files lack `lease_enabled`,
  `accepted_vote_io` and request last-log-id fields required by the current `Trace.tla`.
- Trace validation: real TLC with `TraceMatched` over all 20 fresh traces against the final
  suite: `spec/output/trace-validation-round2.txt` (20/20 PASS; per-trace
  `spec/output/trace-*.log` contain "Finished checking temporal properties" and "No error has
  been found"). Round 1 (pre-R8) also 20/20.
- Field consumption / non-vacuity: 8 single-field mutations rejected
  (`spec/output/trace-mutation-check.txt`).
- Affected-action coverage in fresh traces: TransferLeader target-elect (`core-t14-n2-c0`,
  `core-learner-n3-c0`), lease-disable (`core-t14-n1-c0`, `core-learner-n{0,1,2}-*`),
  ignored (`core-t14-n1-c1`); elect via TransferLeader; ReceiveVoteResponse panic branch
  (`core-learner-n3-c0`); first consumers: VoteRequest accept after disable (lease
  re-enabled), VoteRequest lease rejection on the non-transferred leader (`core-t14-n0-c1`),
  VoteResponse grant/won/other, touch keeps lease disabled and update re-enables
  (`lease-touch`).
- Interaction gaps: no real trace of an absent (removed) transfer target, of crash/restart
  across a transfer, or of RaftCore storage callbacks (model-checked only).
- Semantic spec files changed during validation: yes, repair R8 (self vote-response ordering)
  after an MC Case B; full trace regression rerun afterwards (round 2, 20/20).
- Instrumented source tests: 199 passed / 0 failed (`spec/output/source-tests.log`).
