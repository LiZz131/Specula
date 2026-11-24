# Scenario census brief (shared by all census sub-agents)

You are one of six agents. Each takes one arm (v0, v1 or v2) and 3-4 cases of a set of 21 TLA+ modeling
runs made by an LLM agent ("the agent") that evolved a TLA+ model for a code update. Your job: for each of
your runs, list the scenarios THE AGENT ITSELF declared it wanted covered, and measure whether the configs
(cfgs) it ran actually reach them.

## Paths
- Run: `R=/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/results/<arm>/<case>/r1/`
  - `R/output/modeling-brief.md` (look for the "Update Scenarios" section, U1..Un or similar),
    `R/output/analysis-report.md`, `R/output/spec/bug-report.md` or `R/output/bug-report.md`, `changelog.md`,
    `R/output/spec/` (Update.tla, MC.tla, *.cfg, TLC logs under spec/output/ or output/ or similar),
    `R/timeline.md` (agent messages per turn, `**[N]**` marks turn N), and for v1/v2 `R/invariant-evidence.json`.
- Census dir (your outputs go here): `C=/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/analysis/epoch-1/scenario-census/`
- Runner (already written, read its docstring first): `C/run_census.py`. It reuses
  `/users/bingzhuo/Specula/research/ci-evolution/update-coverage/check.py`'s `run_config` machinery: an
  ACTION_CONSTRAINT records the first state where each probe holds; for a state predicate P, ENABLED P = P.
  INVARIANT/PROPERTY sections of the cfg are dropped for the probe run (nothing stops the run).
  Default 120 s simulation at depth 100, seed 1, then a 240 s retry with seed 2 for cfgs where some probe
  was not reached. Scratch copies go to `/mydata/bingzhuo/evidence-work/census/<arm>/<case>/` and are deleted.

## HARD RULES
1. Anti-hindsight: do NOT open
   the private notes directory, nor `.../analysis/epoch-1/evidence/`, `.../analysis/epoch-1/coverage/`,
   nor any `case-*.md`, evidence cards, or the epoch-1 summary. Do not open other arms' results for your cases (you only
   see your own arm). Write predicates STRICTLY from the agent's own wording in your run.
2. Gold is sealed: do not look for or read any Gold, grading, judge or answer-key material.
3. Do not modify `results/`, `inputs/`, notes, or any Specula code (including run_census.py and check.py).
   Only write under `C/probes/<arm>/<case>/`, `C/runs/<arm>/<case>/` (the runner writes this),
   `C/items/` and `/mydata/bingzhuo/evidence-work/census/`. Do not commit.
4. TLC concurrency: you get the number of TLC jobs stated in your task (pass `--jobs N` to run_census.py,
   and run at most one run_census.py at a time). -Xmx3g each (runner default). Never run TLC outside the
   runner except quick SANY parse checks (`java -cp /mydata/bingzhuo/src/Specula/lib/tla2tools.jar tla2sany.SANY`
   in a scratch copy under /mydata/bingzhuo/evidence-work/census/). Delete any states/ dirs and *_TTrace_*
   files you create.
5. Probe modules add NO actions and must not change the spec. Only state predicates (you may use
   definitions of the arm's modules, and history/ghost variables the arm already has).

## Method per run
1. Inventory declared items (expect ~5-15). "Declared" means, in the agent's own words:
   (a) each Update Scenario in modeling-brief.md (kind `update_scenario`);
   (b) each new or modified property's stated intent where the intent names situations, e.g. "learners
       and removed nodes never start an election" (kind `property_intent`; sources: Update.tla comments,
       brief, invariant-evidence.json, analysis-report);
   (c) explicit statements in analysis-report / bug-report / timeline that a situation needs to be checked or
       is covered by some cfg (kind `check_statement`).
   Record a verbatim quote (short, <= 300 chars) and source as `file:line` (path relative to `R`) or
   `timeline.md:[turn]`. One item per distinct situation; a scenario naming two distinct situations (e.g. "a
   learner ... The same happens to a voter demoted to learner by a membership change ...") becomes two items
   (U2a, U2b).
   Dismissals ("X is safe because ...", "X cannot happen because ...", "excluded: ...") are NOT items; list
   them separately (quote + source) in the dismissals file. Exclusions of whole topics count as dismissals.
   If a run has too many items, prioritize (a) and (b) tied to the update and write what you skipped in
   the run's notes file.
2. For each item, find the related check(s): the property the agent names for it, or else the update's
   safety invariants. Find the cfgs that enable that property (grep INVARIANT/PROPERTY sections). Find
   whether the agent had a precondition canary (often `Canary*`, `*NotReached`, `NotReach*`, `*Witness`,
   `*Reachable`) or a hunt cfg for it, and whether its own logs show the canary was reached (a canary
   "violation" means reached). Cite the log file and line.
   A canary reached only in a canary-only cfg counts for the property cfgs ONLY if that canary cfg has
   the same behaviour-defining sections (CONSTANTS values, SPECIFICATION/INIT/NEXT, CONSTRAINT,
   ACTION_CONSTRAINT, model-value/`<-` substitutions) as a cfg that enables the related property; say so.
   Also check the canary predicate actually matches the item's wording; if it is weaker/different, treat
   the item as having no canary for that aspect.
3. For items with no valid canary in a property-enabling cfg: write a precondition predicate
   `SC_<item>` strictly from the agent's wording in `C/probes/<arm>/<case>/CensusProbes.tla`
   (`---- MODULE CensusProbes ----` / `EXTENDS <the module that defines what you need, e.g. Update or MC>`).
   Above each predicate put a comment with the quote and source it encodes. Then write
   `C/probes/<arm>/<case>/plan.json`: `{"configs": [{"name": "<cfg>", "extends": "<module the cfg runs on,
   e.g. Update or MC>", "probes": ["SC_..."]}]}` listing the cfgs that enable the related property (and
   only those; skip canary-only, trace, base/old-model cfgs). The probe module generated by the runner is
   `EXTENDS <extends>, CensusProbes, TLC`, so CensusProbes must extend a module in the closure of every
   cfg's `extends` (usually the lowest common module, e.g. MC). Check a cfg's needed module the way the
   agent ran it (its run scripts / logs show `tlc ... Update` etc.). Parse-check first with SANY on a scratch
   copy. Then: `cd C && python3 run_census.py <arm> <case> --jobs N` (use `--only NAME.cfg` to rerun one cfg;
   it merges into result.json). A positive control is wise: include one probe you expect to be reached
   (e.g. the agent's own reached canary condition negated) so a dead run is not mistaken for "not reached".
4. For "not reached": look for a structural reason (a constant, a guard, a counter limit in that cfg) and
   cite it (file:line and the constant value). Without a structural reason or exhaustive BFS, write
   "not seen in budget", never "unreachable".
5. Classify each item:
   - `covered`: reached in a cfg that runs the related check;
   - `Q-a` (declared-uncovered): not reached in any cfg that runs the related check (structural or not seen
     in budget; say which in `evidence`);
   - `covered-not-with-check`: reached only in cfgs that do not run the related property;
   - `unclear`: wording too vague to encode, item not MC-checkable (e.g. purely trace/code-review item;
     say so), or runs errored.

## Output files (English)
- `C/items/<arm>-<case>.csv` with header exactly:
  `arm,case,item_id,kind,quote,source,related_check,agent_canary_or_cfg,agent_log_reached,census_probe,census_cfgs,census_reached,evidence,class,note`
  (RFC4180 CSV, quote fields with commas; write it with python's csv module.)
  - `agent_log_reached`: yes / no / not-run / n/a, with nothing else.
  - `census_reached`: e.g. `MC.cfg:yes; Update_full.cfg:no(not seen 360s)` or `n/a`.
  - `evidence`: log file:line citations and/or structural reason (constant=value at cfg:line).
- `C/items/<arm>-<case>.dismissals.csv`: `arm,case,quote,source,topic`.
- `C/items/<arm>-<case>.notes.md`: <= 40 lines: cfgs examined, what you skipped and why, caveats, anything
  inferred rather than measured.
- Keep logs trimmed (the runner trims). Total size of your outputs should stay well under 300 KB per run.

## Final report to your caller
Per run: counts of covered / Q-a / covered-not-with-check / unclear and dismissals; each Q-a item with its
quote, source, and the structural reason or "not seen in budget"; any runner errors; anything inferred.
