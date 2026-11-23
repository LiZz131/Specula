# update-coverage on the epoch-1 final specs

Question: the TLC evidence (`../evidence/`) found cfgs that structurally exclude the scenario of a bug.
Would `../../../../update-coverage/check.py` (#188 §3.3), run without an agent on each arm's final spec,
have flagged them? Predictions were written before any run: [predictions.md](predictions.md).

## Setup

- `run_coverage.py` runs check.py's own code (probes from `Update.tla:AffectedActions`, simulation,
  retry, report) on `results/<arm>/<case>/r1/output/spec`, with three adaptations described in its
  docstring: every `MC*.cfg` and `Update*.cfg` is run (epoch-1 suites also use `MC-x` and `Update-x`
  names); each cfg runs on the module that defines what it names, falling back to `MC` on an unassigned
  constant; reachability canaries are left out of the gap report by name.
- 120 s per cfg at depth 100, seed 1; cfgs behind a gap get 240 s more with seed 2; one TLC worker per
  cfg. 569 cfgs over the 21 specs, none ended in error.
- `run_all.sh` runs all 21; `python3 run_coverage.py --rebuild` rebuilds the reports from `out/*/*/report.json`.

## Result 1: none of the four known cfg gaps is flagged (all four predictions hold)

| Gap (from the TLC evidence) | Flagged | Why not |
|---|---|---|
| 004 v2: `MembershipLimit <= 1`, node removal unreachable | no | `AffectedActions` is only `MCTransferLeader`; no probe covers membership change |
| 011 v0: `MaxElectionCount <= 2` in every membership cfg, bug B unreachable | no | both probes are taken in these cfgs; the gap is a third election round, not an action |
| 006 v1/v2: `MC.cfg` has `MaxReadLimit = 1`, context reuse unreachable | no | the probe is taken in `MC.cfg`; the gap is a repeated context, not an action |
| 004 v1: `TransferTargets = {2,3}` in the main cfg | no | `MCTransferLeader` is taken; the gap is one argument value |

The tool checks configs against the agent's own `AffectedActions`, at the granularity of an action.
These gaps are at the granularity of a scenario: the action happens, but not with the arguments, the
state or the number of rounds the bug needs. `AffectedActions` has 1 to 9 probes per spec, often one
or two.

## Result 2: what it does report

Four gap groups over 21 specs:

| Spec | Never checked while | Checks | Reading |
|---|---|---|---|
| v0 case-002 | `MCLearnerLogPending`, `MCLearnerCommitAfterUpToDate`, `MCLearnerAbort` (never possible) | `Not*Reached` | reachability canaries whose names the filter does not match; noise |
| v1 case-002 | `MCLogSyncProposal`, `MCStartServing` (never possible) | 11 invariants of `MC.cfg` (`PipelinePrefix`, `ElectionSafety`, …) | v1's main cfg never lets a learner log a sync proposal or start serving; those actions happen only in `Update-*` cfgs, which enable 1–4 checks each. A real cfg fact, not tied to v1's NPE miss (the NPE state is before both actions; `../evidence/case-002/`) |
| v1 case-010 | `MCLearnerExitLeaderGone`, `MCReloadDatabase` (never possible), `MCLearnerExit` (possible) | `MonotoneUnlessRecoveryV1`, `OrderedHistories` | two invariants enabled only in cfgs without the exit paths; v1 found the bug elsewhere |
| v2 case-002 | `MCEnterBroadcast` (never possible) | `DischargeContext` | a discharge-only check; expected |

"Never possible" is from sampled runs (never seen enabled), not a proof.

## What this means for proposal A

Action-level coverage is cheap (a few minutes per spec) and finds real cfg facts, but it does not
catch the gaps behind the epoch-1 misses. Catching them needs scenario-level probes: a predicate for
each scenario's precondition (a node removed; a pre-vote grant from outside the frozen config in a
later round; a reused read context), checked for reachability on the cfgs actually run. check.py
already has the machinery (an action constraint that records the first state where a probe holds);
what is missing is the predicates.

Whether an agent would write those predicates without hindsight was checked against the arms' own
text, not run:

- 004 v2 names the scenario: `results/v2/case-004/r1/output/analysis-report.md:64`, "a leader can be
  removed from voters yet remain leader long enough to finish the change". A precondition probe for
  it would be unreachable under `MembershipLimit <= 1` (structural; `../evidence/case-004/`).
- 011 v0's scenario U3 (`modeling-brief.md:61-73`) is about the candidate being removed, not about a
  grant from outside the frozen config in a third round. A probe written from v0's own scenarios would
  probably not have covered bug B.
