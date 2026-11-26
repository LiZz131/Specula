# I-9 results: ci-init anchoring

Plan and reasoning: notes `CI/1121-inv演变质量/迭代地图.md`, section I-9. Work directory (outside git):
`/mydata/bingzhuo/inv-e2e-i9` (`INV_E2E_WORK`); session logs stay there (`inits/<case>/r<rep>/log/`).

## inits/case-011/r1 (P1 pilot, 2026-11-26)

Blind ci-init on the base tree with main's skills (six skills the V0 task names), Specular layout,
`main-tools-r2`, claude-opus-5-5 xhigh, 4 h / $100 limits (`prepare_init.py`, `run_init.py`).

- EXITED_0, `COMPLETED_WITH_LIMITED_COVERAGE`, trace validation `LIMITED_COVERAGE`, model checking
  `FINDINGS`; $32.10, 204 min; network audit clean.
- `prior/`: the frozen prior suite (P1). No temporal property: the cfgs check `ElectionSafety`,
  `TypeOK` and the action properties `CommittedMonotonic`, `VoteMonotonic`; `Trace.cfg` checks
  `TraceMatched`. `modeling-brief.md` §5: "No liveness property is proposed: the scope forbids
  progress claims without a grounded fairness assumption, and election progress depends on timer
  randomness."
- `manifest.json`, `attempt.json`, `final-response.json`, `log/run-manifest.json`,
  `work-source.diff` (the instrumentation left in the writable source copy).

Not run (stopped for quota, 2026-11-26): ci-init for case-002, annotation (P1a), and the eight
incremental runs. See the notes for how to resume.
