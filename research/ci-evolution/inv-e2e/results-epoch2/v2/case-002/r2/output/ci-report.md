# Incremental CI report

MODEL_CHANGE_REQUIRED: the update moves learner logging of DIFF-synced proposals before the NEWLEADER ACK but does not wait for their fsync. Model, harness and traces were updated; model checking found a CommittedQuorumDurable counterexample that was reproduced on the updated implementation (a transaction served by the leader is lost after the acking learners crash). Two further update-introduced defects were reproduced from code review.

CI verdict: **FAIL**. Reproduced bugs: 3; other unresolved findings: 0; other dispositions: 0.

[Findings and evidence](confirmed-bugs.md) · [Severity](bug-severity.md)

## Validation limits

- All TLC campaigns are finite-bound: canonical MC/base runs are exhaustive only up to the inherited level-23 state constraint; the full update BFS stopped at its CommittedQuorumDurable counterexample, focused/open/discharge BFS runs stopped at their 30-minute budget (on a superset transition relation) and were followed by 30-minute simulations on the final model (LIMITED_COVERAGE, not proofs).
- The stale data-tree election vote of CR-2 is not represented in the model (votes use durable history); it is evidenced by a real trace only.
- CR-3 (proposal ACK consumed as NEWLEADER ACK) is a liveness/availability issue outside the safety model; confirmed only by reproduction.
- The MC-1 reproduction uses a test-fixture fsync hold (slow disk) and SIGKILL-equivalent data-directory images; without a slow disk the window was not hit in 3 natural-timing runs.
- JDK 21 / in-process multi-server JUnit environment, as in the prior run.
