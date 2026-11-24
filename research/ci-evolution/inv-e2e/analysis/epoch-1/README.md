# Epoch 1: why bugs were missed, and the quality of invariant evolution

Summary of the per-case analyses of the 21 epoch-1 runs (7 cases × v0/v1/v2, one run each; setup in `../../README.md`). Written 2026-11-21.

- Every judgment in the per-case files follows [rubric.md](rubric.md) and cites `file:line` or a timeline turn.
- The mechanical tables come from `../prop_events.py` (output in `../out/`).
- Gold is still sealed. "Defect" means a defect an arm reported and reproduced in code.
- With one run per cell, the counts below show direction only.

| Case | System, module | File |
|---|---|---|
| case-002 | ZooKeeper, Zab DIFF sync | [case-002.md](case-002.md) |
| case-003 | CometBFT, consensus-parameter updates and replay | [case-003.md](case-003.md) |
| case-004 | OpenRaft, leader transfer and membership change | [case-004.md](case-004.md) |
| case-006 | etcd Raft, linearizable ReadIndex | [case-006.md](case-006.md) |
| case-010 | ZooKeeper, follower sync and shutdown | [case-010.md](case-010.md) |
| case-011 | OpenRaft, Pre-Vote and membership change | [case-011.md](case-011.md) |
| case-012 | OpenRaft, replication progress and commit computation | [case-012.md](case-012.md) |

The arms: v0 is the base `incremental-modeling` skill; v1 adds divergence evidence (a changed property needs a separating state evaluated by TLC); v2 adds the requirement-evidence ledger (`REQ-EVIDENCE` annotations on the prior suite). "§3.1–§3.3" below are the technical directions of issue #188.

> **2026-11-24:** the root cause of each miss, and why risks get dismissed by argument, are in [root-causes.md](root-causes.md); the update-coverage run is in [coverage/](coverage/README.md) and the census of declared scenarios in [scenario-census/](scenario-census/README.md).
>
> **2026-11-23 corrections from TLC evidence** (one directory per case under [evidence/](evidence/))
>
> | Miss | Model can represent it | Arm's own cfgs reach it | Verdict |
> |---|---|---|---|
> | 002 v1 | yes | yes (unmodified `MC.cfg`, depth 38) | missing property; action written to the contract, skipping `peekFirst().hdr` |
> | 010 v0 | no (whole queue made durable on exit) | — | wrong abstraction |
> | 011 B v0 | yes | no (every membership cfg has `MaxElectionCount≤2`) | structural cfg gap |
> | 011 B v1 | yes | yes | missing property / dismissal |
> | 011 C v1, v2 | yes | yes (11–12 states) | missing property / dismissal |
> | 012 v2 | no (commit independent of vector order) | — | wrong abstraction; **not** masked by SYMMETRY |
>
> Other corrections:
> - 004 v2 can represent leader self-transfer (10 states in its main cfg); what it lacks is a property. The masking by `MembershipLimit≤1` is confirmed.
> - 003: the ValidateUpdate conjunct dropped from PUR holds on every reachable state of all arms; v1's `ValidParams` redefinition is an inaccurate ledger entry, not a weakening (read the 003 rows below in that light).
> - 006: v1's and v2's standard `MC.cfg` (`MaxReadLimit=1`) cannot reach the stale read; `ReadDeliveryJustified` holds almost by construction for forwarded reads (Q4 vacuous).
> - 002 v0's second weakening: Q7 none. 010's 144,904-state search used a scenario-view cfg.
> - **Cfgs that structurally exclude the scenario** are more common than estimated: 011 v0, 004 v2, 006 v1/v2, plus partial shapes in 004 v1 and 003 v1. This supports canaries that check scenario preconditions on the cfgs actually run.

## 0. Findings

1. **The misses come from unverified behavior claims, not simply from wrong models.** An arm accepted a claim about what the implementation does from text instead of from execution, and the claim propagated. Counted per arm, there are 7 misses:
   - 2 are wrong model abstractions: 010 v0 and 012 v2;
   - 1 models an action by its contract and misses an unchecked dereference: 002 v1;
   - 4 are cases where the model could express the mechanism, but no property was added or a written argument dismissed the risk: 011 B in v0/v1, 011 C in v1/v2.

   In each miss, the claim:
   - went into the model or into a dismissal;
   - was not distinguished from the truth by trace validation or the completeness review.
2. **Incremental modeling amplifies this.** The prior artifacts (brief, analysis report, abstractions, cfgs, SYMMETRY) supply many ready-made claims. The diff shows what code changed, not which old claims lost their **premises**.
   - 012: the function an inherited abstraction relied on was deleted, and nobody revisited the abstraction.
   - 010: one sentence of the old brief ("drains on exit") was copied verbatim into a new action.
3. **Every arm that caught a defect did so through its exploration path, not through an overlay rule.** Before writing the model, it happened to make one key check:
   - 010 v1/v2: grepped for subclass overrides;
   - 012 v0: checked whether the old tree had callers;
   - 002 v0/v2: matched "the update clears the buffer" with "an unchanged branch assumes it is non-empty".

   Making these results reliable means turning those steps into **checks that must produce an artifact**.
4. **The §3.2 evidence rules fixed visible weakening, but not invisible changes or omissions.** Counts over 173 judged events:

   | Measure | v0 / v1 / v2 |
   |---|---|
   | Weakening events | 10 / 3 / 2 |
   | Valid evidence | 18 / 33 / 45 |
   | Weak or missing evidence, or implementation used as requirement | 46 / 16 / 11 |
   | Reactive changes (made to remove a counterexample) | 16 / 7 / 8 |
   | Model-side narrowing | 9 / 7 / 8 |
   | Helper drift | 4 / 5 / 5 |
   | Missed changes (Q1 missed) | 2 / 4 / 6 |

   **All 9 events judged to have masked a defect are omissions:** a needed property not added, an inherited cfg or SYMMETRY not reviewed, a risk dismissed. None comes from weakening a property.
5. **§3.1 action validation targets this problem directly.** The §3.3 prototypes only close cfg-level gaps. Upstream main's defect ledger (#207) covers dismissals. The proposed strengthening is in §4.

## 1. Attribution of each miss (details in §5 of each case file)

| Miss | Mechanism in the model? | Where it went wrong | Source of the claim | Why the safety nets missed it | What the catching arm did |
|---|---|---|---|---|---|
| 010 v0: SyncRequestProcessor leak | Yes, with wrong semantics | Reconnaissance [45], minute 2.4: read the base class `shutdown(){shutdown(false);}`, assumed equivalence, never opened the subclass | "Drains" from the old brief:88 and old report:92, copied verbatim into a new action (the old TLA+ has no learner-exit action at all) | 15 in-service exits in the traces, but the probes record neither durability nor whether the sync thread is alive, and the queue is empty at exit | v1/v2 grepped for subclass overrides during reconnaissance (minutes 1.7 and 9.7) |
| 012 v2: VecProgress reordering | No (idealized) | Reconnaissance: equivalence argument at [85], written into the model at [92] | The prior model "deliberately abstracts away the sorted-vector layout", on the premise that production commit goes through `greatest_majority_value`; the update deleted that function, v2 recorded it as deleted, and did not revisit the premise | Probes serialize progress by id, losing the order; nested events are removed by preprocessing; the only multi-step scenario uses the smallest id as leader | v0 checked the old tree's callers of VecProgress ("test-only"); v1 wrote "Abstraction revisited" |
| 002 v1: NPE when COMMIT interleaves with NEWLEADER | Yes (`ReceiveSyncCommit`; the pre-state is reachable, TLC reaches it in 27 s) | First model draft [95]: wrote what the branch should do, missed the unchecked `peekFirst().hdr` before it | Contract / the prior model's style of turning implementation checks into action preconditions | The probe sits after the dereference, so no event is emitted on the NPE; the model has no error state | v0/v2 matched "the update clears the buffer" with "the unchanged branch assumes non-empty" before modeling, and observed the NPE in a test |
| 011 B (v0, v1): rounds correlated by probe only | Yes | Both identified it and dismissed it as "as stale as a late response"; v1 never read the `expect` line | An argument with no execution behind it; the prior model's `grants ∪ {source}` copied | No check followed the dismissal | v2 took the code comment and the `expect` contract as requirements and modeled the panic branch |
| 011 C (v1, v2): elections started by Pre-Vote do not recheck voter status | Yes (v1's comment says "no voter check") | v1 added no property; v2 claimed it is covered by MC-1/2 | An unverified "already covered" | v0's fix check shows C remains when only MC-1 is fixed, so the coverage claim does not hold | v0 compared the guards of the new caller with those of existing callers during generation |

**Categories (7 misses, several allowed):** property-gap 6, anchoring 5, equivalence-claim 5, contract-substitution 2, unread-code 2, reporting-gap 2, budget 0, scope-exclusion 0.

**Corrections to earlier per-case notes (not in this repository):**
- 002 v1 did not miss because COMMIT during sync was unmodeled.
- 010 v0 followed the old **documents**, not the old model's semantics.
- 010 v1/v2 did not find the leak earlier because of an old-code worktree.
- 011 is not a modeling error.
- 006 v0's weakening of `UpdReadAckFreshness` is correct for the requirement; the counterexample it let go is not the defect mechanism.
- The "~min" times in those notes were scaled linearly from turn indices and can be off by up to 55 minutes.

## 2. How modeling errors arise

A miss has three links, and in each one text stood in for execution.

1. **Where the claim came from**
   - narratives and premises in the prior artifacts (010, 012);
   - a function's name or contract (012 took VecProgress for the value it should compute; 002 v1 wrote what the COMMIT branch should do);
   - half-read code (010 read only the base class);
   - the agent's own argument (011 B "as stale as a late response", 011 C "covered by MC-k", 012's equivalence sketch).
2. **Where the claim went**
   - into the model: action semantics, abstractions and SYMMETRY follow it, so the model has no counterexample;
   - into property selection: no property is added, so a counterexample in the model goes uncaught;
   - into a dismissal: the lead is dropped.
3. **Why it was not corrected**
   - Trace validation compares only the fields the probes record, and the probes are designed in **the model's vocabulary**. What the model lacks (vector order, sync-thread liveness, the empty queue before a dereference) the probes do not record either. Checker and checked share the same assumptions, so the check cannot tell them apart.
   - The completeness review and Q&A-style self-checks are text too, and the same argument can convince them.

So the fix is not a general "read more code" (002 and 012 did read the code). It is: **every claim that rules out a mechanism, a state or a risk needs an observation of the real code, or a TLC check that can fail.** This is the §3.2 idea, a concrete state for every property change, applied to actions, abstractions and dismissals instead of properties.

## 3. Quality of invariant evolution

### 3.1 Profile of each arm

| | v0 | v1 | v2 |
|---|---|---|---|
| Weakening prior properties | Frequent, with weak or no evidence, often after a counterexample (3 in 010, 1 in 012, `PipelinePrefix` weakened twice in 002) | Rare, all with separating states, but often added afterwards (002 changed 4 in its first model draft; evidence started at turn 237) | Rarest; prior properties almost always kept, with evidence or marked unresolved |
| Declaration vs. action | Several mismatches: 003's changelog says "meaning unchanged" while the formula changed; `MonotoneStep` not in the changelog | 003 changed the meaning by redefining a helper while the ledger says keep; 010's `SnapshotPublishedValid` registered keep while V1 is what is checked | Mostly consistent; 002's Trace.cfg weakening unregistered; 3 `verified: base` lines not refreshed in 011 |
| Proactive strengthening and new properties | Sometimes the best: 004's voter-only action property, plus a property covering "the leader campaigns again"; 011's U3 caught C | Medium | New properties sometimes disagree with their descriptions (004's `ElectionByVoterOnly` cannot see removed nodes); 012's `CommitWitnessSound_new` holds by construction and detects nothing |
| Missed changes | Few | Some | Most (helper drift missed in 011; SYMMETRY and a representation invariant in 012; a cfg in 004 that makes node removal unreachable) |

### 3.2 Problems the rules do not cover (by frequency)

1. **Model-side and cfg-side narrowing**, 7–9 per arm. Examples:
   - a timer that drops in-flight responses (011 v2);
   - clearing the witness on election (012 v0/v1);
   - `TransferTargets={2,3}` (004 v1);
   - `MembershipLimit≤1` (004 v2);
   - SYMMETRY inherited unchanged (012 v2);
   - weakening in Trace.cfg (002 v0/v2).

   Most cite code, none gives a separating state, and some of them removed exactly the relevant part of the state space.
2. **Helper drift**, 4–5 per arm: the property text is unchanged, but a helper or data source it depends on changed.
   - Handled well: 006 v1 got it wrong, the old property caught the error, and v1 fixed it.
   - Missed: 011 v2's `DurableLogNotAhead`.
   - Recorded as keep: 003 v1's `ParameterUpdateReflected`.
3. **Omissions:** properties a new mechanism needs were not added; dismissals were not followed by a check; a documented representation invariant of a new data structure (ordering) was not written as a property. This is the only class directly tied to misses.
4. **The choice of representation drives the later evolution.** 002 v1 changed the meaning of `applied` and was then forced to change 4 prior properties. v2 added a variable `memHist` and changed none. The number of prior properties a representation forces to change should count as a cost when choosing it.
5. **A property should be independent of the mechanism it checks.** v0/v1's `CommitWitnessSound` computes its witness from the real acks, so it is an independent oracle for VecProgress, and it caught MC-1. v2's `_new` uses the same data as the commit itself and holds by construction. This cannot be checked mechanically, but it belongs in the rules.

### 3.3 How to measure quality

- **Mechanical measures** (`../prop_events.py`, no cost): formula changes, changed helpers in the definition closure, cfg coverage, evidence entries, new properties. They locate events and cannot judge them alone:
  - false positives in all 7 cases: renames, inlined canaries, equivalent rewrites;
  - false negatives: changed data sources, model-side narrowing.
- **Judged dimensions** (rubric Q1–Q7): 20–40 events per case; one agent session judges a case.
- **Proposed primary measures:**
  1. the share of weakening-type events (weakening, narrowing, unchecked) with valid evidence;
  2. the number of missed changes;
  3. the number of declaration-vs-action mismatches;
  4. the share of new properties with no detection power (true by construction, or with an unreachable premise).

  Measures 2–4 are where v1 and v2 are currently weakest.

**Fixed in the mechanical table:**
- `check_annotation.properties` dropped a PROPERTIES list that directly followed an INVARIANTS list. The frozen v2 annotations are unaffected: the annotators had annotated those properties anyway.
- A copy of the old model (`OldBase.tla`) shadowed the current definitions in `base.tla`.

**Not done yet:** recognizing renames and replacements (the `replaces` field, `Never*` renames), excluding canaries, and comparing old and new definitions with TLC to decide stronger/weaker.

## 4. What upstream and §3.1/§3.3 offer, and how to strengthen the skill

| Source | Content | Problem it meets | Assessment |
|---|---|---|---|
| upstream main #180 | spec-generation reads code beyond the functions cited in the brief, following callers, callees, shared state, configuration and failure paths; a cfg may bound unrelated actions only while the target stays reachable | 010 (read only the base class), 004 (cfg makes the target unreachable) | Right direction, but still a prose rule; 002 and 012 did read the code, so this alone is not enough |
| upstream main #207 | every suspected defect goes into a defect ledger; "a defect you could not rule out after checking compensating mechanisms is still recorded — Bug Confirmation decides" | the dismissals in 011 B/C; 002 v2's CR-1 | Directly relevant. It lives in the one-shot pipeline (code_analysis and the Phase 4 consolidation); the incremental final-result flow does not use it yet |
| upstream main #201/#205 | liveness; a timed-out safety run without violations counts as completed | none directly | — |
| §3.1 action validation (etcd prototype) | execute the affected actions on the real implementation from mapped pre-states and compare with the model's transitions | 012 (real VecProgress vs. the model operator; the case-012 analysis found a divergence within 4 steps with a line-by-line Python port), 010 (sync thread alive after exit), 002 (COMMIT on an empty queue) | **The most direct fit**: it would have stopped all three "wrong model" misses. The prototype needs hand-written adapters per system; a lightweight version is proposed as E2 below |
| §3.3 update-coverage | checks that the cfgs reach the affected actions with the relevant checks enabled | 004's `TransferTargets` and `MembershipLimit`; 012's SYMMETRY | Finds cfg narrowing (one kind of missed change) automatically; does not address model fidelity |
| §3.3 prefix-branch / env-update | branch from recorded runs; find environment actions the Update model leaves out | none directly | Better exploration of a given model; cannot find errors in the model itself |

**Proposed strengthening, a new overlay tentatively called v3** (not adopted yet; each item names the cases it targets):

- **E1 Re-examine inherited premises (decision gate in reconnaissance, chapter 01).** List every "X is abstracted away" or "X behaves as Y" in the prior brief, reports and model comments, with the symbols it depends on. If the diff deletes, reroutes or overrides any of them, re-examine the claim, with E2 evidence. (012, 010)
- **E2 Execution evidence for behavior claims (lightweight action validation).** Record every claim that rules out a mechanism or risk: "equivalent", "not affected", "already covered", "dismissed", and "this function does Y". Discharge each one in one of these ways:
  - exhaustive or boundary execution of the real function on small inputs, compared with the model operator;
  - a TLC canary, or a check on a copy of the model with the fix applied;
  - if neither works, the claim goes into the defect ledger (as in #207) instead of being dropped.

  This is the counterpart of §3.2's separating state for actions. (012, 011, 002)
- **E3 Dispatch and implicit-precondition audit (update analysis, chapter 03).**
  - Add an "actually dispatched method" column to the old/new behavior table: the receiver's declared type and subclass overrides.
  - When the update clears or resets state, list the unchanged code that reads it, write down its implicit preconditions, and add for each a canary "the action is enabled while the precondition fails".
  - Take the guard difference between a new caller and existing callers.
  - Every `expect`/`assert` on a new path needs either a crash branch in the model or a precondition property.

  (010, 002, 011)
- **E4 Probes that can tell the difference (validation 02/03).** Probes sit at branch entry; every post-effect a changed action claims is recorded; at least one scenario yields different traces for the model's claim and its negation. (010, 012, 002)
- **E5 Evolution rules for omissions and hidden narrowing (merged into divergence evidence).**
  - A property with a changed helper in its definition closure must be re-examined, not recorded as keep.
  - Model-side narrowing and changed or inherited cfgs, SYMMETRY and constants are treated as weakening.
  - Documented representation invariants of new data structures are written as properties.
  - A new property states its independence: its oracle must not be defined by the output of the mechanism it checks.

  (012, 004, 011, 003)

## 5. Next steps

1. **Choose the base of the next epoch.** E1–E5 strengthen the skill and must be shared by every arm. Decide first whether to merge upstream main (#180, #207 and the Specular rename; the rename moves skill paths, so the hook anchors must be realigned).
2. **Write the v3 overlay:** E1–E5, plus wiring #207's defect ledger into the incremental final result. Smoke-test it on the etcd dev set.
3. **Revisit the cases with misses:** run v3 on 002, 010, 011 and 012 and compare with the arm that missed in epoch 1. Two runs per case (8 runs, about $250) show whether the misses go away reliably. If the budget allows, also run v0 + E1–E4 as a control, to separate the effect of the modeling checks from that of the evidence rules.
4. **Complete the mechanical table** (renames and replacements, excluding canaries, TLC-based stronger/weaker comparison). Each future epoch runs the table first and then the rubric.
