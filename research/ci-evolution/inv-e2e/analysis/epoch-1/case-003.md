> Translated from the Chinese analysis of 2026-11-21; the rubric is [rubric.md](rubric.md).

> **2026-11-23 correction from TLC evidence** ([evidence/case-003/](evidence/case-003/README.md))
> - The claim that v1's redefinition of `ValidParams` weakened PUR does **not** hold: the dropped ValidateUpdate conjunct holds on every reachable state of all three arms (exhaustive: 76K / 40K / 1.46M states); it only repeats the accepting action's guard. v1's problem is an inaccurate ledger entry (helper meaning changed, recorded keep, no separating state), not admitted states.
> - v0's changelog "meaning unchanged" holds on reachable states; the text changed but the claim is not wrong.
> - v1 keeping one legal non-ABCI parameter: the bug stays reachable, but the shape of the real reproduction (changing another parameter at the same time) is exhaustively unreachable in its cfg, so "no effect on detection" holds only partly.

# case-003: invariant evolution quality (CometBFT consensus-parameter update and replay)

Rubric: [rubric](rubric.md) (epoch-1). Abbreviations follow section A of the rubric, with paths relative to `research/ci-evolution/inv-e2e/`: `R = ..` (`research/ci-evolution`), `E = .`. `WORK` is the experiment's work directory, archived outside git (see `../../README.md`, section Storage); `buggy-tree` is `WORK/subjects/case-003/buggy-tree` and `old-tree` is `WORK/subjects/case-003/old-tree`.
Old model = `../blind-incremental-bugs/blind-incremental-v0/case-003/.specula-output/spec/` (written `OLD/` below). Each arm's output = `results/<arm>/case-003/r1/output/spec/` (written `v0/`, `v1/`, `v2/`); its timeline is `results/<arm>/case-003/r1/timeline.md` and its evidence `results/<arm>/case-003/r1/invariant-evidence.json`. v2's annotated prior is `inputs/case-003/annotated/`. No Gold or scoring material was read.

## 1. Conclusions

- **The substantive changes the three arms made to existing properties are almost the same.**
  - The old model abstracts `ValidateBasic + ValidateUpdate` with a static set `ValidParams`. The update makes `ValidateUpdate` depend on "the currently enabled height, the new enable height, and the block height". A static set cannot express this, so all three arms had to change the validity clause of `ParameterUpdateReflected` (PUR below).
  - In the end all three arms keep only ValidateBasic in PUR and move the enable-height rule into new properties. The moved rule is semantically equivalent: a height that has already been reached cannot be changed; a change can only be to 0 or to a future height.
- **The difference is whether the change was declared honestly.**
  - v2 registered it as `modify / semantic replacement (weakening …)`, and showed with the trace-derived divergence state E1 and the constructed control state E2 that the detection power moved to `AcceptedVEUpdateRespectsRules`.
  - v0 rewrote PUR in code, but the changelog says "meaning unchanged".
  - v1 did not change the text of PUR. It redefined the helper `ValidParams` as "ValidateBasic only", while the evidence ledger records `keep/keep`. This is an undeclared helper-drift.
- **In the mechanical table, 7 of v2's "9 changes" are false positives.** The 7 `NeverReached*` canaries only inline `~ReachedX` as `"x" \notin coverage`; the semantics are identical. The real changes are only TypeOK (representation change) and PUR (semantic replacement), as many as v0.
- **All new properties are relevant; none is vacuous.** All three arms have a property "a compliant update must not be rejected", and all three triggered the same defect. v2 has the widest coverage: the rejection side covers rows 5, 7, 9, and there is a per-height VE history property; it also marks the "already reached" clause honestly as an evidence conflict. v1's canaries are the most fine-grained. v0 has two small problems: its "compliant" on the rejection side follows the protocol literally, and the precondition of P-U2 has no witnessing canary.
- **No missed bug.**

## 2. Update summary

- Changed files: `ConsensusParams.ValidateUpdate` in `types/params.go`, plus `params_test.go` and the changelog. The changelog describes the fix of ASA-2024-001 "Validation of VoteExtensionsEnableHeight can cause chain halt", see `WORK/subjects/case-003/buggy-tree/.changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md`.
- The old rule first checked `params == updated → nil` (old-tree `types/params.go:212-214`). The new rule is a 9-row decision table (buggy-tree `types/params.go:208-262`), which changes the outcome for three kinds of input:
  - Enabling from 0 to a future height: old rule rejects, new rule accepts (row 7).
  - Cancelling a height that has not been reached: old rule rejects, new rule accepts (row 5).
  - Re-sending an unchanged height that has already been reached: old rule accepts, new rule rejects (row 6). This is the reported defect.
- The new unit tests assert errors for `100→100 @100` and `100→100 @300`, and delete the old test "no error when unchanged". The protocol text (`spec/abci/abci++_app_requirements.md:760-777`) only says "Must always be set to a future height. Once set to a value different from 0, its value must not be changed."
- Affected model elements:
  - the guards of `UpdateStateAccepted` / `UpdateStateRejected`;
  - the parameter representation: the opaque identity becomes `[non-ABCI part, ve]`, and the update becomes a record with a flag for whether Abci is present;
  - PUR and TypeOK, which read these states, and the reachable states of the properties `RejectedUpdateDoesNotInstall`, `SuccessfulApplyAdvancesExactlyOne` and `NormalPhaseIsSynchronized`.
  - `execution.go` and `replay.go` were not changed.

## 3. Event table

There are 15 existing properties: 7 `NeverReached*` canaries, TypeOK, MCTypeOK, and 6 behavioural properties.

- **keep-unaffected (not listed one by one):** in all three arms `PersistedHeightRelationships` and `RecoveryNormalOnlySupported`, 2 each.
- **Existing canaries:** 7 per arm, semantics unchanged; v2's text change is in section 6.
- **New canaries (counts only):** v0 11, v1 18, v2 13. In all three arms the canaries are witnessed:
  - v0: `timeline [210][217]`;
  - v1: `[235]`, 25/25;
  - v2: `validation-report.md:115`, 20/20.

In the table below "same as above" means the same as the previous row.

| arm | property | event | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 | Q7 | source and notes |
|---|---|---|---|---|---|---|---|---|---|---|
| v0 | TypeOK (MCTypeOK follows) | representation | needed | correct | ok | ok | weak | proactive | none | From `v0/base.tla:439`. Parameters become `ParamRecords`, the update becomes `UpdateOrNone`. The changelog only mentions the representation change. |
| v0 | ParameterUpdateReflected | replace (split): the validity clause is weakened to ValidateBasic; the installed-value clause is a representation change | needed | correct | ok | ok | weak | proactive | none | `v0/base.tla:485-493`. The old clause `pendingParam \in ValidParams` (`OLD/base.tla:379`) merely repeated the guard in the old model, a tautology (`OLD/base.tla:132`). The enable-height rule actually moved to P-U2/P-U3 (`v0/Update.tla:133,144`); together they are equivalent to v2's AVURR. But `v0/changelog.md` says "re-expressed … (meaning unchanged)" and does not say where the validity semantics went, so the declaration is inaccurate. The decision was made at `timeline [78]`, in the generation phase; it was not triggered by a counterexample. |
| v0 | RejectedUpdateDoesNotInstall | keep-affected | needed (keep is correct) | correct | ok | ok | missing | proactive | none | The new rejection cases (rows 4, 6, 8, and "re-send unchanged value") all reach `rejected`. v0 gives no per-property reason why these properties are kept; the only visible evidence is the TLC result, no violation in MC.cfg (`[179]`). |
| v0 | SuccessfulApplyAdvancesExactlyOne | keep-affected | same as above | correct | ok | ok | missing | proactive | none | Same as above. |
| v0 | NormalPhaseIsSynchronized | keep-affected | same as above | correct | ok | ok | missing | proactive | none | Parameter equality now compares records, an implicit representation change. |
| v0 | ContractLegalUpdateAccepted (P-U1) | add | needed | correct (somewhat conservative, see note) | ok | ok | valid | proactive | **enabled** | `v0/Update.tla:109-128`. "Compliant" is defined as: Abci absent, or value unchanged, or enabling from 0 to a height greater than h. The basis is protocol `:760-777,779-789,1118-1129`. Under the literal reading of "must not be changed", cancelling or changing an unreached height (rows 5, 9) is not compliant, so these cases are not required to be accepted. The defect is reported by this property (`[179-186]`). `confirmation-MC-1.md:24-26` records that the new unit test expects rejection, so v0 did not ignore the contrary evidence; it just did not mark the requirement as disputed. |
| v0 | VEEnableHeightImmutableOnceEnabled (P-U2) | add | needed | correct | ok | **untested** | valid | proactive | none | `v0/Update.tla:133`. The precondition is "update accepted and the enable height already reached", which can only be produced by row 1 (Abci absent) when E has been reached. None of the 11 canaries witnesses this precondition (`Update.tla:162-204`); it may be reachable, but there is no evidence. |
| v0 | VEStatusOfDecidedHeightsPreserved (P-U3) | add | needed | correct | ok | ok | valid | proactive | none | `v0/Update.tla:144`. An interaction property on the consumer side (reconstructLastCommit, blocksync); it can cover row 6 "change to a past height". It only compares active and persisted in a single step and does not track per-height history. |
| v0 | MockReplayRevalidationAccepts (P-U4) | add | needed | correct | ok | ok (low discriminating power) | valid | proactive | none | `v0/Update.tla:153`. With FinalizeBlock's deterministic guard in place, this property is close to model-internal consistency, but its precondition is reachable (`NeverRealReplayRejected` is violated). |
| v0 | InstalledParamsBasicValid | add (structural) | needed | correct | ok | ok | valid | proactive | none | `v0/base.tla:465`. On the Trace side, `TraceValidBodies` was derived from the post-state, which made this property vacuous on traces; mutant M5 exposed this and it was then fixed (`v0/changelog.md` Round 1 [fix-trace]). Good practice. |
| v1 | TypeOK (MCTypeOK follows) | representation | needed | correct | ok | ok | valid | proactive | none | `v1/base.tla:496`. `Params == [other, veh]`. |
| v1 | ParameterUpdateReflected | **helper-drift** (in substance the validity clause is weakened to ValidateBasic), registered as keep | needed | correct | ok | ok | **weak** | proactive | none | The text is unchanged (`v1/base.tla:533-537`), but the meaning of `ValidParams == {p \in Params : ValidateBasicOK(p)}` (`v1/base.tla:45`) shrank from "ValidateBasic + ValidateUpdate" to ValidateBasic only. The enable-height rule is taken over by `VEReachedImmutable`/`VEChangeOnlyToFuture` (`v1/Update.tla:122,130`), with a correct result. But `invariant-evidence.json` records `decision: keep, kind: keep` for PUR and does not mention the semantic change of the helper. Line 7 of the changelog only says "static ValidParams replaced by … ValidateBasicOK" and does not connect it to PUR. Under the divergence-evidence rule a divergence state should be present here. |
| v1 | ParameterUpdateReflected / NormalPhaseIsSynchronized | **model-narrowing** (cfg) | not-needed | — | — | — | missing | proactive | none | The old cfgs have two legal non-ABCI identities (`OLD/MC.cfg`, `MC_hunt_scenario1_params.cfg`: `p0,p1`). All of v1's cfgs have only `ValidOthers = {"o0"}`, so an update that "only changes the non-ABCI field" becomes an identity update in v1, and the installed-value clause of PUR can only be exercised on VE changes. This update does not touch non-ABCI fields, so detection is not affected, but no reason is given. v0 and v2 both keep two legal identities. |
| v1 | RejectedUpdateDoesNotInstall / SuccessfulApplyAdvancesExactlyOne / NormalPhaseIsSynchronized | keep-affected | needed (keep is correct) | correct | ok | ok | valid | proactive | none | The evidence ledger gives `affected_because` for each; keep evidence is E1, E4c, E5c and others, including trace-derived states. |
| v1 | UnchangedVENotRejected | add | needed | correct (requirement disputed, noted) | ok | ok | valid | proactive | **enabled** | `v1/Update.tla:151`. The divergence state of E1 is constructed, but traces T1/T1r/T6 observed the implementation producing the same state. `limitations` says that the new unit test conflicts with the protocol and "not edited toward the implementation". The focused check reports a violation (`[218]`); that the halt persists across restart is witnessed at `[229-230]`. |
| v1 | EnableFromDisabledNotRejected | add | needed | correct | ok | ok | valid | proactive | none | `v1/Update.tla:139`. Covers only the regression of row 7, not row 5 (cancelling an unreached height). |
| v1 | VEReachedImmutable / VEChangeOnlyToFuture | add | needed | correct | ok | ok | valid | proactive | none | `v1/Update.tla:122,130`. Together with InstalledParamsBasicValid the two are equivalent to v2's AVURR. The canary `NeverReachedReachedVEAccepted` witnesses the precondition, which is better than v0. |
| v1 | InstalledParamsBasicValid / ValidationInputStable | add (structural) | needed | correct | ok | ok | valid | proactive | none | `v1/base.tla:556,563`. ValidationInputStable writes the assumption "persistedParam is the receiver of ValidateUpdate" as a checkable invariant; v0 and v2 rely on this assumption only in comments. |
| v2 | TypeOK | representation (plus two model-internal consistency conjuncts) | needed | correct | ok | ok | valid | proactive | none | `v2/base.tla:494-521`. Added `updatePresent = pendingParam.present` and `DOMAIN veHist = 1..blockStoreHeight`. Evidence E6 is trace-derived. |
| v2 | ParameterUpdateReflected | **replace**: the validity clause is weakened to ValidateBasic, the enable-height rule moves to AVURR; the installed-value clause becomes `ApplyUpdate(persistedParam, pendingParam)`, a representation change | needed | correct (see note) | ok | ok | **valid** | proactive | none | `v2/base.tla:588-609`. E1 is a trace-derived divergence state (`ve_enable_future.ndjson` event 5): the old PUR is FALSE (the old `ValidParams` is instantiated with the ruling of the old code, see `evidence/E1/EE1.tla:6`), the new PUR is TRUE, and the requirement says allowed. E2 is a constructed control state (`1→0 @h=1` changed to "accepted"): the new PUR is TRUE and AVURR is FALSE, showing that the detection power was moved, not lost. This change is the `initial_decision: modify` that v2 fixed in the initial phase and never changed; it was not triggered by a counterexample. Note: AVURR does not apply the protocol's "must not be changed" to heights not yet reached. v2 says this interpretation explicitly in the REQ-EVIDENCE starting at line 63 of `UpdateProps.tla`, based on the new unit test and the V0 old unit test. |
| v2 | RejectedUpdateDoesNotInstall / NormalPhaseIsSynchronized | keep-affected (registered as representation-only) | needed (keep is correct) | correct | ok | ok | valid | proactive | none | Evidence E3, E5. The formulas are unchanged; the compared objects became records. |
| v2 | SuccessfulApplyAdvancesExactlyOne | keep-affected | same as above | correct | ok | ok | valid | proactive | none | E4. The REQ-EVIDENCE note (`v2/base.tla:559`) explains why the guard change does not affect the height assignment it reads. |
| v2 | AcceptedVEUpdateRespectsRules | add (takes over the enable-height part of PUR) | needed | correct | ok | ok | valid | proactive | none | `v2/UpdateProps.tla:76`. It is wider than the code's accept set, because it allows "already reached and unchanged"; as a requirement-level safety property this is reasonable. |
| v2 | PermittedVEUpdateNotRejected | add | needed | **unclear** | ok | ok | valid | proactive | none | `v2/UpdateProps.tla:87,107`, covering "must not be rejected" for rows 5, 7, 9. Rows 5 and 9 (cancelling or changing an unreached height) are supported only by the new unit test and the V0 unit test, and conflict with the protocol's literal "must not be changed". For the clause "already reached and unchanged", v2 marked it unknown because the same new unit-test file asserts the opposite. So the same test file is trusted in one place and not in another, yet the ledger status says `requirement`, not mixed. No effect on detection (it holds on the new code). |
| v2 | UnchangedVEUpdateNotRejected | add | needed | correct (after-reached clause marked unknown) | ok | ok | valid | proactive | **enabled** | `v2/UpdateProps.tla:131`, clause description at lines 127-128. Evidence for and against is listed; the counter-evidence includes the new unit test `params_test.go:168-169` and the decision-table comment. E10 is trace-derived (`replay_real_ve_unchanged_rejected.ndjson`). `Update_full` shows a violation (`[230]`). |
| v2 | VEHistoryStable | add (interaction property) | needed | correct | ok | ok | valid | proactive | none | `v2/UpdateProps.tla:30`. Depends on the new variable `veHist` (`v2/base.tla:187`), which records per height the enable height in effect for each stored block. It is stronger than v0's P-U3 and covers multiple updates. E7 is obtained by trace-edit, E7c is the control state. |
| v2 | VEEnableMonotone | add | needed | correct | ok | ok | valid | proactive | none | `v2/UpdateProps.tla:45`, evidence E8. |
| v2 | StartupLastCommitConsistent | add | not-needed (redundant) | correct | ok | ok | valid | proactive | none | `v2/UpdateProps.tla:59`. v2 itself notes that it is a corollary of VEHistoryStable; while VEHistoryStable holds, it gives no further detection power. |

## 4. Per-arm summary

**v0** (58 min, $14.69)

- **Good:**
  - In the generation phase (`[69]`) it wrote an exhaustive projection script that compares the branches of the old and new ValidateUpdate (`spec/analysis/validate_update_projection.py`) and lists exactly the inputs whose result flips in three ways.
  - It defined "compliant" using the protocol text.
  - It used trace mutant M5 to find and fix the vacuity of `InstalledParamsBasicValid` on traces.
- **Problems:**
  - The rewrite of PUR is described as "meaning unchanged", and the destination of the validity clause is not declared anywhere.
  - No keep-affected property has a written reason.
  - The precondition of P-U2 has no witnessing canary.
  - P-U1 counts rows 5 and 9 as non-compliant, which is more conservative than v2. This is not wrong, because the protocol literally says so, but v0 does not say it is an interpretive choice.
- **Under-reaction:** none found.

**v1** (41 min, $15.88)

- **Good:**
  - Every add in the evidence ledger has a constructed divergence state and a trace-derived control state.
  - It used `ValidationInputStable` to turn an implicit assumption into an invariant.
  - Canaries cover the decision table row by row.
  - It made an exact-old control trace (`[187]`).
- **Problems:**
  - PUR is a helper-drift but was registered as keep. This is exactly the case the divergence-evidence rule is meant to stop: the property semantics changed with no divergence state. No actual loss resulted only because the VE rule properties made up for it.
  - The legal non-ABCI identities went from 2 to 1 with no reason given (model-narrowing).
- **Under-reaction:** PUR (a declaration that should have been made was not).

**v2** (67 min, $20.19)

- **Good:**
  - PUR is the only one of the three arms honestly registered as "weakening plus transfer", with the trace-derived divergence state E1 and control state E2 showing that detection power was not lost.
  - It used `veHist` to build the most complete interaction property on the consumer side (saving and rebuilding the extended commit).
  - Disputed clauses were split per clause, and it wrote "what evidence would resolve the dispute".
  - `UpdateProps.tla` makes the same predicates also checked on real traces (`Trace_update_props.cfg`).
- **Problems:**
  - `PermittedVEUpdateNotRejected` trusts the new unit test asymmetrically (see event table).
  - `StartupLastCommitConsistent` is redundant.
  - The pointless inlining of 7 canaries made noise for the mechanical comparison.
- **Under-reaction:** none found.

## 5. Missed-bug attribution

**No missed bug.** All three arms reported "re-sending an unchanged, already-reached VE enable height is rejected, ApplyBlock fails, the node halts, and it is rejected again on replay". The three paths are basically the same: all read the diff in the generation phase, derived the flip of row 6 from the decision table, wrote the property first, and then confirmed it with traces and TLC. The differences:

- **v0:** projection script (`[69]`) → P-U1 (`[94]`) → MC violation (`[179-186]`) → Level-0 reproduction on a real node (`[227-240]`). The old-code control shows that the old code does not reject the same input.
- **v1:** read the diff and protocol (`[48]`-`[61]`) → wrote the evidence ledger and the constructed divergence state E1 before observing the code (`[125]`) → trace observation (`[187]`, including an exact-old control) → focused MC violation (`[218]`) → added a witness for "halt persists across restart" (`[229-230]`).
- **v2:** read the diff, the protocol, and the deleted old unit test (`[7]`, `[45]`, `[60]`) → added coverage markers for every decision row (including `veRejIdentity`) in base.tla (`[83]`) → the trace first observed the rejection (`[141]`) → `Update_full` violation (`[230]`), and wrote the evidence conflict into the clause.

So detection is unrelated to the overlay: all three arms obtained the defect by reading the diff. The overlay made a difference in only two places: how the requirement was characterized (v0 treated it as a regression; v1 noted the dispute; v2 marked it unknown per clause), and the form of the evidence (v1 and v2 have divergence states).

## 6. Errata for the mechanical table (`E/analysis/out/prop_events-case-003.md`)

1. **v2's 7 `NeverReached*` marked "changed" are false positives.**
   - The old model and v2's input (the annotated version `inputs/case-003/annotated/spec/MC.tla:78-93`) are both written as `NeverReachedX == ~ReachedX`, `ReachedX == "x" \in coverage`.
   - v2 writes `NeverReachedX == "x" \notin coverage` (`v2/MC.tla:104-110`), which is semantically identical.
   - So the only existing properties whose formulas v2 really changed are TypeOK and PUR, the same as v0, not "9, far more than v0".
2. **v1's PUR marked "same" should be helper-drift, in substance a weakening of the validity clause.**
   - `ValidParams` went from a cfg constant of the old model (the ruling of ValidateBasic plus ValidateUpdate) to `{p : ValidateBasicOK(p)}` (`v1/base.tla:45`).
   - Although the table lists that the helper `ValidParams` changed, the conclusion is written as "same" plus `keep/keep`, which hides this semantic change.
   - So the statement "v1 kept all existing properties and changed only TypeOK" in the earlier summaries (the two earlier summaries, not in this repository) is inaccurate.
3. **The PUR changes of v0 and v2 are semantically almost identical** (compare `v0/base.tla:488-492` with `v2/base.tla:605-609`).
   - The comparison "v0: 0 (re-expressed under the new rule) / v2: 1 semantic migration" in the second earlier summary (line 111) reflects a difference in what each **declared**, not in what each **changed**.
   - v0 also moved the enable-height rule into the new properties; it just did not declare it.
4. **MCTypeOK is "same; helpers changed" in all three arms.** The helper change comes from the representation change of TypeOK; it is benign helper-drift, not a quality event.
5. **The counts of additions must be classified before reading.**
   - v0 16 = 4 update properties + 1 structural property + 11 canaries.
   - v1 24 = 4 + 2 + 18 canaries.
   - v2 19 = 6 update properties + 13 canaries.
   - Without canaries it is 5 / 6 / 6, a smaller gap than it looks.
6. **The table cannot show model-narrowing.** v1 reduced the legal non-ABCI identities from 2 to 1 (see event table); the cfg counts in the mechanical table do not reflect this.
7. **A correction to the earlier notes.** The first earlier summary says "v0 directly treated this as a regression", but v0 recorded in `confirmation-MC-1.md:24-26` that the new unit test expects rejection and the old unit test was deleted. v0 just did not mark the requirement status as disputed.

## 7. Uncertain and not verified

- **Whether the precondition of v0's P-U2 is reachable was not verified.** No corresponding canary or TLC evidence was found. I did not run TLC myself, so it is marked untested.
- **The requirement status of rows 5 and 9 in v2's `PermittedVEUpdateNotRejected` can only be marked unclear.** The protocol's literal text ("must not be changed") constrains the application, not CometBFT's validation, so the requirement status of these rows depends on interpretation.
- **Whether the clause "already reached and unchanged" is really a defect depends on the Gold's characterization.** The Gold is sealed; this document makes no judgement and only evaluates how each arm handled the evidence conflict.
- **Not re-checked one by one:**
  - the TLC log values of each arm (state counts, canary results), which quote the timeline and reports directly;
  - the contents of the `.tla` files of v1's evidence E1 to E6;
  - for v2's evidence, only the instantiation of E1 was spot-checked (`evidence/E1/EE1.tla:4-7`).
