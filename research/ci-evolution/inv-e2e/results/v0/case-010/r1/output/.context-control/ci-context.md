# CI context (case-010 incremental) — updated
- Disposition: MODEL_CHANGE_REQUIRED (final JSON: MODEL_UPDATED).
- Final model: base/MC/Update/Trace in spec/ (snapZ TRUNC repair, ApplyTxn serving guard, no drain ACKs, LeaderEpochAgreed, EnterElectionPhase).
- Validation: final gate final4-gate-trace-*-v3b.log PASS (4 traces); non-vacuity final4-nonvacuity-* rejected at expected lines.
- Finding MC-1 (TRUNC-window exit keeps in-memory commit; update covers SNAP only): witness spec/output/counterexamples/MC-1-witness-deterministic-commit.log; consequence MC-1-consequence-durable-hole.log; bug-report.md, findings.json written.
- F1 done (all LIMITED, no violation). F2 running (scripts/run_F2.sh -> spec/output/final-campaign-F2.out).
- Remaining: collect F2, verification-summary.md, final-result.json, final-response.json (both places), brief-coverage final, cleanup /dev/shm, revert artifact? (keep instrumentation applied; patch preserved).
