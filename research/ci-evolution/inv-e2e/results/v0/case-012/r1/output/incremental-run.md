# Incremental Specula run — case-012 (OpenRaft, baseline ce863f4 → update aa05a38)

**Decision:** MODEL_CHANGE_REQUIRED (`MODEL_UPDATED`). The update moves leader
commit from `LeaderState::calc_commit_log_id` (full joint-majority recomputation)
to `Engine::update_progress` over a leader-owned `VecProgress` (cached
committed value, quorum set rebuilt on membership change).

**Finding:** MC-1 (Critical, update-introduced, REPRODUCED) — a leader can
commit a joint-membership entry without a joint quorum; with 5 voters two nodes
then apply different entries at the same index. Baseline control is clean.

| What | Where |
|---|---|
| Update analysis / disposition | `analysis-report.md` (§ Incremental update analysis), `modeling-brief.md` (§ Incremental update) |
| Reference suite | `spec/base.tla`, `spec/MC.tla`, `spec/Trace.tla`, cfgs |
| Update view | `spec/Update.tla`, `spec/Update_*.cfg` |
| Instrumentation | `spec/instrumentation-spec.md`, `harness/` (`run.sh`, patch, preprocessor) |
| Fresh traces | `traces/*.ndjson` (27; V0 archive in `traces/v0-archived/`) |
| Trace validation | `spec/output/trace-validation-final.summary`, mutants `spec/output/trace-validation-mutant.summary` |
| Model checking | `spec/validation-summary.md` (campaign tables), logs in `spec/output/` |
| Finding | `spec/bug-report.md`, `spec/findings.json`, `spec/confirmation-MC-1.md`, `spec/final-result.json` |
| Reproduction | `harness/repro/run_repro.sh`, tests `harness/repro/t90_*.rs`, `t91_*.rs` |
| Change history | `spec/changelog.md`, `spec/brief-coverage.md` |

Working copies: `work-source/` (instrumented copy of the update), `repro-new-source/`
and `old-control-source/` (`git archive` exports of the two neutral commits plus
the reproduction tests). `artifact/` is unmodified.
