# Scenario census: declared but not covered (I-3)

Question: in the 21 epoch-1 runs, which scenarios did the agent itself say it wanted covered, and did
the cfgs it ran actually reach them? If "declared but not covered" (Q-a) is common, a scenario-canary
consistency check (proposal A′) is a cheap rule that needs no prior knowledge. If it is rare, the
effort belongs to Q-b (dismissed in text) and Q-c (never thought of).

## Method

**Declared items.** Only the agent's own words count:
1. each Update Scenario in `modeling-brief.md`;
2. each new or modified property whose stated intent names a situation;
3. explicit statements in the analysis report, bug report or timeline that a situation needs checking
   or is covered by some cfg.

A scenario that names two situations becomes two items. Dismissals ("X is safe because ...",
exclusions, "argued, not modeled") are not items. They are listed separately in `dismissals.csv`, as
input for the next step (Q-b).

**Related check.** The property the agent names for the item. If it names none, the update's safety
invariants. A cfg is *related* when it enables one of these checks.

**Reached?**
1. *Agent evidence.* The agent's own canaries, hunts and counterexamples, cited from its logs.
   - A canary hit counts for a property cfg only if the canary cfg has the same behaviour sections
     (CONSTANTS, SPECIFICATION/INIT/NEXT, CONSTRAINT, ACTION_CONSTRAINT, substitutions). A different
     VIEW was accepted.
   - The canary predicate must match the item's wording.
2. *Census probe.* Otherwise, a state predicate `SC_<item>` is written strictly from the agent's
   wording, in `probes/<arm>/<case>/CensusProbes.tla`.
   - The module EXTENDS the arm's module and adds no actions.
   - `run_census.py` runs it on a copy of the spec, on the related cfgs listed in `plan.json`, with
     their INVARIANT/PROPERTY sections dropped.
   - It reuses `update-coverage/check.py`'s `run_config`: an ACTION_CONSTRAINT records the first state
     where each probe holds (ENABLED P = P for a state predicate).
   - TLC simulation at depth 100, one worker: 120 s with seed 1, then 240 s with seed 2 for cfgs where
     a probe was missed.
   - Every plan has a positive-control probe, so a dead run is not mistaken for "not reached".
3. *Never reached.* A structural reason (constant, guard, counter, with file:line) is required.
   Otherwise the verdict is "not seen in budget", never "unreachable".

**Classes**

| Class | Meaning |
|---|---|
| `covered` | reached in a cfg that runs the related check |
| `Q-a` | not reached in any related cfg |
| `covered-not-with-check` | reached only in cfgs that do not run the related check (e.g. a canary-only cfg with other constants) |
| `unclear` | not MC-checkable by the agent's own design (trace-only or code-review items), or too vague to encode |

**Anti-hindsight rule**
- The six census sub-agents worked one arm at a time and never saw the other arms.
- They were barred from private notes, the evidence directories (`../evidence/`), `../coverage/`, `../case-*.md`
  and the epoch-1 summary with its correction table (`../README.md`), and from all Gold material. Their brief is [census-brief.md](census-brief.md).
- The known-defect correction table (top of `../README.md`) was opened only after every row was classified.
- Caveat: the coordinating agent had read `../coverage/README.md` (I-2) before launch. That README
  names the 004 v2 removed-node gap. The coordinator did not pass this on, and the v2 sub-agent found
  the 004 v2 items on its own.

## Files

| Path | Content |
|---|---|
| [census.csv](census.csv) | every item: arm, case, id, kind, quote, source, related check, agent canary/cfg, agent log reached, census probe, cfgs, per-cfg reach, evidence, class, note |
| [dismissals.csv](dismissals.csv) | dismissals (quote, source, topic) |
| [totals.md](totals.md) | per-run and per-arm counts (`aggregate.py` output) |
| `items/<arm>-<case>.{csv,dismissals.csv,notes.md}` | per-run sources of the two tables, plus notes (cfgs examined, what was skipped, inferences) |
| `probes/<arm>/<case>/{CensusProbes.tla,plan.json}` | probe modules and cfg plans |
| `runs/<arm>/<case>/result.json`, `logs/` | per-cfg passes (seed, seconds, status, traces), probes reached and not reached; slimmed TLC logs |
| `run_census.py`, `aggregate.py`, `slim_logs.py` | runner, table builder, log slimmer |

**How to rerun**
- One run: `python3 run_census.py <arm> <case> --jobs N`. Add `--only X.cfg` to rerun one cfg; the
  result merges into `result.json`.
- Tables: `python3 aggregate.py`.

## Results

215 declared items:

| Kind | Count |
|---|---:|
| Update-scenario items | 174 |
| Property-intent items | 29 |
| Check statements | 12 |

114 dismissals.

| Arm | Items | covered | Q-a | covered-not-with-check | unclear | Dismissals |
|---|---:|---:|---:|---:|---:|---:|
| v0 | 61 | 58 | 2 | 1 | 0 | 29 |
| v1 | 78 | 74 | 1 | 1 | 2 | 41 |
| v2 | 76 | 66 | 7 | 0 | 3 | 44 |
| all | 215 | 198 | 10 | 2 | 5 | 114 |

Per run: [totals.md](totals.md). Q-a is concentrated: 6 of the 10 come from two runs, v2 004 and v2 012.

### Q-a items

| Run | Item | Quote (agent's words) | Source | Why not covered |
|---|---|---|---|---|
| v0 002 | U-LOSS-b | "changed NEWLEADER window -> crash or INITIAL exit -> election by epoch -> TRUNC/missing history at the new leader" (crash branch); the agent's bug report notes it was not reached | `modeling-brief.md:60-61`, `spec/bug-report.md:127` | not seen in budget: agent BFS stopped at depth 38 (target about 52 steps); census missed it |
| v0 010 | U1 | "SNAP-window learner exit (directly changed) ... -> changed LearnerShutdown -> ..." | `modeling-brief.md:207` | not seen in budget in 20 related cfgs (840 s in the two SNAP hunts). The agent's canary is weaker (no non-durable image) and ran in a canary-only cfg. The exact state appears only in the old-semantics control |
| v1 002 | P_PP | "a crashed process has no data tree, so snapshot-prefix-of-applied is required only for live servers" | `invariant-evidence.json` (PipelinePrefix) | not seen in budget in `MC.cfg` and `MC-hunt-sync`; structural in `MC-hunt-mutation` (`MaxCrash=0`) |
| v2 004 | U2b | "The same happens to a voter demoted to learner by a membership change that reaches it before the transfer message" | `modeling-brief.md:229-230` | structural: no MC action demotes a voter to learner (`MC.tla:162-190`); `MembershipLimit<=1` |
| v2 004 | U2c | "a quorum of voter grants makes it `Leader`" | `modeling-brief.md:227-229` | structural: the self grant is processed first and panics (`MC.tla:144`, `base.tla:364`). The agent later wrote "expected NOT reachable" (`Update.tla:148-149`) |
| v2 004 | P_EBVOr | "learners and removed nodes never try to elect themselves" (removed-node half) | `spec/Update.tla:89` | structural: removal needs MCJoint then MCUniform, but `MembershipLimit<=1` in every cfg that enables `ElectionByVoterOnly` |
| v2 010 | U3c | "... or after the new session's processor appended later records" | `modeling-brief.md:215` | structural in the `MaxTxn=1` cfgs; not seen in budget in the `MaxTxn=2` cfgs; no agent witness |
| v2 012 | US3 | "states where the effective membership is covered by the commit index but not promoted" | `modeling-brief.md:183` | not seen in budget. The agent's 30-min BFS stopped with 4.1M states queued; the agent says so (`analysis-report.md:117`) |
| v2 012 | C2a | "RejectAppendConflict / DiscardNegativeAck had no positive coverage at the explored depths" | `spec/bug-report.md:61` | not seen in budget; the agent acknowledges the gap. Its explanation (prev = None on a leader's first append) was not verified |
| v2 012 | C2b | same quote (DiscardNegativeAck) | `spec/bug-report.md:61` | depends on C2a: negative acks are produced only by RejectAppendConflict (`base.tla:568`) |

### Covered-not-with-check items

- **v1 002 P_SCJ**: "a broadcasting follower must also have sent its NEWLEADER ACK".
  - The agent's `CanaryFollowerBroadcast` was violated (reached) only in its canary cfg (`MaxCrash=0`,
    no depth CONSTRAINT).
  - The cfgs that run `SyncCompletionJustified` did not reach it in the census.
  - Probably the same 21-step trace is a behaviour of `MC.cfg`. That is inferred, not run.
- **v0 004 US4a**: "Removed (absent) target runs `elect()` ...".
  - Witnessed only in `Update_canary_AbsentElect_witness.cfg` (`ReplicateLimit=4`), which runs only the
    canary.
  - Structural in the five `MembershipLimit=1` cfgs: node 1 must leave by MCJoint then MCUniform
    (`MC.tla:111-124`).
  - Not seen in `MC_hunt_transfer_membership`, where the agent's same-constants canary BFS also stopped
    without a witness. That cfg does not enable `NoCorePanic` or `ElectOnlyByVoter`.

### Relation to known defects and misses (checked after classification against the correction table in `../README.md`)

| Q-a / not-with-check item | Known defect or miss | Relation |
|---|---|---|
| v2 004 P_EBVOr, U2b | 004 v2: `MembershipLimit<=1` masks the removed-node self-election (evidence card) | **directly related**: these are the declared form of that gap. U2b reaches the same state family by demotion |
| v2 004 U2c | 004 v2 (missing property for leader self-transfer) | same case, different scenario; the agent itself retracted the expectation |
| v0 004 US4a | none for v0 (v0 reported the 004 defects) | same scenario shape as the v2 gap (removed node elects; `MembershipLimit=1`), not tied to a miss |
| v0 010 U1 | 010 v0 miss (SyncRequestProcessor leak; P1, model drains the queue at exit) | **related scenario**: the SNAP-window exit is where the leak lives. Reaching U1 would not have shown the leak, because the model's exit is wrong (P1) |
| v1 002 P_SCJ, P_PP | 002 v1 miss (COMMIT/NEWLEADER NPE) | same case, different situations; not the miss |
| v2 012 US3, C2a, C2b | 012 v2 miss (VecProgress order abstracted away, P1) | same case, different mechanism; not the miss |
| v0 002 U-LOSS-b, v2 010 U3c | none (both arms reported the case's defects) | not related to a known miss |

The other known gaps did not show up as Q-a:

| Known gap | Census verdict | Class |
|---|---|---|
| 011 B v0 `MaxElectionCount<=2`; 011 B/C in v1/v2 | every declared 011 item was covered in all three arms | Q-b/Q-c misses, not Q-a |
| 002 v1 empty-buffer precondition | not declared | Q-c |
| 006 v1/v2 `MaxReadLimit=1` | the declared reuse scenarios were reached in the Update/hunt cfgs that run the read properties; only the standard `MC.cfg` excludes them | not Q-a |
| 004 v1 `TransferTargets` | all v1 004 items covered | not Q-a |

## Reading

1. **Q-a is real but rare.** It is 10 of 215 items (4.7%), plus 2 covered-not-with-check.
   - Of the 7 epoch-1 misses, one is directly a Q-a gap: the 004 v2 removed-node half, which the
     evidence cards call a masked defect, not a miss.
   - One more (010 v0) sits next to a Q-a scenario, but its root cause is the abstraction.
   - Misses in 011, 002 v1 and 012 v2 are not Q-a.
2. **A′ would have flagged real things at low cost.** The 004 v2 items are structural, so an A′ check
   would have reported them deterministically.
   - Four other Q-a items (v0 002 U-LOSS-b, v2 012 US3/C2a/C2b) the agent had already acknowledged as
     uncovered. A′ would turn such admissions into a blocking item.
3. **"Covered" leans on the agent's own deep runs.** Random simulation at depth 100 misses deep
   states. Several items are covered only through an agent BFS counterexample or a hand-built initial
   state:
   - v2 010 U2/U3a/U3b
   - v2 011 U4b
   - v1 002 update items (FocusInit)
   - v1 006 US4 and v0 006 S6b2 (guided hunts)
   - v0 002 U-EPOCH/U-LOSS-a

   An A′ implementation should accept a property cfg's own counterexample or BFS witness as reach
   evidence, and should report "not seen" separately from "structurally excluded".
4. **Agent canaries often cannot be credited.** In 003 (v1, v2), 010 (v0, v2) and 012 v1 the canary
   cfgs run with constants that no property cfg has. The canary then proves reachability in a cfg that
   checks nothing. A′ needs the canary inside, or behaviour-equal to, a cfg that runs the related
   property.

## Limits

- One run per arm and case. Items were inventoried by six LLM sub-agents with one shared brief, so
  granularity differs:
  - v1 011 has 18 items, v0 002 has 6;
  - some sub-agents itemised property intents, others folded them into scenarios.

  Counts are directional.
- Dismissal lists come partly from grep and are not exhaustive.
- Several probes are weaker than the wording, because a state predicate cannot see a step or an
  order. Each is marked in the notes:
  - v0 010 U1b, P3;
  - v2 011 U5a, U6a, U6b, U1b;
  - v2 012 US1a, US2b;
  - v1 010 UPD-1.
- Some probes use ENABLED of an MC action, which ignores steering ACTION_CONSTRAINTs (v0 011 U5b, v0 012
  U4d). These may be over-reported; both items are reached elsewhere.
- "Not seen in budget" is weak evidence. Simulation throughput was 1k–30k traces per cfg, and a few
  `MC.cfg` runs were dead (v1 002, v2 002, v2 006, v0 006 `Update_open`).
- Coordinator completion and corrections:
  - Two sub-agents did not finish: v0 002–006 stalled after writing probes; v2 010–012 ran out of
    context.
  - The coordinating agent ran v0 004/006 and classified v0 003/004/006 and v2 012 from the
    sub-agents' probes. Those rows say so in `note`.
  - It reclassified v1 002 P_SCJ and v0 004 US4a from Q-a to covered-not-with-check, by the class
    definition.
  - `run_census.py --only` had a merge bug (fixed). v1 012 merged its reruns by hand; v0 002's hunt
    cfgs were rerun after the fix.
