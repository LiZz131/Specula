# Validation/specification changelog

All entries below concern the V0 suite itself. None is an implementation finding, and no exact-old property was weakened to obtain a green result.

| Stage | Symptom | Classification | Correction |
|---|---|---|---|
| Trace setup | cfg parsing rejected directive ordering and a negative constant literal | trace configuration | moved init/spec directives before constants and defined `Nil` in TLA+ rather than cfg |
| Trace semantic check | standard modules did not provide the assumed `Max`/`Min` operators | trace/base specification | added explicit integer `IMax`/`IMin` operators |
| Election trace | trace action deadlocked although the implementation transition was enabled | trace specification | post-snapshot fields had been compared to the pre-state; added explicit primed next-state matchers |
| Progress/majority traces | record field selection failed inside `CHOOSE` | trace specification | bound the selected sequence index in `LET`, then selected the record field |
| Model run 1 | `Nil` was used as a function key while evaluating a log match | model specification | made sentinel branches explicit with `IF`, preserving the same log-match relation |
| Model run 2 | bounded terminal states were reported as deadlocks | model configuration | disabled deadlock checking for intentionally terminating counter budgets |
| Code-faithfulness review | election freshness used the candidate term instead of last-log term/index | model specification | aligned `LogUpToDate` with exact-old `last_log_id` comparison abstraction |
| Code-faithfulness review | conflict handling omitted exact-old `has_log_id`'s committed-prefix shortcut | model specification | committed prefixes now match without re-reading purged/local term state |
| State identity review | bound counters were omitted from the view | model configuration | retained counters in `MCView` so paths with different remaining budgets are not merged |
| Atomicity review | membership promotion was also exposed as a standalone MC step | model specification | retained promotion inside commit/delivery actions and removed the standalone transition from `Next` |
| Scale calibration | broad bounds did not drain within 600 seconds | coverage bound | preserved the scale log as incomplete evidence and added tight, converged main/scenario configs; status remains LIMITED_COVERAGE |

After the final tightening, all implementation traces were replayed again and all final model configurations were rerun.
