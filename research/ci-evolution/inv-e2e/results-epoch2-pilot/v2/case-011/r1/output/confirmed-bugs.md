# Confirmation Report

Reproduced bugs: 2; other unresolved findings: 0; other dispositions: 1.

| Entry | Finding | Status | Counts as final bug? |
|---|---|---|---|
| 1 | MC-1 | REPRODUCED | yes |
| 2 | MC-2 | REPRODUCED | yes |
| 3 | CR-1 | FALSE POSITIVE | no |

## Entry 1: Pre-Vote responses of an earlier round are accepted by a later round of the same term

- **Finding ID**: MC-1
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: Engine::pre_elect builds every round from the unchanged local vote, so all rounds at one local term share the leader id (term+1, self); RaftCore::does_pre_candidate_vote_match compares only leader ids, and Candidate::grant_by expects the responder to be a voter of the current round.
- **Trigger scenario**: A node starts a Pre-Vote round, starts another round at the same term (timer restart, trigger().elect(true), or after leader contact dropped the first), and a granted response to the first round arrives; for the panic, the responder was removed from the voter set between the rounds.
- **Impact**: The grant is tallied by the wrong round: RaftCore panics (Fatal::Panicked) when the responder is no longer a voter, and otherwise a real election can start on grants the current round never received, inflating the term.
- **Evidence**: [evidence 1](<spec/confirmation-MC-1.md>), [evidence 2](<spec/bug-report.md>), [evidence 3](<spec/output/cex-update-full-PreVoteStaleResponseIgnored.log>), [evidence 4](<spec/output/cex-hunt-PreVoteResponseNeverPanics.log>), [evidence 5](<harness/repro/t13_specular_pre_vote_repro.rs>), [evidence 6](<harness/repro/repro-current.log>), [evidence 7](<harness/repro/repro-current-release.log>), [evidence 8](<traces/prevote_stale_member_panic.ndjson>), [evidence 9](<spec/evidence/trace-lens/prevote_stale_member_panic.log>)

## Entry 2: A Pre-Vote round started while Candidate survives leader establishment; the new Leader starts another election

- **Finding ID**: MC-2
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: The election timer (and trigger().elect(true)) runs pre_elect for a Candidate without cancelling its election; establish_leader does not drop Engine.pre_candidate, and handle_pre_vote_resp calls elect() on quorum without checking the node's role, leaving a stale leader object.
- **Trigger scenario**: A Candidate starts a Pre-Vote round while its real election is in flight; the real election wins, then the Pre-Vote grants arrive.
- **Impact**: The freshly established Leader steps down and starts an election at term+1 (term inflation, leadership loss); in debug builds RaftCore panics on try_leader_handler's assertion leader.vote >= state.vote.
- **Evidence**: [evidence 1](<spec/confirmation-MC-2.md>), [evidence 2](<spec/bug-report.md>), [evidence 3](<spec/output/cex-update-full-TimerPreVoteElectionFromFollowerState.log>), [evidence 4](<harness/repro/t13_specular_pre_vote_repro.rs>), [evidence 5](<harness/repro/repro-current.log>), [evidence 6](<harness/repro/repro-current-release.log>), [evidence 7](<traces/candidate_prevote_establish.ndjson>), [evidence 8](<spec/evidence/trace-lens/candidate_prevote_establish.log>)

## Entry 3: Pre-Vote backward-compatibility documentation contradicts the default pre_vote and grant counting

- **Finding ID**: CR-1
- **Status**: FALSE POSITIVE
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: docs/protocol/pre_vote.md says the default pre_vote returns Unreachable and Unreachable counts as a grant; the code returns a granted response and never counts transport errors.
- **Trigger scenario**: Reading the protocol document for a mixed-version cluster.
- **Impact**: No behavioral consequence: code, code comments, and tests agree; only the document is stale.
- **Evidence**: [evidence 1](<spec/confirmation-CR-1.md>)

## Validation limits

- Bounded three-node model (MaxTerm 2, MaxLogIndex 4, bounded election/membership/crash/drop counters and message bag); 30-minute BFS runs did not exhaust their queues and simulations are sampled (spec/output/campaigns.md).
- Model time is abstract: tick restarts and response delays are unconstrained; reachability of each finding was confirmed in code (spec/confirmation-MC-1.md, spec/confirmation-MC-2.md).
- Follower-side membership replication and the leadership-transfer lease bypass are not modeled (V0 abstractions kept); the MC-1 panic is reached through leader-side membership change.
- Engine-level traces cannot observe the RaftCore Pre-Vote response filter; it is exercised by the integration reproduction.
- Old-revision controls are not applicable: the old revision has no Pre-Vote round or Trigger::elect(bool).
- No fairness or liveness claim.
