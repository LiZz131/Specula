#!/usr/bin/env python3
"""Prepare one blind incremental workspace per (arm, case, rep).

    python3 prepare.py --arm v1 --case case-002 [--rep 1]
    python3 prepare.py --arm v0 --arm v1 --arm v2 --all-cases --rep 1

Layout matches the blind study's prepare_incremental.py, so the task text is unchanged:

  /work/old-source, /work/new-source       changed files at base / update (read-only)
  /work/previous/.specula-output           V0 prior (v2: with annotated spec) (read-only)
  /work/current/.specula-output            writable copy of the same prior
  /work/current/.specula-output/artifact   updated tree, two neutral commits `baseline`, `update`
  /work/model-scope.md, case.json, input-manifest.json, task.md, final-schema.json
  /work/.agents/skills (= /work/.claude/skills)   the arm's skill tree
  /work/lib, /work/tools                   TLA+ jars, infra scripts, trace debugger, network guard

With --layout specular (epoch 2 after the rename; needs --main-tools) the workspace follows
Specular v1.5 (docs/Usage.md, "Switching from Specula"): `.specular-output` instead of
`.specula-output`, and the task names the `specular` CLI. As main's incremental runner does
(ci_workflow.prepare_source_snapshots), it also adds what `specular ci-result` and
`specular findings` need, with a neutral run ID:

  /work/ci-run/ci-source          frozen copy of the updated tree (read-only)
  /work/ci-run/ci-input.json      final_result_version 1, old_model = /work/previous/.specular-output
  current/.specular-output/persistent-findings-context.json, spec/persistent-findings/
                                  seeded from the prior (ci_verdict.seed_issues) and bound
                                  (persistent_findings.configure), run inside bwrap so the
                                  recorded paths are the agent's /work paths

The three arms differ only in .agents/skills and, for v2, the comments in previous/ and
current/ spec files. Nothing inside the workspace names the arm: the physical directory
is WORK/neutral/<random hex>, and the arm, skill-tree hash and prior hash are recorded
outside it, in WORK/attempts/<arm>/<case>/r<rep>/attempt.json (next to a `ws` symlink).
"""

from __future__ import annotations

import argparse
import secrets
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from common import (ARMS, BLIND_TOOLS, CASE_IDS, HERE, SPECULA, V0_ROOT, WORK, blind_helpers, check_arm,
                    check_case, read_json, sha256, tree_hash, write_json)

CACHE_DIRS = ("cargo", "cargo-target", "go-build", "go-mod", "gopath", "m2", "rebar3", "tmp")
H = blind_helpers()


def tools_dir(dest: Path) -> None:
    dest.mkdir()
    for name in ("start_background.sh", "wait_for_pid.sh", "clean_states.sh"):
        shutil.copy2(SPECULA / "scripts/infra" / name, dest / name)
    td = SPECULA / "tools/trace_debugger"
    shutil.copytree(td / "src", dest / "trace_debugger/src")
    shutil.copy2(td / "requirements.txt", dest / "trace_debugger/requirements.txt")
    shutil.copytree(BLIND_TOOLS / "network-guard", dest / "network-guard")
    for f in [*dest.glob("*.sh"), *(dest / "network-guard").iterdir()]:
        f.chmod(0o755)


def overlay_annotated(prior: Path, case_id: str) -> dict:
    annotated = WORK / "annotated" / case_id
    manifest = annotated / "manifest.json"
    if not manifest.exists() or not read_json(manifest).get("frozen"):
        raise SystemExit(f"{case_id}: no frozen annotation at {annotated}; run annotate.py first")
    replaced = []
    for path in (annotated / "spec").rglob("*"):
        if path.is_file():
            target = prior / "spec" / path.relative_to(annotated / "spec")
            if not target.exists():
                raise RuntimeError(f"annotated file has no V0 counterpart: {target}")
            shutil.copy2(path, target)
            replaced.append(path.relative_to(annotated / "spec").as_posix())
    return {"annotation_manifest_sha256": sha256(manifest), "replaced_spec_files": sorted(replaced)}


LAYOUTS = {"specula": ".specula-output", "specular": ".specular-output"}

# Final reporting as main's IncrementalPhase.build_prompt words it for a final_result_version-1 run.
SPECULAR_FINAL = """
## Specular final result

This run also uses Specular's incremental output contract. Write only
`/work/current/.specular-output/spec/final-result.json` using the final-result reference in the
skill. Use run ID `{run_id}`. Run `specular ci-result --work=/work/current/.specular-output`
before finishing; fix reported errors in that file. This generates the reports, verdict, and
persistent records. Do not maintain those generated outputs separately. Missing reuse metadata
only disables automatic reuse; missing core confirmation evidence prevents completion. Persistent
findings from the prior suite can be inspected with `specular findings --work=/work/current/.specular-output`.
"""


def task_text(case_id: str, layout: str, run_id: str | None) -> str:
    task = (HERE / "prompts/incremental-task.md").read_text().replace("INCREMENTAL_CASE_ID", case_id)
    if layout == "specula":
        return task
    task = (task.replace(".specula-output", ".specular-output")
            .replace("incremental Specula task", "incremental Specular task")
            .replace("/dev/shm/specula-e2e-", "/dev/shm/specular-e2e-"))
    if "specula" in task.lower().replace("specular", ""):
        raise RuntimeError("old name left in the Specular task text")
    return task + SPECULAR_FINAL.format(run_id=run_id)


def bind_ci_run(stage: Path, main_tools: Path, run_id: str, synthetic: dict) -> dict:
    """Mirror main's incremental setup for ci-result/findings; paths are the sandbox's /work paths."""
    out = "/work/current/.specular-output"
    ci = stage / "ci-run"
    ci.mkdir()
    shutil.copytree(stage / "current/.specular-output/artifact", ci / "ci-source", symlinks=True)
    write_json(ci / "ci-input.json", {
        "version": 1,
        "target": "target",
        "artifact": f"{out}/artifact",
        "source": "ci-source",
        "source_commit": synthetic["update_commit"],
        "snapshot_commit": synthetic["update_commit"],
        "dirty": False,
        "guidance": "",
        "previous": "prior",
        "final_result_version": 1,
        "old_source": "/work/old-source",
        "old_model": "/work/previous/.specular-output",
    })
    code = (
        "from pathlib import Path\n"
        "from specular import ci_verdict, persistent_findings\n"
        f"work = Path('{out}')\n"
        "ci_verdict.seed_issues(work, Path('/work/old-source'), Path('/work/previous/.specular-output'))\n"
        f"persistent_findings.configure(work, Path('/work/ci-run/ci-source'), '{run_id}', "
        "Path('/work/previous/.specular-output'))\n"
    )
    from agent import MAIN_TOOLS_MOUNT, bwrap_command  # the agent's own sandbox layout
    with tempfile.TemporaryDirectory() as home:
        cmd = bwrap_command(stage, ["old-source", "previous", "ci-run"], ["current"],
                            [(str(main_tools), MAIN_TOOLS_MOUNT)], Path(home),
                            ["/usr/bin/env", f"PYTHONPATH={MAIN_TOOLS_MOUNT}/src", "python3", "-c", code],
                            specular_env=True)
        subprocess.run(cmd, check=True, env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"})
    work = stage / "current/.specular-output"
    index = work / "spec/persistent-findings/index.json"
    return {"run_id": run_id, "ci_input_sha256": sha256(ci / "ci-input.json"),
            "ci_source_tree_sha256": tree_hash(ci / "ci-source"),
            "seeded_findings": read_json(index) if index.exists() else None}


def prepare(arm: str, case_id: str, rep: int, layout: str = "specula", main_tools: Path | None = None) -> Path:
    logical = WORK / "attempts" / arm / case_id / f"r{rep}"
    if logical.exists():
        raise SystemExit(f"refusing to overwrite {logical}")
    subject = WORK / "subjects" / case_id
    skills = WORK / "skills" / arm
    for need in (subject / "subject.json", skills / "manifest.json"):
        if not need.exists():
            raise SystemExit(f"missing {need}: run materialize.py / build_skills.py first")
    subject_data = read_json(subject / "subject.json")
    changed = H.normalize_changed_files(subject_data["changed_files"])
    v0 = V0_ROOT / case_id / ".specula-output"
    out = LAYOUTS[layout]
    if layout == "specular" and not (main_tools and (main_tools / "specular").is_file()):
        raise SystemExit("--layout specular needs --main-tools with the specular CLI (build_main_tools.py)")

    physical = WORK / "neutral" / secrets.token_hex(16)
    stage = physical.with_name(f".{physical.name}.tmp")
    stage.mkdir(parents=True)
    try:
        shutil.copytree(subject / "old-source", stage / "old-source", symlinks=True)
        shutil.copytree(subject / "new-source", stage / "new-source", symlinks=True)

        prior = stage / ".prior"
        shutil.copytree(v0, prior, symlinks=True)
        annotation = overlay_annotated(prior, case_id) if arm == "v2" else None
        (stage / "previous").mkdir()
        (stage / "current").mkdir()
        shutil.copytree(prior, stage / f"previous/{out}", symlinks=True)
        shutil.copytree(prior, stage / f"current/{out}", symlinks=True)
        prior_hash = tree_hash(prior)
        shutil.rmtree(prior)
        artifact = stage / f"current/{out}/artifact"
        if artifact.exists() or artifact.is_symlink():
            H.remove_path(artifact)
        H.make_tree_owner_writable(stage / "current")
        synthetic = H.build_synthetic_artifact(subject / "old-tree", subject / "buggy-tree", artifact, changed)

        shutil.copy2(V0_ROOT / case_id / "scope.md", stage / "model-scope.md")
        write_json(stage / "case.json", {
            "schema_version": 1,
            "case_id": case_id,
            "category": subject_data["category"],
            "changed_files": changed,
            "source_history": {"kind": "neutral_synthetic_two_commit_history",
                               "commit_subjects": ["baseline", "update"],
                               "upstream_identifiers_included": False},
        })
        shutil.copytree(skills, stage / ".agents/skills", ignore=shutil.ignore_patterns("manifest.json"))
        (stage / "lib").mkdir()
        for jar in ("tla2tools.jar", "CommunityModules-deps.jar"):
            shutil.copy2(SPECULA / "lib" / jar, stage / "lib" / jar)
        tools_dir(stage / "tools")
        run_id = f"incr-{physical.name[:12]}" if layout == "specular" else None
        (stage / "task.md").write_text(task_text(case_id, layout, run_id))
        shutil.copy2(HERE / "prompts/final-schema.json", stage / "final-schema.json")
        for name in CACHE_DIRS:
            (stage / ".cache" / name).mkdir(parents=True)
        write_json(stage / "input-manifest.json", {
            "schema_version": 1,
            "case_id": case_id,
            "purpose": "blind_source_derived_incremental_verification",
            "inputs": {
                "old_source": "/work/old-source", "new_source": "/work/new-source",
                "previous": f"/work/previous/{out}", "current": f"/work/current/{out}",
                "artifact": f"/work/current/{out}/artifact", "model_scope": "/work/model-scope.md",
                "case_metadata": "/work/case.json", "skills": "/work/.agents/skills",
                "libraries": "/work/lib", "tools": "/work/tools",
            },
            "forbidden_inputs": [
                "fixed source", "upstream Git objects, refs, tags, remotes, and revision identifiers",
                "issues, pull requests, advisories, papers, release research, and incident history",
                "user memory and paths outside /work", "general internet research",
            ],
            "network_policy": "model API and ordinary build dependencies only; history and research commands are prohibited and audited",
        })
        ci_run = bind_ci_run(stage, main_tools, run_id, synthetic) if layout == "specular" else None
        H.make_tree_read_only(stage / "previous")
        if ci_run:
            H.make_tree_read_only(stage / "ci-run")
        for name in ("old-source", "new-source", ".agents", "lib", "tools"):
            H.make_tree_read_only(stage / name)
        stage.rename(physical)
    except BaseException:
        H.remove_tree(stage)
        raise

    logical.mkdir(parents=True)
    (logical / "ws").symlink_to(physical)
    attempt = {
        "schema_version": 1,
        "arm": arm,
        "case_id": case_id,
        "rep": rep,
        "physical": str(physical),
        "prepared_at_utc": datetime.now(timezone.utc).isoformat(),
        "skills_manifest": read_json(skills / "manifest.json"),
        "skills_tree_sha256": tree_hash(physical / ".agents/skills"),
        "prior_tree_sha256": prior_hash,
        "v0_tree_sha256": tree_hash(v0),
        "annotation": annotation,
        "task_sha256": sha256(physical / "task.md"),
        "synthetic_artifact": {k: synthetic[k] for k in ("baseline_commit", "update_commit", "commit_count")},
        "layout": layout,
        "output_dir": out,
        "main_tools_at_prepare": str(main_tools) if main_tools else None,
        "ci_run": ci_run,
        "agent_started": False,
    }
    write_json(logical / "attempt.json", attempt)
    print(f"{arm} {case_id} r{rep}: prepared -> {physical.name}", flush=True)
    return logical


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--arm", action="append", dest="arms", required=True)
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--all-cases", action="store_true")
    parser.add_argument("--rep", type=int, default=1)
    parser.add_argument("--layout", choices=sorted(LAYOUTS), default="specula")
    parser.add_argument("--main-tools", type=Path, help="main-tools build (required for --layout specular)")
    args = parser.parse_args()
    cases = list(CASE_IDS) if args.all_cases else (args.cases or [])
    if not cases:
        raise SystemExit("give --case or --all-cases")
    for arm in args.arms:
        check_arm(arm)
    for case_id in cases:
        check_case(case_id)
    for case_id in cases:
        for arm in args.arms:
            prepare(arm, case_id, args.rep, args.layout, args.main_tools)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
