# Epoch 1: root causes of the misses, after the TLC evidence, coverage check and census

Written 2026-11-24. It combines the per-case evidence ([evidence/](evidence/)), the update-coverage
run ([coverage/](coverage/README.md)) and the census of declared scenarios
([scenario-census/](scenario-census/README.md)). One run per cell, so counts show direction only.

## 1. Each miss

None of the seven misses comes from TLC limits or from a weakened property. Each comes from a claim
taken from text, not from execution. The claim sits in one of three places: the abstraction, the cfg
bounds, or the decision not to check.

| Miss | Model can represent it | Arm's own cfgs reach it | Direct cause | Intent |
|---|---|---|---|---|
| 010 v0 | no | — | "a learner's exit makes its whole queue durable" (`base.tla:318-330`), carried over from the old brief; base-class and subclass `shutdown` assumed equivalent, the override never read | not thought of |
| 012 v2 | no | — | the prior abstraction (commit independent of vector order) kept although the update broke its premise; the checking property reads the same data as commit, so it holds by construction | not thought of (an equivalence argument) |
| 011 B v0 | yes | no (`MaxElectionCount <= 2` in every membership cfg) | the cfg bound excludes the third election round the bug needs | not thought of |
| 002 v1 | yes | yes (`MC.cfg`, depth 38) | the action written to its contract, skipping `peekFirst().hdr`; every probe placed after the dereference | the empty-buffer premise never stated |
| 011 B v1 | yes | yes | dismissed by argument | thought of, dismissed |
| 011 C v1 | yes | yes (11–12 states) | noted in a model comment only; no property, not reported | thought of, not reported |
| 011 C v2 | yes | yes (11–12 states) | claimed to be covered by MC-1/MC-2, never checked | thought of, dismissed |

- Wrong abstraction 2, cfg cannot reach 1, reachable but not reported 4.
- The evidence rules of v1 and v2 cut unsupported weakenings (10 / 3 / 2) but do not touch omissions,
  which is where every miss lies.
- "Declared but not covered" explains only one gap, 004 v2, and that is not a miss (census: 10 such
  items out of 215).

## 2. Why "dismissal" happens: an asymmetry in the skill

In the incremental-modeling skill at base `5880061f`:

- `03-update-focused-analysis.md`: "Turn **consequential** uncertainties into Scenarios for later trace
  validation or model checking". The agent decides what is consequential.
- The same file asks every Scenario for "a plausible correctness consequence"; once the agent argues
  there is none, the risk never becomes a Scenario.
- `05-completeness-review.md` checks only that "every excluded behavior has an explicit scope
  rationale". Any written rationale passes.
- For weakening a property the skill says the opposite: "Do not weaken a still-promised property
  merely because the draft violates it. **The later validation phase decides** …".

So a property change must go to validation, while a risk can be closed with a paragraph. The v1/v2
evidence rules cover property changes only.

The three forms in case-011:

1. **Argument** (B v1): `analysis-report.md:290-297`, "Reviewed and dismissed (code review) … no
   finding". The argument relies on a minimum interval between restarts, which v1's own model
   abstracts to nondeterminism; v1's bug report says the manual trigger "has no timing constraint".
2. **Subsumption claim** (C v2): `modeling-brief.md:370-372`, "i.e. through MC-1/MC-2", unchecked.
   C is reachable in 11 states of its own `MC-membership.cfg` on a path that does not go through
   MC-2; v0's fixcheck showed C survives a fix of MC-1 alone.
3. **Silence** (C v1): "no voter check" in a comment (`base.tla:272-275`), no property, no report.

Each could have been settled on the arm's own model in minutes.

## 3. Rules this points to, and how each will be tested

| Cause | Misses | Rule | Zero-cost test on epoch-1 |
|---|---|---|---|
| closed by text | 011 B v1, C v1, C v2 | every identified risk ends as an executed check, a reported finding, or an "unverified" entry in the defect ledger (#207); a subsumption claim needs the fix-and-recheck that v0 did | run the 114 collected dismissals as canaries on copies of the models; count how many are reachable |
| implicit premise not stated | 002 v1 | list every state the update clears or changes, the unchanged code that reads it, and that code's premise; one canary per premise | apply the rule by hand to the 7 diffs; does it name the known premises? |
| cfg bound | 011 B v0 | an independent run with every counting constant raised by one, or a larger random simulation | rerun the final specs that way; does it expose the known gaps, at what cost and noise? |
| wrong abstraction | 010 v0, 012 v2 | every inherited abstraction and equivalence argument is checked by running the changed function on small inputs | the 012 differential script already does this (`evidence/case-012/`); repeat for 010 |
| declared but not covered | 004 v2 | every declared scenario and property intent gets a precondition canary that some cfg running the check reaches | done in the census: cheap, catches 004 v2; keep as an auxiliary completion check |
