# Confirmation Report

Reproduced bugs: 2; other unresolved findings: 0; other dispositions: 1.

| Entry | Finding | Status | Counts as final bug? |
|---|---|---|---|
| 1 | MC-1 | REPRODUCED | yes |
| 2 | MC-2 | REPRODUCED | yes |
| 3 | CR-1 | FALSE POSITIVE | no |

## Entry 1: Pre-Vote round started while Candidate survives leader establishment and makes the new leader re-elect

- **Finding ID**: MC-1
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: establish_leader/become_leader do not reset Engine.pre_candidate, and handle_pre_vote_resp calls elect() on a Pre-Vote quorum without checking that the node is still the non-leader whose vote the round probed; a Candidate can start such a round because the tick skips only Leaders and Trigger::elect(true) has no role check.
- **Trigger scenario**: A Candidate at term T starts a Pre-Vote round (election timer or Trigger::elect(true)) while its real vote replies are in flight; a peer grants both the real vote and the term T+1 Pre-Vote (its uncommitted vote carries no lease); the real grant arrives first and the node becomes Leader at T; the Pre-Vote grant is delivered afterwards, within the RPC timeout.
- **Impact**: The freshly established Leader abandons term T and starts an election at T+1 that peers holding its lease reject, leaving the cluster without a working leader for at least a lease and inflating the term (the disruption Pre-Vote is documented to prevent); with debug assertions the stale Leader object trips Engine::try_leader_handler and RaftCore panics.
- **Evidence**: [evidence 1](<spec/confirmation-MC-1.md>), [evidence 2](<spec/bug-report.md>), [evidence 3](<spec/findings.json>), [evidence 4](<spec/output/MC-1_update_full_PreVoteElectionPremiseCurrent.out>), [evidence 5](<spec/output/MC-1_final_update_full_PreVoteElectionPremiseCurrent.out>), [evidence 6](<spec/output/pre-nonmember-repair/mc-update-focused.log>), [evidence 7](<spec/output/mc-hunt-stale-round.log>), [evidence 8](<spec/repro/test_bugMC-1_pre_vote_after_establish.rs>), [evidence 9](<spec/repro/run-MC-1-repro.sh>), [evidence 10](<spec/repro/MC-1-repro.patch>), [evidence 11](<spec/repro/MC-1-repro-debug.log>), [evidence 12](<spec/repro/MC-1-repro-release.log>), [evidence 13](<spec/repro/MC-1-repro-backtrace.log>), [evidence 14](<traces/pre_vote_after_establish.ndjson>), [evidence 15](<spec/output/trace-pre_vote_after_establish.log>), [evidence 16](<spec/repro/run-all-repro.log>)

## Entry 2: Stale Pre-Vote grant from a node outside the current round's voter set panics RaftCore

- **Finding ID**: MC-2
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: Pre-Vote responses are correlated only by the pre-candidate leader id, which every round started from the same local vote shares, while each round freezes its own voter set; handle_pre_vote_resp passes any matching grant to Candidate::grant_by, which expects the granter to be in that set.
- **Trigger scenario**: A node runs a Pre-Vote round while peer P is a voter and P's grant is delayed; the voter set changes so that P is no longer a voter; the node starts another round from the same local vote (e.g. Trigger::elect(true), or the tick); P's delayed grant arrives within the RPC timeout.
- **Impact**: grant_by's expect("target not in quorum set") panics and the node's RaftCore task terminates (follower or leader; debug and release builds), so the node stops serving until restarted.
- **Evidence**: [evidence 1](<spec/confirmation-MC-2.md>), [evidence 2](<spec/bug-report.md>), [evidence 3](<spec/findings.json>), [evidence 4](<spec/output/MC-2_hunt_stale_membership_PreVoteGrantFromRoundMember.out>), [evidence 5](<spec/output/MC-2_final_hunt_leader_PreVoteGrantFromRoundMember.out>), [evidence 6](<spec/output/MC-2_full_sim_PreVoteGrantFromRoundMember.out>), [evidence 7](<spec/repro/test_bugMC-2_stale_pre_vote_grant_nonmember.rs>), [evidence 8](<spec/repro/specular-repro-all.patch>), [evidence 9](<spec/repro/run-all-repro.sh>), [evidence 10](<spec/repro/MC-2-repro-debug.log>), [evidence 11](<spec/repro/MC-2-repro-release.log>), [evidence 12](<spec/repro/run-all-repro.log>)

## Entry 3: pre_vote.md backward-compatibility paragraph contradicts the implemented transport-error semantics

- **Finding ID**: CR-1
- **Status**: FALSE POSITIVE
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: docs/protocol/pre_vote.md says the default pre_vote returns Unreachable and that Unreachable counts as a grant; the code's default returns a synthesized grant and never counts a transport error as a grant.
- **Trigger scenario**: Reading the documentation; at runtime an Unreachable Pre-Vote reply is not a grant (shipped test pre_vote_unreachable_peer_is_not_a_grant).
- **Impact**: None in the implementation: the code behavior is the intended one (comments, network trait docs, Config docs, tests); only the prose is stale and should be corrected.
- **Evidence**: [evidence 1](<spec/confirmation-CR-1.md>), [evidence 2](<spec/repro/CR-1-t12-pre-vote.log>)

## Validation limits

- LIMITED_COVERAGE: bounded three-node model (MaxTerm 2, MaxLogIndex 4, at most 2 election starts, 2 Pre-Vote starts, 2 membership appends, 1 crash, 1 drop, 5 in-flight messages; hunt configs narrow unrelated faults); every BFS run stopped at its 30-minute budget with a non-empty queue and every simulation is time-bounded, so no run is an exhaustive pass.
- No fairness or liveness property is claimed.
- Trace validation covers 17 engine-level traces (20 events) driven by test fixtures; runtime-only behavior (tick timing, the in-flight-round rate limiter, the RPC timeout, transport errors, the default-grant network implementation) is abstracted; HandlePreVoteResponseTally/Stale/NonMember are model-checked but not observed in traces.
- Open and discharge checks depend on the EnvUpdate rely (v3) and are bounded; the open model is not exhaustive.
- Followers' membership replication is not modeled (inherited abstraction), so the follower variant of MC-2 is covered by the integration reproduction only; the transfer bit of leadership-transfer elections is not propagated in the inherited model (independent of this update).
- Two inherited model defects were repaired in this run (absent-log LogLE equality; HandleVoteResponse lease effects); the prior suite's three-voter MC results were vacuous for leader paths and are not reused.
- Upstream novelty of MC-1/MC-2 is undetermined: issue trackers and history were not searched under the isolation contract.
