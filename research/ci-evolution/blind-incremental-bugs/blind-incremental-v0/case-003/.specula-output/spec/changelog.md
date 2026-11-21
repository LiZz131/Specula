# Validation changelog

## Round 1 — Trace validation

- [result] Six fresh, nonempty implementation traces matched every event and
  post-state field in `Trace.tla`; `TraceMatched` was satisfied in all runs.
- [classification] No implementation/spec/trace mismatch was encountered, so
  no property, action, or capture point was weakened or changed.

## Round 1 — Model checking

- [result] `MC.cfg` completed its bounded BFS with 5,126 distinct states and no
  invariant violation.
- [result] The three scenario hunting configurations completed bounded BFS with
  no invariant violation. Scenario 1's diameter was 18, so a depth-100 random
  simulation followed and checked 80,000,001 states across 800,000 traces with
  no violation. Scenario 2 and 3 BFS diameters were 27 and 33.
- [non-vacuity] Seven deliberately negated reachability invariants each failed
  as expected, preserving witnesses for accepted/rejected updates, crash,
  app-only replay, real replay, mock replay, and handshake completion.

## Result

Converged in one trace-first round with no fixes and no model-checking findings.
All conclusions remain limited by the documented model and environment bounds.

