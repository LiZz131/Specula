#!/usr/bin/env python3
"""Prepare one blind ci-init workspace per (case, rep): a fresh prior suite (P1) from the base source.

    python3 prepare_init.py --case case-011 [--rep 1] [--skills WORK/skills/v0]

The task and the inputs are those of the blind V0 generation (../blind-incremental-bugs/tools/
prepare_baselines.py with baseline-task-template.md), with main's skills and the Specular v1.5 names,
so a P1 prior differs from the V0 (P0) only in the skill version and the naming:

  /work/source                 base tree (WORK/subjects/<case>/old-tree) with one neutral commit
                               `baseline`, no remote, tag or history (read-only)
  /work/work-source            writable byte-identical copy (instrumentation, builds, traces)
  /work/scope.md               V0_ROOT/<case>/scope.md, the scope the V0 was given
  /work/prior/.specular-output empty, writable: the agent writes the suite here
  /work/lib, /work/tools       TLA+ jars; infra scripts of the specular layout (prepare.tools_dir,
                               with run_model_check.sh), trace debugger, network guard
  /work/.agents/skills         the skill tree (default WORK/skills/v0: main's skills, no overlay);
                               run_init.py also binds it at /work/.claude/skills
  /work/input-manifest.json, final-schema.json (baseline-final-schema.json), task.md

task.md is baseline-task-template.md with names changed only (Specula -> Specular,
.specula-output -> .specular-output, /dev/shm/specula-v0- -> /dev/shm/specular-init-, skill names
as in the skill tree); render_task() refuses to write a text with an old name left.

Nothing in the workspace names the rep: the physical directory is WORK/neutral/<random hex>; case,
rep and hashes are recorded outside it in WORK/inits/<case>/r<rep>/attempt.json, next to a `ws`
symlink. run_init.py runs the session and freezes the prior.
"""

from __future__ import annotations

import argparse
import os
import re
import secrets
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from common import BLIND_TOOLS, CASE_IDS, LIB, V0_ROOT, WORK, check_case, read_json, sha256, tree_hash, write_json
from prepare import CACHE_DIRS, H, tools_dir

TEMPLATE = BLIND_TOOLS / "baseline-task-template.md"
SCHEMA = BLIND_TOOLS / "baseline-final-schema.json"
OUT = ".specular-output"
# Skill names in the template -> directory names in the skill tree. main's public names are the
# template's (build_skills.py SKILL_SOURCES); render_task checks every name against the tree.
SKILL_RENAMES: dict[str, str] = {}
TEMPLATE_SKILLS = ("code-analysis", "spec-generation", "harness-generation", "tla-trace-workflow",
                   "validation-workflow", "tla-checking-workflow")


def render_task(case_id: str, skills: Path) -> str:
    text = TEMPLATE.read_text()
    for name in TEMPLATE_SKILLS:
        if f"`{name}`" not in text:
            raise RuntimeError(f"template no longer names skill {name}")
    for old, new in SKILL_RENAMES.items():
        text = text.replace(f"`{old}`", f"`{new}`")
    for name in (SKILL_RENAMES.get(n, n) for n in TEMPLATE_SKILLS):
        if not (skills / name / "SKILL.md").is_file():
            raise RuntimeError(f"task names skill {name}, which is not in {skills}")
    text = text.replace("/dev/shm/specula-v0-BASELINE_CASE_ID/", f"/dev/shm/specular-init-{case_id}/")
    text = text.replace(".specula-output", OUT)
    text = re.sub(r"\bSpecula\b", "Specular", text)
    text = text.replace("BASELINE_CASE_ID", case_id)
    check_task(text)
    return text


def check_task(text: str) -> None:
    left = [m.group(0) for m in re.finditer(r"specula(?![a-z])|-v0-|BASELINE_CASE_ID", text, re.I)]
    if left:
        raise RuntimeError(f"old names left in the ci-init task text: {sorted(set(left))}")


def git(source: Path, *args: str, env: dict | None = None) -> str:
    done = subprocess.run(["git", *args], cwd=source, text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, env=env, check=False)
    if done.returncode != 0:
        raise RuntimeError(f"git {args} failed: {done.stdout}")
    return done.stdout


def neutral_source(old_tree: Path, source: Path) -> dict:
    """Same as prepare_baselines.prepare_case: copy, one neutral commit, check no history/remote/tag."""
    if (old_tree / ".git").exists():
        raise RuntimeError(f"upstream Git metadata in {old_tree}")
    shutil.copytree(old_tree, source, symlinks=True)
    before = H.tree_identity(source)
    git(source, "init", "-q", "-b", "baseline")
    git(source, "config", "user.name", "Baseline")
    git(source, "config", "user.email", "baseline@invalid")
    git(source, "config", "commit.gpgsign", "false")
    git(source, "add", "-A")
    env = {**os.environ, "GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z"}
    git(source, "commit", "-q", "--no-gpg-sign", "-m", "baseline", env=env)
    if git(source, "remote").strip():
        raise RuntimeError("unexpected remote in the neutral source repository")
    if git(source, "rev-list", "--count", "--all").strip() != "1":
        raise RuntimeError("neutral source repository does not hold exactly one commit")
    if git(source, "tag", "--list").strip():
        raise RuntimeError("unexpected tag in the neutral source repository")
    if git(source, "status", "--porcelain").strip():
        raise RuntimeError("neutral source repository is dirty")
    if H.tree_identity(old_tree) != before:
        raise RuntimeError("source copy drift")
    return {"identity": before, "head": git(source, "rev-parse", "HEAD").strip(),
            "log": git(source, "log", "--format=%s", "--all").splitlines()}


def prepare_init(case_id: str, rep: int, skills: Path | None = None, main_tools: Path | None = None) -> Path:
    logical = WORK / "inits" / case_id / f"r{rep}"
    if logical.exists():
        raise SystemExit(f"refusing to overwrite {logical}")
    subject = WORK / "subjects" / case_id
    skills = skills or WORK / "skills" / "v0"
    scope = V0_ROOT / case_id / "scope.md"
    for need in (subject / "old-tree", skills / "manifest.json", scope):
        if not need.exists():
            raise SystemExit(f"missing {need}: run materialize.py / build_skills.py first")

    physical = WORK / "neutral" / secrets.token_hex(16)
    stage = physical.with_name(f".{physical.name}.tmp")
    stage.mkdir(parents=True)
    try:
        src = neutral_source(subject / "old-tree", stage / "source")
        shutil.copytree(stage / "source", stage / "work-source", symlinks=True)
        shutil.copy2(scope, stage / "scope.md")
        (stage / "task.md").write_text(render_task(case_id, skills))
        shutil.copy2(SCHEMA, stage / "final-schema.json")
        shutil.copytree(skills, stage / ".agents/skills", ignore=shutil.ignore_patterns("manifest.json"))
        (stage / "lib").mkdir()
        for jar in ("tla2tools.jar", "CommunityModules-deps.jar"):
            shutil.copy2(LIB / jar, stage / "lib" / jar)
        tools_dir(stage / "tools", "specular")
        (stage / f"prior/{OUT}").mkdir(parents=True)
        for name in CACHE_DIRS:
            (stage / ".cache" / name).mkdir(parents=True)
        # Same fields as prepare_baselines.py's public manifest, with the Specular output path.
        # Its `prep` block (inspection hints from the original study's prep/ directory) is not in
        # this repository and is left out.
        write_json(stage / "input-manifest.json", {
            "schema_version": 1,
            "case_id": case_id,
            "purpose": "neutral_exact_old_v0_prior_generation",
            "source": {
                "pristine_path": "/work/source",
                "writable_work_path": "/work/work-source",
                "role": "exact_old_only",
                "git_history": "one neutral synthetic baseline commit; no remotes, tags, or upstream objects",
                **src["identity"],
            },
            "scope_path": "/work/scope.md",
            "output_path": f"/work/prior/{OUT}",
            "allowed_inputs": ["/work/source", "/work/work-source", "/work/scope.md", "/work/lib", "/work/tools",
                               "/work/.agents/skills"],
            "forbidden_inputs": [
                "new or fixed source",
                "source diff",
                "upstream history, refs, tags, or remotes",
                "issues, pull requests, advisories, papers, and release notes",
                "Gold, grader, candidate manifest, prior answers, and another case's outputs",
                "general internet research",
            ],
            "network_policy": "model API and ordinary build dependencies only; command activity is audited",
        })
        for name in ("source", ".agents", "lib", "tools"):
            H.make_tree_read_only(stage / name)
        for name in ("scope.md", "task.md", "final-schema.json", "input-manifest.json"):
            (stage / name).chmod(0o444)
        stage.rename(physical)
    except BaseException:
        H.remove_tree(stage)
        raise

    logical.mkdir(parents=True)
    (logical / "ws").symlink_to(physical)
    write_json(logical / "attempt.json", {
        "schema_version": 1,
        "kind": "ci-init",
        "case_id": case_id,
        "rep": rep,
        "physical": str(physical),
        "prepared_at_utc": datetime.now(timezone.utc).isoformat(),
        "source_identity": src["identity"],
        "synthetic_head": src["head"],
        "synthetic_log": src["log"],
        "skills_dir": str(skills),
        "skills_manifest": read_json(skills / "manifest.json"),
        "skills_tree_sha256": tree_hash(physical / ".agents/skills"),
        "scope_source": str(scope),
        "scope_sha256": sha256(physical / "scope.md"),
        "task_template_sha256": sha256(TEMPLATE),
        "task_sha256": sha256(physical / "task.md"),
        "schema_sha256": sha256(physical / "final-schema.json"),
        "layout": "specular",
        "output_dir": OUT,
        "main_tools_at_prepare": str(main_tools) if main_tools else None,
        "agent_started": False,
    })
    print(f"init {case_id} r{rep}: prepared -> {physical.name}", flush=True)
    return logical


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--all-cases", action="store_true")
    parser.add_argument("--rep", type=int, default=1)
    parser.add_argument("--skills", type=Path, help="skill tree (default WORK/skills/v0)")
    args = parser.parse_args()
    cases = list(CASE_IDS) if args.all_cases else (args.cases or [])
    if not cases:
        raise SystemExit("give --case or --all-cases")
    for case_id in cases:
        check_case(case_id)
    for case_id in cases:
        prepare_init(case_id, args.rep, args.skills)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
