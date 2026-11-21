> Translated from the Chinese analysis of 2026-11-21; the rubric is [rubric.md](rubric.md).

# case-011: Invariant evolution quality and miss attribution (OpenRaft · Pre-Vote and membership change)

> Rubric: [rubric](rubric.md) (epoch-1, single run r1). The Gold is sealed; no Gold or scoring material was read.
> Path abbreviations (repository paths are relative to `research/ci-evolution/inv-e2e/`; `WORK` is the experiment's work directory, archived outside git, see `../../README.md`, section Storage): `R=research/ci-evolution`, `E=` the directory `research/ci-evolution/inv-e2e/` itself; `res/<arm>=results/<arm>/case-011/r1`, `spec/<arm>=res/<arm>/output/spec`; old model `old=../blind-incremental-bugs/blind-incremental-v0/case-011/.specula-output/spec`; source `src=WORK/subjects/case-011/buggy-tree/openraft/src`.
> `[N]` is a turn of `res/<arm>/timeline.md`; `L<n>` is a line number of `WORK/attempts/<arm>/case-011/r1/log/activity.jsonl`. The thinking in all three logs is empty, so why the agent decided something can only be inferred from the artifacts it wrote. Every inference is marked as such below.

## 1. Conclusion

**Evolution quality.** None of the three arms weakened, deleted, or removed from the cfg any original property. All three also fixed, independently, the same defect in the old model: `LogLE`/`NoLog` treated two empty logs as unequal, so every leader-related property in the old 3-voter `MC.cfg` was vacuous. The arms do not differ on "whether to weaken". They differ in the following points:

- **v1** has the most complete review of the affected properties. It is the only arm that admits helper-drift on `DurableLogNotAhead` and registers evidence for it, although the keep evidence is taken from the initial state and is weak. It made no model-narrowing in the whole run.
- **v2** has the richest evidence, but three gaps:
  - Under-reaction to helper-drift: it lists `DurableLogNotAhead` as an "unaffected control".
  - For 3 preserved properties with watch touched, the `verified:` line is still `base`.
  - It made one reactive model-narrowing: when the timer starts a new round, the node's earlier Pre-Vote traffic is dropped. This narrowing is on `StalePreVoteResponseIgnored`, the property it is itself reporting a bug on, and it rests only on a source-timing argument. When I checked, the argument still leaves a window.
- **v0** has no evidence obligation, so none of its keep-affected properties has a recorded review. But it added a voter-gating property already in the generation stage, which is why it caught C.

**Root cause of the misses (one sentence).** The mechanisms of B and C can be represented in all three models; the miss happens at the step "add a property or not": the agent replaced a property check with an unverified prose argument. The argument for B is "a grant from the previous round is as stale as a late grant in the current round", written by both v0 and v1. The argument for C is "covered by MC-1/MC-2", written by v2; v1 only mentions it in a model comment. v0 and v1 also kept the old model's `grants ∪ {source}` abstraction, so the `grant_by` panic is invisible in the model.

## 2. Update summary

- An optional Pre-Vote phase is added: `Engine.pre_candidate`, `pre_elect` (`src/engine/engine_impl.rs:297-322`), `handle_pre_vote_req` (:414-447) and `handle_pre_vote_resp` (:516-554; once a quorum is reached it calls `self.elect()` **directly**).
- Runtime side:
  - `handle_tick_election` goes through `pre_elect` when `enable_pre_vote` is on and there is more than one voter, and rate-limits by `pre_candidate.starting_time + election_timeout` (`src/core/raft_core.rs:2010-2035`);
  - `ExternalCommand::Elect{pre_vote}` checks only `is_voter` (:1683-1696);
  - responses are correlated by `does_pre_candidate_vote_match`, which compares only the id of the probed leader (:2066-2090). The comment on that function says "previous round … should be ignored".
- `do_elect` and `become_following` clear `pre_candidate` (engine_impl.rs:264, vote_handler/mod.rs:244); `establish_leader`/`become_leader` do not.
- The implementation of `Candidate::grant_by` is unchanged and is still `expect("target not in quorum set")` (`src/proposer/candidate.rs:106-107`). The new caller is `handle_pre_vote_resp`.
- Affected model elements: the election action (split into do_elect plus a caller guard), the new Pre-Vote state and messages, all become_following paths, `TypeOK`. No formula of an old property needs to change. The impl-abstraction properties `VoteRequestAfterDurable` and `DurableVoteNotAhead` describe the SaveVote→SendVote order, which is unchanged.

## 3. Event table

**keep-unaffected (count only):** all three arms have 3: `DurableVoteNotAhead`, `CertifiedLeaderHasFrozenQuorum`, `MembershipAtMostOneOutstanding`. v2 also registered keep entries for the first two, which counts as extra work.

**Count of new properties (add); canaries are not counted as quality events:**

| arm | non-canary properties | canary |
|---|---|---|
| v0 | 6 (U1–U4, `PreCandidateProbesNextSelfTerm`, the diagnostic `PreVoteRoundNotInheritedByLeader`), plus `DischargeMembership` | 5 (`spec/v0/Update.tla:153-220`) |
| v1 | 5, plus `DischargeContext` | 8 (`spec/v1/Update.tla`) |
| v2 | 6, plus `DischargeContext` | 8 (`spec/v2/UpdateProps.tla:152-166`) + 3 diagnostic (`DebugU4.tla`) |

| arm | property | event | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 | Q7 | source and notes |
|---|---|---|---|---|---|---|---|---|---|---|
| v0 | TypeOK / MCTypeOK / TraceTypeOK | representation | needed | correct | ok | ok | weak | proactive | none | Accepts the new variables and the new message kinds (`spec/v0/base.tla:844-886`). Only one line of explanation in changelog:12, no separating state |
| v0 | DurableLogNotAhead | representation (the value encoding of `NoLog(i)` changed; the formula and helper text did not) | missed (no recorded review) | correct | ok | ok | missing | reactive | none | `base.tla:51-57`; changelog:25-26 only explains what the fix means for the vote checks. The property compares `durableLastLog[i]` and `lastLog[i]` of the same node, both sides change encoding together, so the verdict is unchanged (inference: no cross-node empty-log value occurs in reachable states) |
| v0 | VoteRequestAfterDurable, GrantedResponseAfterDurable, NoForgedMessageEndpoints | keep-affected | needed | correct | ok | ok | missing | unclear | none | The new message kinds PreVoteReq/PreVoteResp are excluded by the `m.kind` quantifier, which agrees with "persists nothing" in `pre_vote.md:40-44`. v0 wrote no review record |
| v0 | LeaderRoleHasCommittedSelfVote, CandidateRoleHasPendingSelfVote | keep-affected | needed | correct | ok | ok | missing | unclear | none | The new `elect()` caller can run on a Leader (A). After A the role becomes Candidate while the Leader object is still there; these two role-based properties cannot catch A, so a new property is needed |
| v0 | (old `HandleVoteResponse`) install lease when winning an election | model-narrowing (fixes a defect of the old model) | needed | n/a | ok | — | valid | reactive | none | Exposed by trace `stale_pre_vote_after_establish` (changelog:20). Effect: a new leader refuses votes while its lease is valid |
| v0 | (empty-log encoding fix) | model fix, removes vacuity | needed | n/a | ok | ok | valid | reactive | **enabled** | changelog:25-26. Before the fix no election could complete with 3 voters; only after the fix does the U1 counterexample exist (timeline [184]) |
| v0 | PreVoteNeverDemotesEstablishedLeader (U1) | add (scope excludes "round started by an operator on a leader") | needed | correct (excluded part is weak) | ok | ok (canary) | weak (the exclusion rests on the TODO at `raft_core.rs:1685`, i.e. impl-as-req) | proactive | enabled (A) | `spec/v0/Update.tla:144-155`, written at [104]. The excluded part is covered by U3 |
| v0 | PreVoteElectOnlyByVoter (U3) | add | needed | unclear (it rests on "all other elect callers check is_voter", i.e. consistency among similar callers, with no documented source) | ok | ok | weak | proactive | **enabled (C)** | `Update.tla:165-169`, written at [104]. Violated from [261]; still violated when fixcheck fixes only MC-1 (bug-report.md:157) |
| v0 | (missing) round-correlation property | add-missed | **missed** | — | — | — | — | — | masked (B) | The mechanism is already in the model (`base.tla:594-597`: `match` compares only term/node, `ng == preGrants ∪ {m.source}`), but `modeling-brief.md:128-131` says "same staleness as a delayed response … not reported". See §5 |
| v1 | TypeOK / MCTypeOK / TraceTypeOK | representation | needed | correct | ok | ok | valid | proactive | none | E1 (mc separating state) and E1c (Bogus negative control), `invariant-evidence.json` |
| v1 | DurableLogNotAhead | helper-drift (`LogLE` fix) | needed | correct | ok | ok | weak | reactive | none | Registered as affected (E12, E13). E12 uses the initial state, where old and new verdicts are both TRUE, so it does not separate; E13 only witnesses the change of the helper itself on cross-node empty logs. The conclusion is right, but the argument "same-node comparison, verdict unchanged" is not written down |
| v1 | VoteRequestAfterDurable / GrantedResponseAfterDurable / CandidateRole / LeaderRole / NoForged | keep-affected | needed | correct | ok | ok | valid | proactive | none | E2–E6, all mc states; both the old and the new property are evaluated by TLC |
| v1 | (old `HandleVoteResponse`) lease | model-narrowing (fixes a defect of the old model) | needed | n/a | ok | — | valid | reactive | none | changelog:29-31, trace `candidate_pre_vote_then_leader` |
| v1 | (`LogLE` fix) | model fix, removes vacuity | needed | n/a | ok | ok | valid | reactive | **enabled** | changelog:36-40. Before the fix the hunt shows "no pre-vote grant at all" |
| v1 | PreVoteNeverDemotesLeader + NoStalePreCandidateAtLeader | add (excludes `preStartRole = Leader`) | needed | correct (excluded part is weak) | ok | ok | weak (the exclusion rests on the same TODO :1685) | proactive | enabled (A) | `spec/v1/Update.tla:199-225` |
| v1 | (missing) voter-gating property | add-missed | **missed** | — | — | — | — | — | masked (C) | The mechanism is already in the model (`spec/v1/base.tla:272-275,283`; the comment says "only the pre-vote quorum caller … has no voter check"), but there is no property and the report does not mention it. See §5 |
| v1 | (missing) round-correlation property | add-missed | **missed** | — | — | — | — | — | masked (B) | `output/analysis-report.md:290-297` says "Reviewed and dismissed (code review)". See §5 |
| v2 | TypeOK | representation | needed | correct | ok | ok | valid | proactive | none | E-TypeOK-sep comes from a trace state, E-TypeOK-ctl is a negative control; the REQ-EVIDENCE block was updated (`spec/v2/base.tla:890-896`) |
| v2 | DurableLogNotAhead | helper-drift (`LogEq`/`LogLE`) | **missed** | correct | ok | ok | missing | — | none | Listed in `unaffected_controls_kept_enabled` at `invariant-evidence.json:8-11`; the block still has `verified: base` (base.tla:980). changelog:46-51 only states what the fix means for the vote checks. The verdict happens to be unchanged (same reason as v0), so there was no consequence |
| v2 | VoteRequestAfterDurable / GrantedResponseAfterDurable / CandidateRoleHasPendingSelfVote | keep-affected (watch_touched=true) | needed | correct | ok | ok | valid | proactive | none | The keep evidence is all trace states, evaluated by TLC. But the REQ-EVIDENCE blocks still say `verified: base` (base.tla:995, 1013, 1046) and were not refreshed as overlay §3 requires. This is weak ledger upkeep (minor) |
| v2 | LeaderRoleHasCommittedSelfVote | keep-affected | needed | correct | ok | ok | valid | proactive | none | E-LeaderRole-keep and E-U2-sep |
| v2 | CertifiedLeaderHasFrozenQuorum | keep (reviewed per ledger rule 3) | not-needed | correct | ok | ok | valid | proactive | none | The evidence entry says "a Pre-Vote quorum is not leadership certification". The frozen annotation marks the frozen-config clause as impl-abstraction and records "use the latest configuration" from raft-essentials.md:103 (`inputs/case-011/annotated/spec/base.tla:724`, review-decisions.md:15). This hint is directly relevant to C; v2 did not use it |
| v2 | **drop this node's earlier Pre-Vote traffic when the timer starts a new round** | **model-narrowing** | unclear | n/a | ok (applies to `byTimer` only) | ok (the counterexample and canary on the operator path are still reachable) | **weak** | **reactive** | unclear | `spec/v2/base.tla:359-361,390-397`; changelog:52-57. The first `Update-full` counterexample appears at [235] (L1477), a timer→timer two-round run; [269] read `raft_core.rs:1385-1405`; the change landed only at [300] (L1880), with no prose reasoning in between. See §4.3 |
| v2 | (MC.cfg) `MaxPreVoteCount = 1` | cfg scope (not a narrowing relative to the old model) | — | — | — | — | — | proactive | none | `spec/v2/MC.cfg:13`, changelog:78-80. In the standard run the old properties are checked under a single Pre-Vote round only; multi-round interactions are checked only in the Update cfg (=2/3). v1's MC.cfg uses 2 |
| v2 | (old `HandleVoteResponse`) lease | model-narrowing (fixes a defect of the old model) | needed | n/a | ok | — | valid | reactive | none | changelog:34-36, trace `prevote_stale_round_after_leadership` |
| v2 | (`LogLE` fix) | model fix, removes vacuity | needed | n/a | ok | ok | valid | reactive | **enabled** | Fixed at [224]; two update properties were violated soon after at [228] |
| v2 | TimerPreVoteElectsOnlyNonLeader | add (covers only timer-started rounds) | needed | correct (excluded part is weak) | ok | ok | valid (doc, comment, contract) | proactive | enabled (A) | `UpdateProps.tla:57-73`; line 69 explicitly excludes operator rounds |
| v2 | StalePreVoteResponseIgnored + PreVoteResponseNeverPanics | add | needed | correct (based on the code's own comment :2066 and the `expect` contract) | ok (`round` is only a history variable) | ok | valid | proactive | **enabled (B)** | `UpdateProps.tla:75-101`; base.tla:637,646 model the panic branch explicitly |
| v2 | (missing) voter-gating property | add-missed | **missed** | — | — | — | — | — | masked (C) | `modeling-brief.md:370-372` claims "reachable only on own-vote nodes, i.e. through MC-1/MC-2"; this coverage argument does not hold (see §5.2) |

## 4. Per-arm summary

### 4.1 v0
- **Good practice:**
  - In the generation stage ([104]) it wrote "the new `elect()` caller lacks the is_voter check" as property U3. It is the only arm of the three that did a "same-kind caller guard comparison".
  - With two model copies, fixcheck and fixcheck2, it showed that the root causes of MC-2 and MC-1 are independent (bug-report.md:155-157).
  - When fixing `NoLog` it wrote down that "the leader-related properties in the old MC.cfg were vacuous" (changelog:25-26).
- **Problems:** none of the keep-affected properties has a recorded review. B was already identified in the brief but dismissed with the single phrase "same staleness".
- **Under-reaction:** the value encoding that `DurableLogNotAhead` depends on changed, but there is no review record (no consequence). No property was added for round correlation.

### 4.2 v1
- **Good practice:**
  - It is the only arm that lists `DurableLogNotAhead` as affected and registers E12/E13.
  - All evidence for keep-affected properties comes from mc reachable states and is evaluated by TLC.
  - No model-narrowing at all.
- **Problems:**
  - E12 is the initial state and has no separating power.
  - The dismissal argument for B uses the implementation's rate limit, but v1's own model abstracts the rate limit as nondeterminism (analysis-report.md:310 Exclusions). The constraint the argument relies on does not exist in the model, and no property checks the argument.
  - A only reaches DEFERRED (`spec/v1/final-result.json:15`); no end-to-end RaftCore reproduction was run.
- **Under-reaction:** a model comment already says the Pre-Vote path has no voter check (base.tla:275), but no property was added and nothing was reported.

### 4.3 v2
- **Good practice:**
  - Every new property has a REQ-EVIDENCE source. The two B properties take the code comment (:2066) and the `expect` contract (candidate.rs:107) directly as the requirement, without substituting its own argument.
  - `HandlePreVoteResponse` explicitly models the panic branch (base.tla:637-650); it is the only arm that does.
  - It has the most trace-sourced evidence.
- **Problem 1: model-narrowing.** When the timer starts a new round, this node's earlier Pre-Vote traffic is dropped. v2's justification: every RPC is within `timeout(election_timeout_min)`, and the timer restarts a round only after at least `election_timeout ≥ election_timeout_min`. My check on `src`:
  - The argument mostly holds. Tick and PreVoteResponse go through the same `tx_notification` channel, which is FIFO (`core/tick.rs:110`). The rate limit counts from `starting_time` (the `C::now()` when the pre_candidate was created). When there is no pre_candidate, the vote's `is_expired(now, election_timeout)` constrains it.
  - **But it is not strict.**
    - Each RPC's timeout starts counting inside the spawned task, and before the spawn `new_client(...).await` runs for each target in turn (`raft_core.rs:1386-1405,1420-1426`). So the deadline is `starting_time + ε + ttl`, not `starting_time + ttl`.
    - `election_timeout` comes from `random_range(min..max)` and can equal min exactly (`config/config.rs:579-580`).
    - So when `election_timeout − election_timeout_min < ε`, a grant of the old round can still count in the new round.
  - **Impact:** B itself is not missed: after switching to the operator path at [303] it is violated all the same, and from [305] the run moves to end-to-end reproduction. But the timer-path variant of B (the most common path under the production setting `enable_pre_vote = Some(true)`) is eliminated in the model. As a result brief:368 says "Timer-only rounds are protected by the RPC timeout". This sentence is a product of the narrowing and has no support from code observation.
  - **Comparison:** the precondition v1 wrote for A already admits that the timing window on the timer path depends on "latency exceeding `election_timeout − election_timeout_min`" (bug-report.md:83-88). v2's argument ignores the same kind of window.
- **Problem 2: under-reaction to helper-drift.** The `LogLE` that `DurableLogNotAhead` reads changed, but the property is listed as "unaffected" (invariant-evidence.json:8-11), which violates divergence-evidence §1. No consequence.
- **Problem 3: ledger not refreshed.** The `verified:` lines of the 3 preserved properties with watch_touched=true were not refreshed (base.tla:995, 1013, 1046).
- **Under-reaction:** the frozen annotation already marks frozen-config as impl-abstraction and records "use the latest configuration". When v2 discussed pre_candidate under rule 3 it concluded only "not a leadership certification". It did not ask "when the quorum is reached, is voter identity still checked against the latest configuration?", which is exactly C.

## 5. Miss attribution

### 5.1 B (responses correlated only by probe; `grant_by` panics after a membership change): missed by v0, v1

| Question | v0 | v1 |
|---|---|---|
| 1. Where the wrong abstraction comes from | The correlation mechanism is modeled faithfully; there is no wrong abstraction there: `base.tla:594-597` compares only term/node, as does `raft_core.rs:2081`, and both models can produce cross-round counting (MaxElectionCount=2, shared with pre-elect). The wrong abstraction is in the "grant count": `ng == preGrants ∪ {m.source}`, **copied from the old model** `old/base.tla:325` (`grants ∪ {m.source}`). A grant from a non-member is silently absorbed when `IsQuorum` takes the intersection, so the panic is invisible | Same as v0: `spec/v1/base.tla:644` copies `∪ {m.source}`. With MaxPreVoteCount=2 and membership=2 in the Update cfg, cross-round states are reachable but invisible |
| 2. At which step it was settled | 04 Update model ([104] writes Update.tla, no round property). The reason was added to the brief at [238]: "Pre-Vote responses are correlated by leader id only, so grants from an earlier round at the same term count in a restarted round … Both rounds probe the identical vote; this is the same staleness as a delayed response within one round and is not reported." (`res/v0/output/modeling-brief.md:128-131`) | 04 ([104]). The reason was written into analysis-report U.5 at [181]: "Reviewed and dismissed (code review) … tick restarts are at least `election_timeout >= election_timeout_min =` RPC timeout apart, so a stale grant is no staler than a delayed in-round grant. Not modelled as a separate property; no finding." (`res/v1/output/analysis-report.md:290-297`) |
| 3. Information gap | [79] (L619-620) read `candidate.rs`, and the returned content contains `expect("target not in quorum set")`. The code was read, but it was not connected to "membership change between two rounds → different frozen configuration" | **Never saw the `expect` line.** The `git diff` at [26] shows only the `starting_time` hunk, and [110] grepped only `fn granters`. The phrase "target not in quorum set" appears nowhere in the tool returns of the whole log. [48] read the RPC timeout code `raft_core.rs:1376-1410`, which is where the rate-limit argument comes from |
| 4. Why the mechanism that should have caught it did not | The trace scenarios are engine-level single rounds only; there is no "two rounds plus membership change". No canary shows that "cross-round grants are counted" is reachable. The completeness review recorded it only as a code-review note. The dismissal ignores two points: operator rounds are not rate-limited (v0 itself distinguishes operator rounds in U1); and the configuration may change between the two rounds | Same as v0. One more self-contradiction: v1's Exclusions abstract the rate limit away (analysis-report.md:310), yet the dismissal depends on the rate limit; and when writing the precondition for A it admits the manual trigger path "has no timing constraint" (bug-report.md:83-88) |
| 5. Comparison arm v2 | v2 read the `expect` of `grant_by` at [88] (L628-630). When writing base at [97] it already gave `HandlePreVoteResponse` a `member` test and a crash branch (base.tla:637,646); at [112]/[123] it took the comment at :2066 as the requirement and wrote `StalePreVoteResponseIgnored`, and took the `expect` as the contract and wrote `PreVoteResponseNeverPanics` (UpdateProps.tla:75-101). The difference is in two places: **it uses the comment and the contract as requirements instead of arguing equivalence itself**; and **it does not copy the old grant abstraction**. Whether this comes from the overlay: REQ-EVIDENCE requires each new property to cite a comment/contract source, which matches what v2 did; the `CertifiedLeaderHasFrozenQuorum` watch column in the frozen annotation lists `Candidate::grant_by` (annotated base.tla:721), which may have led it to `grant_by`. But the thinking is empty, so the causation **cannot be confirmed**; the most that can be said is "possibly the overlay, plus a different exploration path" | Same as left |
| 6. Classification | **equivalence-claim** (an unverified "same staleness"), **anchoring** (copied `∪ {source}`, the panic is invisible), property-gap (the correlation mechanism is faithful, but there is no property) | **equivalence-claim**, **unread-code** (never read the `expect`), anchoring, property-gap |

**Minimal interception point (B):** at 05 completeness review.
- **What to check:** every "reviewed and dismissed / not reported" code-review conclusion in the update report.
- **Required artifacts:**
  - a TLC property (with a history variable if necessary), or a canary plus one TLC run, that tests the dismissal argument;
  - a table "new call site → `expect`/`unwrap`/`assert` in the callee (including indirect callees)", where every row has a crash branch or a precondition property in the model.

  Missing either one means the review cannot be closed. v2 happens to have both.

### 5.2 C (the Pre-Vote-triggered `elect()` does not recheck voter): missed by v1, v2 (v2 mentions it only in the fix suggestion)

| Question | v1 | v2 |
|---|---|---|
| 1. Where the wrong abstraction comes from | There is no wrong abstraction. The old `StartElection` has its own `InConfig` guard (`old/base.tla:187`). v1 moves the guard to the caller (`ElectGuard`); for a non-member `DoElect` gives term+1, role=Learner, candidateActive=FALSE (`spec/v1/base.tla:272-292`), which faithfully reflects that `elect()` does not check voter. **The mechanism is represented** | Equally faithful: in `ElectEffects`, `leading == InConfig(...)` (`spec/v2/base.tla:298-321`); `StartElection` has the guard and the Pre-Vote quorum branch does not (:324-326 versus :663) |
| 2. At which step it was settled | 02/04 ([94] writes base). The comment reads: "the guarded tick/external callers always satisfy InConfig, only the pre-vote quorum caller (engine_impl.rs:535-539) has no voter check." No property follows, and no report mentions it | 04 and U.6: the brief says "Code-review note (no separate finding): a Pre-Vote quorum also bypasses `enable_elect` and the voter check … reachable only on own-vote (candidate/leader) nodes, i.e. through MC-1/MC-2." (`res/v2/output/modeling-brief.md:370-372`). bug-report.md:42,57 also mention it only in passing, in the root cause and fix suggestion of MC-1 |
| 3. Information gap | All the relevant code was read: `raft_core.rs:1683-1697` (comment at base.tla:374), `engine_impl.rs:535-539`. No gap | All read (brief:255-256,281-287). It also had the hint from the frozen annotation (frozen-config is impl-abstraction, with "use the latest configuration" recorded) |
| 4. Why the mechanism that should have caught it did not | The A property excludes "rounds started by an operator on a Leader" (`Update.tla:211-216`, based on the TODO :1685). The v0 counterexample for C falls exactly into this excluded region: an operator starts a round on the leader, the leader removes itself from the voters, and a late grant arrives (`res/v0/output/spec/confirmation-MC-2.md` §1). Outside the excluded region there is no voter property, so nothing is left as a backstop | Same as left: `TimerPreVoteElectsOnlyNonLeader` covers only timer-started rounds (UpdateProps.tla:69). The coverage argument does not hold: C has a single round and does not go through the cross-round correlation of MC-2; it is also an operator-started round on a leader, which the MC-1 property explicitly excludes. The v0 fixcheck already showed that C still exists when only MC-1 is fixed (`res/v0/output/spec/bug-report.md:157`) |
| 5. Comparison arm v0 | When generating Update.tla at [104], v0 wrote "every other path to do_elect() checks is_voter … a Pre-Vote-triggered election must likewise only start on a current voter" as U3 (`spec/v0/Update.tla:165-169`) and gave it a dedicated membership hunt (`MC_hunt_prevote_membership.cfg`, single-voter start, membership=2), with an 11-step counterexample. This is v0's own exploration path; there is no overlay | Same as left |
| 6. Classification | **property-gap** (mechanism represented, no property), **reporting-gap** (the comment notes the missing voter check, but it was not reported as a finding); the exclusion region of the A property widens the gap | **property-gap**, **equivalence-claim** ("covered through MC-1/MC-2"), **reporting-gap** (appears only in the fix suggestion and a code-review note) |

**Minimal interception point (C):** at 03 update analysis.
- **What to check:** every case where "a new caller calls an existing state-transition function", here `handle_pre_vote_resp → elect()`.
- **Required artifact:** a caller-guard comparison table that lists the guards of the existing callers (is_voter, server_state≠Leader, enable_elect) and the set difference with the new caller. Each item in the difference must satisfy one of the following:
  - it is written as a step property;
  - a **requirement-based** exclusion reason is written down (an implementation TODO cannot be the basis).

  In addition, any claim "X is covered by MC-k" must be tested by running a model copy with the candidate fix for MC-k applied, to confirm that X also disappears (the v0 fixcheck does exactly this).

### 5.3 A (reported by all three arms)
Not a miss. v1 stops at DEFERRED: it has only an engine trace plus debug-assertion observations and did not run Part 4 (`spec/v1/final-result.json:15`).

## 6. Corrections to the mechanical table (`analysis/out/prop_events-case-011.md`)

1. **"New checked properties" systematically omits action properties.**
   - Cause: the regex in `check_annotation.properties()`, `\b(INVARIANTS?|PROPERT(?:Y|IES))\b((?:\s+[A-Za-z_]\w*)+)`, swallows the `PROPERTIES` keyword that directly follows an INVARIANTS list as an identifier, then breaks at the keyword, so the whole following PROPERTIES list is lost. Measured: the parse result of `spec/v0/Update-full.cfg` contains no U1–U4 (`check_annotation.py:58-62`).
   - Consequences:
     - v0 actually added four action properties U1–U4, 4 action canaries and `DischargeMembership`; the table lists only 3 properties;
     - v1 is missing `PreVoteElectsProbedVote`, `PreVoteRequestPure`, `PreVoteNeverDemotesLeader` (the one MC-1 violates) and `DischargeContext`;
     - v2 is missing `TimerPreVoteElectsOnlyNonLeader`, `StalePreVoteResponseIgnored`, `PreVoteResponseNeverPanics`, `PreVoteProbeMatchesElection`, `PreVoteRoundPersistsNothing` and `DischargeContext`.
   - Properties that appear only in canary cfgs with PROPERTIES only (such as v1's `CanaryNoPreVoteElection` and v2's `CanaryNoPreVoteElect`) are not affected.
   - This bug affects the "new property" statistics of **all cases**, and the counts of any cfg where an action property comes after INVARIANTS.
2. **v0's `DurableLogNotAhead` is recorded as "same", a false negative.** v0 changed the value encoding of `NoLog`, not `LogLE`. The script compares only the operator text in the definition closure and cannot see a change in the state value representation. The substantive verdict is unchanged (§3).
3. **v2's `CanaryNoCrash` comes from the diagnostic module `DebugU4.tla`** (through `canary-U4c.cfg`). It is not a formal update property and should be excluded from the statistics.
4. **The other rows agree with the measurements:** the definitions of the 12 original properties are all same/changed (TypeOK, MCTypeOK are representation); none is deleted and none is dropped. v1's `cfg 4→4` (DurableLogNotAhead, MembershipAtMostOneOutstanding) means these two did not enter the Update cfg; they are not unchecked: the four cfgs base/MC/MC-membership/Trace still check them, as in the old model.

**Verification and corrections of the earlier analysis (the earlier per-case notes, not in this repository):**
- ✅ A is reported by all three arms, v1 as DEFERRED. ✅ B only by v2, C only by v0. ✅ v2's 3 `verified: base` lines (base.tla:995/1013/1046). ✅ v2 lists `DurableLogNotAhead` as unaffected. ✅ The behavior described by the two impl-abstraction properties is not changed by the update: vote_handler changes only `become_following`, and `log_id/mod.rs` is unchanged.
- ❌ In the §4 table, the reason given for v0 missing B is "the model does not distinguish rounds". This is inaccurate. v0's model, like the implementation, does not distinguish rounds, and cross-round counting is itself reachable. What is missing is the property and the panic branch of `grant_by`, and v0 **explicitly identified B and dismissed it** at brief:128-131.
- ❌ The source given for v1 missing B is "the changelog says response correlation is covered only by code reading and test t12". The source is wrong. The dismissal is written at `analysis-report.md:290-297`; t12 (:303) is about Unreachable not counting as a grant and has nothing to do with response correlation; v1's changelog has no such text.
- ❌ "This difference comes from modeling granularity, … unrelated to invariant evolution" does not hold. All three models can represent the mechanisms of B and C. The difference lies in which properties were added and in prose dismissals; it is "should have added but did not" (under-reaction) within invariant evolution, only without going through "weakening".
- ⚠️ "v2's timer fix … needs manual checking": checked, see §4.3. The argument mostly holds, but there is an ε window, and the statement "Timer-only rounds are protected" is too strong.
- ➕ Two additions: v2's coverage argument for C does not hold; v2's standard MC.cfg limits Pre-Vote to 1 round.

## 7. Uncertain and unverified points

- **Whether v2's ε window can fire in a real run was not measured.** The only basis is code structure: `new_client().await` runs before the timeout starts counting, and `election_timeout` can equal min. With the default 150–300 ms configuration the probability may be very low.
- **Whether v2's choice to use the comment and the contract as requirements was caused by the overlay cannot be confirmed.** The thinking in all three logs is empty. The `grant_by` in the frozen-annotation watch is only circumstantial.
- **Whether the v1 and v2 models can reach a C state in the cfgs that were run was not verified with TLC.** I only confirmed that the guard structure allows it: an operator-started round on a Leader, a local membership change at the leader, and a quorum branch without InConfig are all present. This pass was read-only and did not run TLC.
- **Whether C is a real defect, and which of A/B/C is the Gold, is unknown.** The Gold is sealed. v0 classifies C as Low (confirmation-MC-2.md).
- **The Q6 of the keep-affected rows of v0 is recorded as unclear.** v0 has no evidence obligation and no record, so it cannot be judged whether it reviewed them on its own initiative.
