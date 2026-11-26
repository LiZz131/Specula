# Incremental CI report

MODEL_CHANGE_REQUIRED: the update moves the learner's hand-off of synced proposals before the NEWLEADER ACK. The model, Trace spec and harness were updated and validated; model checking found that the ACK still precedes durability (MC-1, reproduced on the update and the old revision), and code review found three update-introduced sync/lifecycle defects (CR-1..CR-3, reproduced).

CI verdict: **FAIL**. Reproduced bugs: 4; other unresolved findings: 0; other dispositions: 0.

[Findings and evidence](confirmed-bugs.md) · [Severity](bug-severity.md)

## Validation limits

- All model checking is bounded (3 servers, 1 txn, up to 3 epochs, 2 crashes, 1 drop/snapshot); BFS runs stopped at 30-minute budgets with non-empty queues, so no-violation results are LIMITED_COVERAGE, not proofs.
- The deep U2/U3 witnesses (depth 25/38 from Init) were not reached by BFS or simulation from Init; they were found from a seed state that full MCNext reaches from Init (canary-seed.log) and re-found with full MCNext from that seed.
- Open/discharge checking is not applicable: Update.tla defines no EnvUpdate; focused relations are restrictions of MCNext.
- Not modeled: late joiners to a broadcasting leader, observers, reconfiguration, exception/liveness paths (handled by code review CR-1..CR-3); zxid order approximated by log length; FLE votes persist across rounds; TRUNC does not roll back the visible committed/applied state.
- Fresh traces did not exercise SyncProposalApplied, the TRUNC directive, or a crash inside the ACK-to-fsync window (the reproduction test covers the crash window).
- Known-status (issue/history) searches for the findings were not performed because the run is blind; novelty is undetermined.
- Only JDK 21 was available; the hypothetical flush-before-ACK control is a local patch, not an upstream fix.
