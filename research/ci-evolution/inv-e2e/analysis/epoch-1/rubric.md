# Rubric: invariant-evolution quality and miss attribution (epoch 1)

Every per-case analysis in this directory follows this rubric, so that cases can be compared. It covers only the 21 sealed epoch-1 runs (7 cases × v0/v1/v2, one run each). Gold is still sealed: no analysis looked for or read Gold or grading material.

## A. Data

Paths are relative to `research/ci-evolution/inv-e2e/`. `WORK` is the experiment's work directory (`$INV_E2E_WORK`); it is not in git and is archived as described in `../../README.md`, section Storage.

| What | Where |
|---|---|
| Prior suite, the common input of all arms | `../blind-incremental-bugs/blind-incremental-v0/<case>/.specula-output/` |
| v2's annotated prior suite and the annotation reports | `inputs/<case>/annotated/` |
| A run's outputs (spec, harness, traces, `analysis-report.md`, `modeling-brief.md`, `bug-report.md`, `changelog.md`, …) | `results/<arm>/<case>/r1/output/` |
| A run's session timeline (agent messages, one line per tool call) | `results/<arm>/<case>/r1/timeline.md` |
| Full session log, when tool results are needed | `WORK/attempts/<arm>/<case>/r1/log/activity.jsonl` |
| Evidence file (v1, v2) | `results/<arm>/<case>/r1/invariant-evidence.json` |
| The agent's edits to source trees | `results/<arm>/<case>/r1/instrumentation/*.diff` |
| Source before and after the update | `WORK/subjects/<case>/old-tree`, `WORK/subjects/<case>/buggy-tree` |
| Mechanical property table | `analysis/out/prop_events-<case>.md` (per prior property and arm: formula change, changed helpers in its definition closure, cfg coverage, evidence entry; a starting point, not a verdict) |

## B. Evolution events

For each arm, list what it did to properties as events. One property can have several events.

| Type | Meaning |
|---|---|
| keep-unaffected | The update does not affect it; kept as is |
| keep-affected | The update affects it (the state, actions or helpers it reads changed); kept as is |
| strengthen | Fewer states allowed |
| weaken | More states allowed (an added premise or exception, a weaker predicate) |
| replace | Semantic replacement; old and new are incomparable |
| representation | Only the state representation changed (renamed variables, new structure); same intent |
| helper-drift | Property text unchanged, but a helper or variable it depends on changed meaning |
| unchecked | Deleted, removed from cfgs, or checked only in fewer or smaller configurations |
| add | New property (canaries are counted, not judged) |
| model-narrowing | Property unchanged, but changes to actions, guards, constraints, constants or cfg scope make relevant states unreachable (equivalent to weakening the check) |

## C. Quality dimensions (judged for every event)

| Dimension | Values | Notes |
|---|---|---|
| Q1 necessity | needed / not-needed / missed | missed: a change was required but not made (under-reaction), e.g. a helper changed and the property was not re-examined |
| Q2 requirement correctness | correct / too-weak / too-strong / wrong-target / unclear | Against the requirement: protocol, documentation, contract comments, test assertions. **Implementation behavior is not a requirement.** |
| Q3 representation fidelity | ok / mismatch / n/a | Does the new formula express the same intent over the new model's state? |
| Q4 non-vacuity | ok / vacuous / untested | Can its premise hold in reachable states; is there a canary or TLC evidence? |
| Q5 evidence | valid / weak / missing / impl-as-req | v0 has no evidence file; use its changelog and reports |
| Q6 trigger | proactive / reactive | reactive: changed to remove a counterexample. A reactive weakening needs a look at whether the counterexample was a bug. |
| Q7 effect on detection | masked / enabled / none / unclear | Did it hide or help find a defect? |

Each judgment cites `file:line` or a timeline turn `[N]`. When unsure, the value is `unclear`, with what evidence is missing.

## D. Miss attribution (cases with a miss)

For each miss:

1. **Where the wrong abstraction came from:** inherited from the prior suite or introduced by this arm (compare the prior suite with the arm's final model).
2. **Which step fixed it:** reconnaissance (01), reference model (02), update analysis (03), Update model (04), completeness review (05), trace validation, model checking. Quote the agent (timeline turn).
3. **Information gap:** which relevant code the agent read and did not read (checked against Read/grep calls in the timeline).
4. **Why the safety nets did not catch it:** what the trace scenarios covered and did not; what the completeness review said; whether a related canary or counterexample was explained away.
5. **Comparison:** what the arm that caught the defect did differently at the same step, and whether that came from an overlay rule or a different exploration path.
6. **Category (several allowed):**
   - anchoring: reusing the prior suite's abstraction or vocabulary, projecting a new mechanism onto old semantics;
   - contract-substitution: modeling what a function should do (contract, name, comment) instead of what it does;
   - unread-code: key code not read (dynamic dispatch, subclass overrides, callers, concurrent paths);
   - equivalence-claim: an unverified "old and new are equivalent" or "not affected" argument;
   - scope-exclusion: the mechanism was deliberately left out of the model's scope;
   - interleaving-omission: a message or event interleaving not modeled;
   - property-gap: the model is faithful, but no property can catch the defect;
   - reporting-gap: found, but not reported as a defect (e.g. only in fix suggestions);
   - budget: time or budget ran out.
7. **Smallest interception point:** at which step, and with which check and which artifact, it would most likely have been stopped (e.g. "for every equivalence argument, observe the changed function body on boundary inputs").

## E. Output

One file per case, `case-<id>.md`:

1. One-paragraph conclusion (evolution-quality differences among the arms; for a miss, its root cause in one sentence).
2. Update summary (what the code change did and which model elements it touches, at most 10 lines).
3. Event table: `| arm | property | event | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 | Q7 | source and notes |`. keep-unaffected events and canaries are counted, not listed.
4. Per-arm summary: good practice, problems, under-reaction.
5. Miss attribution (if any), following D.
6. Corrections to the mechanical table (false rows, e.g. "deleted" caused by a rename or a move to another module).
7. Open and unverified points.

Analyses are read-only: they change no run output, code or other notes.
