# V1 incremental outputs

- `runs/` — final TLC logs (one per run id) and `ledger.ndjson` (command, exit, outcome, states).
  `final-*` = final trace-validation gate; `mc-*`, `base-*`, `upd-*`, `hunt*`, `canary-*`, `v0-hunt-*` = model checking.
- `runs-round1/` — pre-repair round (before the `Crash` vote-tally repair); superseded.
- `runs-superseded-gate1/` — first final-gate attempt (before the neg5 tightening); superseded.
- `campaign*/`, `campaign-main.out`, `followups-main.out` — lane outputs of
  `../../run-incremental-campaign.sh` and `../../run-incremental-followups.sh`.
- `harness/` — build, scenario, reproduction and old-revision control logs.
- `trace-inventory.json`, `campaign-summary.{json,md}`, `validation-handoff.md`.
- `sany/` — SANY logs; `cfg-static-check.log` — generation-time cfg operator check.
- Counterexamples for findings: `../cex/` (copies of final-model logs).

States: `/dev/shm/specula-e2e-case-002/<run-id>`, removed after every run.
One early exploratory trace validation (before the wrapper existed) used the
trace-debugger MCP tool's own temporary directory; it was removed.
