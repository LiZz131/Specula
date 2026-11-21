# inv-e2e: end-to-end blind test of invariant-evolution evidence (#188 §3.2)

`../etcd-v0-v3/inv-ablation/` and `../etcd-v0-v3/inv-evidence-ledger/` reran only the invariant judgment step, on the etcd V0–V3 dev set. In the real workflow, property decisions interact with action modeling, trace validation, configs and model checking, so a judgment-only result need not carry over.

This experiment runs the **full incremental CI workflow** on the blind cohort of `../blind-incremental-bugs/` with three skill variants:

| Arm | Skill tree | Prior suite |
|---|---|---|
| v0 | base `incremental-modeling` and shared skills | blind V0 |
| v1 | v0 + `divergence-evidence.md` + 5 hook lines | blind V0 |
| v2 | v1 + `ledger-usage.md` + 2 hook lines | blind V0 with `REQ-EVIDENCE` comments (comments only) |

- **v0 → v1** measures what requiring divergence evidence adds. Every changed or affected property needs a separating state evaluated by TLC, keeping a property also needs evidence, and implementation behavior is not requirement evidence.
- **v1 → v2** measures what the requirement-evidence ledger adds on top of that.

The overlays and hooks are described in `skill-overlays/`.

**Questions.**
- Does each arm find the update-introduced bug?
- What does it cost?
- How does it treat the prior properties: keep, strengthen, weaken or delete them, and with what evidence?

Grading follows the blind protocol (`../blind-incremental-bugs/PROTOCOL.md`) once Gold is unsealed. With at most 10 cases, the results are directional, not statistical.

The etcd V0–V3 experiments served as the dev set: the skill overlays were written there, and were frozen before any blind case ran.

## Pipeline

| Step | Script | Writes |
|---|---|---|
| 1. Subjects | `materialize.py` | `WORK/subjects/<case>/{old-tree,buggy-tree,old-source,new-source,subject.json}`; `WORK/history/<case>.git` (base and its ancestors only) |
| 2. Skill trees | `build_skills.py [--base-ref REF] --show-diff` | `WORK/skills/<arm>/` + `manifest.json` |
| 3. v2 annotation | `annotate.py --case ...` | `WORK/annotated/<case>/spec/` (frozen) + manifest |
| 4. Workspaces | `prepare.py --arm ... --case ... --rep N` | `WORK/neutral/<hex>/` (the sandbox's `/work`); `WORK/attempts/<arm>/<case>/r<N>/{ws,attempt.json}` |
| 5. Runs | `run.py --arm ... --case ... --rep N [--plan]` | `WORK/attempts/.../log/`; `results/<arm>/<case>/r<N>/` |
| 6. Summary | `collect.py` | `results/summary.{md,json}` |
| 7. Export | `export.py all` | `results/<arm>/<case>/r<N>/{output,instrumentation,timeline.md,export.json}`; `inputs/` |
| 8. Archive | `archive.py --epoch E` | `/proj/aiopslab-PG0/specula-ci/inv-e2e/E/` (logs and workspaces, outside git) |
| Driver | `pipeline.py --case ...` | steps 3–5 and the per-run export (step 7) for several cases (run 6 and 8 by hand afterwards): arms in the fixed order v2, v0, v1, one at a time; the next case is annotated while the current one runs its last arm |
| Analysis | `analysis/timeline.py`, `analysis/prop_changes.py`, `analysis/prop_events.py` | per-run behavior timeline from the activity log; which prior properties a run kept, changed, deleted or stopped checking; per case, a table of every prior and new property across the arms (`analysis/out/`) |

`WORK` is `$INV_E2E_WORK` (default `/mydata/bingzhuo/inv-e2e`); `results/` can be redirected with `$INV_E2E_RESULTS`.

Other files:
- `common.py`: paths, the case list, and helpers. It reuses the blind study's `prepare_incremental.py`, which builds the neutral two-commit artifact.
- `agent.py`: the sandbox, plus behavior and cost extraction.
- `check_annotation.py`: checks that a v2 input changes comments only.
- `tools/hist.sh`: git history up to the base commit.
- `prompts/`: the task text, the final-response schema, and the annotation and review prompts.

## v2 inputs: annotation

`annotate.py` runs two fresh agent sessions per case in the sandbox: one annotates (`prompts/annotate.md`), the other reviews every block (`prompts/review.md`).

- **What the sessions see.** Only the base revision: its source tree, the V0 spec, and a history repository that physically contains no later commit.
- **What they write.** Comment lines only. `check_annotation.py` requires that:
  - non-comment lines and `.cfg` files are unchanged;
  - every property has exactly one block, with a known status;
  - SANY parses every changed module.
- **No model review in the notes.** `note:` lines may describe only the evidence search, never the model. Otherwise v2 would get a free model review that v1 does not get. Observations about the model go to `concerns.md`, which stays outside the workspace. The checker warns on model talk in `note`, `clause` and `review` lines.
- **No hint about the cohort.** The examples in the prompts come from a fictional system, not from any cohort case or from etcd.

## Controls

- **Same everything but the arm.** Same V0, task text, schema, model (`claude-opus-5-5`, effort `xhigh`), 4 h timeout, $100 budget and sandbox. Workspaces carry no arm name; the arm is recorded only outside the sandbox.
- **Isolation.** The sandbox is bubblewrap with `--unshare-all --share-net --clearenv`:
  - the workspace is at `/work`;
  - HOME is a throwaway directory holding only the agent's credentials;
  - `network-guard` is first on PATH and blocks curl, wget, gh, text browsers and git fetch/clone/pull.

  The network stays up for the model API and for dependency downloads. Every shell command is audited afterwards, and a hit marks the run `contaminated`. Each flagged run is reviewed by hand and recorded in `results/audit-review.json`. Every flag so far was a false alarm: a local `git clone` of the workspace's own artifact repository, or a `cat` of the guard scripts.
- **Freeze.** Skill trees and annotations are built once. Their hashes go into `manifest.json` and `attempt.json`, and the overlays were not changed after the first real run. Each run is used once.
- **Infrastructure failures.** Runs that end in `USAGE_LIMIT` (the account's 5-hour window) or `AUTH_ERROR` (the sandbox's OAuth session expired) are archived as invalid and restarted from scratch with a freshly prepared workspace. They are never results; their cost is reported separately.
- **Truncated runs are results.** A run stopped by the per-run cost cap (`BUDGET_CAP`, `--max-budget-usd 100`) or the 4-hour timeout (`TIMEOUT`) is recorded as it is and never rerun: rerunning would select on whether a run fits the cap. Its outputs are exported to `results/<arm>/<case>/r<N>/output/` like those of any run (`run.py` first copies them to `partial/`, which `export.py` replaces); the workspace and the full session log stay under `WORK/attempts/` and go to the archive. The pipeline moves on to the next configuration.

## What is recorded per run

`results/<arm>/<case>/r<N>/` holds:
- `run.json`:
  - status, final decision, workflow status and findings paths;
  - wall time, cost and token usage, turns;
  - tool-call counts, and the number of TLC, SANY and build/test commands;
  - the skill files read, which shows whether the arm used its overlay;
  - `invariant-evidence.json` statistics: decisions, evidence records, state sources, claimed versus TLC truth values, bug candidates;
  - the network audit, and the hashes of the skill tree and the prior.
- `final-response.json`: the agent's final answer.
- `invariant-evidence.json` (v1, v2 only).
- `output/`: the run's `.specula-output` as exported by `export.py`: reports (analysis, modeling brief,
  bug report, confirmations, changelog), the full spec suite with cfgs and evidence, the harness, the
  traces, and TLC logs. See "Storage" for what is left out.
- `instrumentation/*.diff`: the agent's edits to source trees (instrumentation, reproduction tests, old controls).
- `timeline.md`: agent messages and one line per tool call, from the session log.
- `export.json`: what the export skipped, trimmed or cut, with the original sizes and hashes.

`inputs/` holds what every run started from:
- `inputs/<case>/`: the neutral task files, the sandbox input map of each arm, and v2's frozen annotated
  prior suite with the annotation and review reports. The v0/v1 prior suite is the blind V0 in
  `../blind-incremental-bugs/blind-incremental-v0/<case>/.specula-output/`, committed verbatim;
  `v0-suite.sha256` and `previous.<arm>.sha256` show that v0/v1 got exactly that tree.
- `inputs/skills/<arm>-manifest.json`: base commit, overlay hashes and tree hash of each arm's skill tree.

## Storage

Three tiers; nothing is kept only on `/mydata`.

| Tier | Where | What |
|---|---|---|
| git | this directory (`results/`, `inputs/`) and the blind V0 suites | run records, reports, models, harnesses, traces, evidence, trimmed TLC logs, instrumentation diffs, timelines, inputs |
| archive | `/proj/aiopslab-PG0/specula-ci/inv-e2e/<epoch>/` (`archive.py`) | full session logs of runs, annotation sessions and invalid attempts; each run's workspace without build and TLC-state directories or regenerable read-only inputs; `MANIFEST.json` with tarball hashes |
| none | | build caches, TLC state directories, `subjects/`, `history/`, `repos/`, `skills/` (regenerated by `materialize.py`, `build_skills.py` and `prepare.py`) |

`export.py` leaves out of git:
- source trees: directories with their own `.git`, and copies of the upstream tree; their edits are in `instrumentation/`;
- build, `target`, `states` and similar directories, binaries, `*_TTrace_*` dumps;
- in TLC logs, per-state variable dumps and profiler noise (statistics, coverage and counterexample actions stay);
- the head and tail of any text file still over 2 MB are kept, the middle cut.

Every omission is listed in the run's `export.json` and its file is in the archive.

**Epochs.** Runs are compared only within one epoch: one base skill commit, one overlay set, one model and
one set of limits. Epoch 1 is the 21 runs below (base `5880061f`, model `claude-opus-5-5`, effort `xhigh`,
4 h, $100). A new base commit or overlay change starts a new epoch with its own v0 runs.

Grading (`BLIND_DISCOVERED` and so on) is entered by hand in `results/grading.json` after Gold is unsealed; `collect.py` merges it.

## Pilot results: case-006 (etcd Raft, Linearizable ReadIndex)

One run per arm. Gold is still sealed, so "found" below means the arm reported a defect and reproduced it in code; whether it is the Gold bug is not yet known.

| Arm | Decision | Reported defect | Confirmation | Minutes | USD | Turns | TLC cmds |
|---|---|---|---|---:|---:|---:|---:|
| v0 | MODEL_UPDATED | stale read after ReadIndex context reuse | TLC, real trace, reachability test (fails on update, passes on baseline); bug-confirmation step skipped | 118 | 25.51 | 224 | 18 |
| v1 | MODEL_UPDATED | same | TLC, Go reproduction | 114 | 17.06 | 142 | 11 |
| v2 | MODEL_UPDATED | same | TLC, real trace, Go reproduction | 95 | 18.74 | 154 | 14 |

All three arms ended with workflow status `COMPLETED_WITH_LIMITED_COVERAGE`.

**The defect.** The update deletes released ReadIndex requests under their real key, so a caller context can be registered again in the same term. `recvAck` matches acks by context only, so a heartbeat response for the earlier registration confirms the new request. If a newer leader has committed meanwhile, the old leader returns a stale read index.

**Findings.**
- **Detection.** All three arms report the same defect. On this case the baseline already finds it, and v1/v2 add no detection gain.
- **Property evolution, the only visible difference.**
  - v0 added `UpdReadAckFreshness`. When TLC violated it, v0 relaxed it to `UpdReadAckAfterEnqueue`, without a separating state and without saying why the violating state was not a bug. The counterexample it relaxed away was the defect's own mechanism. v0 still found the defect through a later linearizability property, so the relaxation cost nothing here, but it is the behavior `divergence-evidence.md` targets.
  - v1 and v2 made no unsupported reversals. Each recorded 11 evidence records, and the claimed truth values matched TLC on all 18 evaluated sides. v2's run.json shows 16/18 only because of a string-format difference.
  - v2 used the ledger. It kept `ReadDeliveryJustified`, which is annotated as a requirement, and added a stronger property. v1 recorded the same change as a modify.
- **Prior properties.** None of the 25 prior properties was deleted or weakened by any arm. Only `TypeOK` gained fields.
- **Cost.** v1 < v2 < v0. With one run per arm, this may be noise. Part of v0's extra cost is its property-revision loop and an extra repair of a pre-existing V0 crash defect.
- **Annotation cost (v2 only, once per case).** $12.21: annotation $7.80 plus review $4.41.

## Epoch-1 analysis

[`analysis/epoch-1/`](analysis/epoch-1/README.md) holds the judged analysis of all 21 epoch-1 runs: a rubric for invariant-evolution quality and miss attribution, one file per case, and a summary of why bugs were missed, how well each arm evolved its properties, and a proposed strengthening of the skill.

## Status (2026-11-20)

- Finished: 7 cases (006, 002, 003, 004 pilot; 010, 012, 011 extension, picked by the user from public
  metadata only) × v0/v1/v2, r1. 20 runs EXITED_0; v0/case-010 hit the 4-hour TIMEOUT and is kept as a
  truncated result; its outputs are exported to `output/` like every other run.
  No contamination after manual review (`results/audit-review.json`). Ungraded (Gold sealed).
  Automatic decisions: `WORK/pipeline-decisions.md`.
- `pipeline.py` runs cases back to back in the fixed order v2, v0, v1 and annotates the next case while the
  current case runs v1; it is resumable.
- Infrastructure hardening found during the pilot: OAuth credentials are synced both ways during a run and an
  auth failure ends the run as AUTH_ERROR (archived and retried); usage limits archive and retry after the reset.
- `findings` in `summary.md` counts `findings_paths` entries, not distinct defects.
- Not yet exercised: the codex backend; a real `BUDGET_CAP` run.

## Known gaps

- The base skill commit of the original blind runs is not confirmed; `build_skills.py` defaults to `HEAD`. Here the shared skills come from the same base commit as `incremental-modeling`.
- The incremental skill mentions `specula ci-result` and context compaction. Neither is available in the blind task, which uses `final-schema.json` instead, as the original blind runs did.
- **Cost of killed runs.** The claude backend reports USD only in its final result event, which a timed-out or budget-killed run never emits. `run.json` then has `cost_usd: null` and `behavior.streamed_usage`. Input and cache tokens there are exact; output tokens are a lower bound.
- The scorer of property-evolution behavior is not blind to the arm.

## Example

```sh
python3 materialize.py
python3 build_skills.py --show-diff
python3 annotate.py --case case-006
python3 prepare.py --arm v0 --arm v1 --arm v2 --case case-006 --rep 1
python3 run.py --arm v2 --case case-006 --rep 1     # one arm at a time
python3 pipeline.py --case case-002 --case case-003 --case case-004
python3 collect.py
python3 analysis/prop_changes.py v0 case-006
```
