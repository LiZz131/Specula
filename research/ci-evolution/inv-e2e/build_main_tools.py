#!/usr/bin/env python3
"""Freeze the Specula-main MCP tool runtime that `run.py --main-tools` mounts at /opt/specular.

    python3 build_main_tools.py [--dest DIR]   # default $INV_E2E_WORK/main-tools (refuses to overwrite)

Builds before 2026-11-25 (epoch-2 round 1, WORK/main-tools) held only the four files of
src/specular the MCP servers import, and no CLI.

A Specula main install gives agents four MCP servers: tracedebugger, spec_analyzer and
inv_checking_tool (registered by scripts/infra/setup.sh) and specular_tlc (per run, from
src/specular/tlc_tasks.py: prepare_environment). This copies from this checkout exactly what
those servers need, keeping the checkout's layout so their SPECULAR_ROOT lookups resolve:

  tools/{trace_debugger,spec_analyzer,inv_checking_tool,tlc_tools}   server code + .venv
  tools/cfa/target/<parser jar>      spec_analyzer's run_vav_analysis
  src/specular/                      the whole package: start_tlc/wait_tlc + TLC guard, and the
                                     `specular` CLI (ci-result, findings, ...) that the skills call
  scripts/tlc/                       run_model_check.sh (the TLC wrapper start_tlc runs)
  scripts/infra/                     start_background.sh, run_model_check.sh, wait_for_pid.sh (skills)
  scripts/launch/, specular          the CLI's launch scripts and its repo-root shim; agent.py puts
                                     /opt/specular on PATH, as `uv tool install` does on main
  lib/{tla2tools,CommunityModules-deps}.jar

Tool tests, examples and source bytecode caches are left out; the venvs are copied as is
(their python is a symlink to /usr/bin/python3.10, which the sandbox has). tools/context_control
is runner-internal orchestration (compaction/confirmation) and is not part of the agent's tools.
manifest.json records the source commit, a tree hash of everything else, and the size.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path

from common import SPECULA, WORK, blind_helpers, tree_hash, write_json

TOOLS = ("trace_debugger", "spec_analyzer", "inv_checking_tool", "tlc_tools")
JARS = ("lib/tla2tools.jar", "lib/CommunityModules-deps.jar",
        "tools/cfa/target/tlaplus-parser-1.0-SNAPSHOT-jar-with-dependencies.jar")
SKIP_SOURCE = {"tests", "examples", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache"}
# name -> (tool dir, server script); the in-sandbox command is <root>/tools/<dir>/.venv/bin/python <script>
SERVERS = {
    "tracedebugger": ("trace_debugger", "mcp_server.py"),
    "spec_analyzer": ("spec_analyzer", "mcp_server.py"),
    "inv_checking_tool": ("inv_checking_tool", "mcp_server.py"),
    "specular_tlc": ("tlc_tools", "mcp_server.py"),
}


def _ignore_source(directory: str, names: list[str]) -> set[str]:
    """Skip tests/examples/caches in tool sources, but copy venvs untouched."""
    if "/.venv" in directory or directory.endswith(".venv"):
        return set()
    return {n for n in names if n in SKIP_SOURCE or n.endswith(".pyc")}


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", str(SPECULA), *args], text=True, capture_output=True, check=True).stdout.strip()


def build(dest: Path) -> dict:
    if dest.exists():
        raise SystemExit(f"refusing to overwrite {dest}")
    for tool in TOOLS:
        if not (SPECULA / "tools" / tool / ".venv/bin/python").exists():
            raise SystemExit(f"missing venv for tools/{tool}: run scripts/infra/setup.sh first")
    stage = dest.with_name(f".{dest.name}.tmp")
    if stage.exists():
        blind_helpers().remove_tree(stage)
    stage.mkdir(parents=True)
    try:
        for tool in TOOLS:
            shutil.copytree(SPECULA / "tools" / tool, stage / "tools" / tool, symlinks=True, ignore=_ignore_source)
        shutil.copytree(SPECULA / "src/specular", stage / "src/specular", ignore=_ignore_source)
        shutil.copytree(SPECULA / "scripts/tlc", stage / "scripts/tlc", ignore=_ignore_source)
        shutil.copytree(SPECULA / "scripts/launch", stage / "scripts/launch", ignore=_ignore_source)
        shutil.copytree(SPECULA / "scripts/infra", stage / "scripts/infra", ignore=_ignore_source)
        shutil.copy2(SPECULA / "specular", stage / "specular")
        for rel in JARS:
            (stage / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(SPECULA / rel, stage / rel)
        paths = [f"tools/{t}" for t in TOOLS] + ["src/specular", "scripts/tlc", "scripts/launch", "scripts/infra", "specular"]
        files = [p for p in stage.rglob("*") if p.is_file() and not p.is_symlink()]
        manifest = {
            "schema_version": 1,
            "built_at_utc": datetime.now(timezone.utc).isoformat(),
            "source_repo": str(SPECULA),
            "source_commit": git("rev-parse", "HEAD"),
            "source_branch": git("rev-parse", "--abbrev-ref", "HEAD"),
            # Tracked files under the copied paths that differ from the commit (should be empty).
            "source_dirty_paths": git("status", "--porcelain", "--", *paths).splitlines(),
            "untracked_inputs": list(JARS) + [f"tools/{t}/.venv" for t in TOOLS],
            "cli": "specular",
            "servers": {name: {"command": f"tools/{d}/.venv/bin/python", "args": [f"tools/{d}/{s}"]}
                        for name, (d, s) in SERVERS.items()},
            "excluded": sorted(SKIP_SOURCE | {"*.pyc outside .venv", "tools/context_control (runner-internal)"}),
            "tree_sha256": tree_hash(stage),
            "file_count": len(files),
            "size_bytes": sum(p.stat().st_size for p in files),
        }
        write_json(stage / "manifest.json", manifest)
        blind_helpers().make_tree_read_only(stage)
        stage.rename(dest)
    except BaseException:
        blind_helpers().remove_tree(stage)
        raise
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dest", type=Path, default=WORK / "main-tools")
    args = parser.parse_args()
    m = build(args.dest)
    print(f"{args.dest}: commit {m['source_commit'][:12]} tree {m['tree_sha256'][:16]} "
          f"{m['file_count']} files {m['size_bytes'] / 1e6:.1f} MB dirty={len(m['source_dirty_paths'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
