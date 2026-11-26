# Confirmation Report

Reproduced bugs: 1; other unresolved findings: 0; other dispositions: 1.

| Entry | Finding | Status | Counts as final bug? |
|---|---|---|---|
| 1 | MC-1 | REPRODUCED | yes |
| 2 | CR-1 | FALSE POSITIVE | no |

## Entry 1: Pre-Vote round survives leader establishment and makes the new Leader re-elect itself

- **Finding ID**: MC-1
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: A Candidate whose election timer fires starts a Pre-Vote round without dropping its running election; establish_leader clears only `candidate`, so `pre_candidate` survives; handle_pre_vote_resp then calls elect() on the established Leader and do_elect keeps the Leader object.
- **Trigger scenario**: Candidate at term T times out (e.g. slow save_vote, or trigger().elect(true) while Candidate) and pre-votes for T+1; the delayed real vote for T arrives first (Leader at T); the granted Pre-Vote reply arrives afterwards.
- **Impact**: The healthy term-T Leader bumps its own term to T+1 while keeping a Leader object at (T, committed); RaftCore::trigger_routine_actions -> try_leader_handler hits debug_assert leader.vote >= state.vote and the core panics (Fatal::Panicked); in release builds the Leader runs behind its persisted vote.
- **Evidence**: [evidence 1](<spec/confirmation-MC-1.md>), [evidence 2](<spec/bug-report.md>), [evidence 3](<spec/output/MC-1-counterexample-update-full.log>), [evidence 4](<spec/output/update-nofault.log>), [evidence 5](<spec/output/repro-MC-1-reliability.log>), [evidence 6](<harness/repro/t13_specular_mc1_prevote_reelect.rs>), [evidence 7](<harness/repro/run-repro.sh>), [evidence 8](<spec/output/trace-update-property-candidate_prevote_then_leader.log>)

## Entry 2: Pre-Vote documentation claims an Unreachable response counts as a grant

- **Finding ID**: CR-1
- **Status**: FALSE POSITIVE
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: docs/protocol/pre_vote.md says the default pre_vote returns Unreachable and that Unreachable counts as a grant; the code synthesizes a granting Ok by default and never counts transport errors.
- **Trigger scenario**: A peer's pre_vote RPC fails with Unreachable while Pre-Vote is enabled.
- **Impact**: None at runtime: the failed reply is dropped (not a grant), as the repository test pre_vote_unreachable_peer_is_not_a_grant confirms; only the documentation is stale.
- **Evidence**: [evidence 1](<spec/confirmation-CR-1.md>), [evidence 2](<spec/output/baseline-new-elect.log>)

## Validation limits

- All model checking is bounded (3 nodes, MaxTerm 2, <=2 elections, <=2 Pre-Vote rounds, <=1 crash, <=1 drop, <=5 messages); 30-minute BFS/simulation budgets did not exhaust the state space (LIMITED_COVERAGE).
- Traces are engine-level (real Engine methods, runtime command execution emulated by an explicit RuntimeDrain event); RaftCore tick guards, RPC dispatch, and the PreVoteResponse gate as executed in RaftCore are validated by source review, model checking, and the integration reproduction rather than trace replay.
- Open focused checks are provisional and budget-limited; the discharge obligation passed only within its BFS budget.
- Two prior-model defects were repaired (LogLE on absent logs; leader lease on establishment); prior state counts are not comparable, but with both repairs reverted and Pre-Vote disabled the suite reproduces the prior exhaustive MC.cfg graph exactly.
- The Level 3 timer-path reproduction slows save_vote through a test-storage hook (memstore only); the Level 1 reproduction uses only public APIs.
