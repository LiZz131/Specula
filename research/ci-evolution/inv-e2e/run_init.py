#!/usr/bin/env python3
"""Run prepared ci-init attempts (prepare_init.py) and freeze the resulting prior suites.

    python3 run_init.py --case case-011 [--rep 1] --main-tools [--main-tools-dir DIR]
    python3 run_init.py --all-cases --rep 1 --main-tools --timeout 14400 --budget 100
    python3 run_init.py --plan ...

One fresh agent per (case, rep) in the same bwrap sandbox as run.py (agent.run_agent), in the
Specular environment (specular_env: /opt/specular on PATH, SPECULAR_ROOT), with main's MCP servers
from the main-tools build. The skill tree is also bound at /work/.claude/skills (project skills
for the claude backend), as in run.py.

Read-only: source, scope.md, lib, tools, .agents, task.md, final-schema.json, input-manifest.json.
Writable: work-source, prior, .cache.

USAGE_LIMIT and AUTH_ERROR runs are void: archived to WORK/invalid/init-<case>-r<rep>-a<n>-<stamp>,
re-prepared and rerun after the reset (as in run.py). Every other outcome is a result, including
TIMEOUT and BUDGET_CAP, and is frozen as it is:

  WORK/inits/<case>/r<rep>/log/                      session log, run-manifest.json, command.json
  WORK/inits/<case>/r<rep>/prior/.specular-output/   the suite, read-only (prepare.py --prior)
  WORK/inits/<case>/r<rep>/final-response.json       final answer (claude: the result event text)
  WORK/inits/<case>/r<rep>/work-source.diff          instrumentation, relative to the neutral commit
  WORK/inits/<case>/r<rep>/manifest.json             hashes (prior tree, skill tree, main tools,
                                                     source, task), status, cost, final fields

Defaults follow run_baselines.py (4 h per run); --budget (claude) as run.py.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

from agent import limit_wait_seconds, run_agent, wait_for_credentials
from common import CASE_IDS, WORK, check_case, read_json, sha256, tree_hash, write_json
from prepare import H
from prepare_init import OUT, prepare_init

RO = [".agents", "lib", "tools", "source", "scope.md", "input-manifest.json", "task.md", "final-schema.json"]
RW = ["work-source", "prior", ".cache"]
FINAL_CODEX = "/work/prior/final-response.json"


class StopQueue(RuntimeError):
    """A usage limit without a parseable 5-hour reset: stop and let a person decide."""


STOP = threading.Event()


def final_text(backend: str, ws: Path, activity: Path) -> str | None:
    """codex writes --output-last-message; claude's answer is the text of its result event."""
    if backend == "codex":
        f = ws / "prior/final-response.json"
        return f.read_text() if f.is_file() else None
    text = None
    for line in activity.read_text(errors="replace").splitlines():
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            continue
        if ev.get("type") == "result" and isinstance(ev.get("result"), str):
            text = ev["result"]
    return text


def parse_final(text: str | None) -> dict | None:
    if text is None:
        return None
    for candidate in (text.strip(), *re.findall(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.S)):
        try:
            value = json.loads(candidate)
            if isinstance(value, dict):
                return value
        except json.JSONDecodeError:
            pass
    start, end = text.find("{"), text.rfind("}")
    if 0 <= start < end:
        try:
            value = json.loads(text[start:end + 1])
            if isinstance(value, dict):
                return value
        except json.JSONDecodeError:
            pass
    return {"parse_error": True}


def archive_invalid(case_id: str, rep: int, manifest: dict) -> Path:
    logical = WORK / "inits" / case_id / f"r{rep}"
    attempt = read_json(logical / "attempt.json")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = WORK / "invalid" / f"init-{case_id}-r{rep}-a{attempt.get('attempt_no', 1)}-{stamp}"
    dest.parent.mkdir(parents=True, exist_ok=True)
    physical = Path(attempt["physical"])
    shutil.move(str(logical), str(dest))
    if physical.exists():
        H.make_tree_owner_writable(physical)
        shutil.move(str(physical), str(dest / "ws-physical"))
    write_json(dest / "invalid.json", {
        "kind": "ci-init", "case_id": case_id, "rep": rep, "attempt_no": attempt.get("attempt_no", 1),
        "status": manifest["status"], "reason": (manifest["behavior"].get("error") or {}).get("text"),
        "wall_seconds": manifest["wall_seconds"], "cost_usd": manifest["behavior"].get("cost_usd"),
        "streamed_usage": manifest["behavior"].get("streamed_usage"),
    })
    return dest


def freeze(logical: Path, ws: Path, attempt: dict, manifest: dict, backend: str) -> dict:
    prior = logical / "prior" / OUT
    shutil.copytree(ws / "prior" / OUT, prior, symlinks=True)
    H.make_tree_read_only(logical / "prior")
    text = final_text(backend, ws, logical / "log/activity.jsonl")
    if text is not None:
        (logical / "final-response.json").write_text(text)
    final = parse_final(text)
    diff = subprocess.run(["git", "-C", str(ws / "work-source"), "diff", "--binary", "HEAD"],
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False).stdout
    untracked = subprocess.run(["git", "-C", str(ws / "work-source"), "ls-files", "--others", "--exclude-standard"],
                               text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False).stdout
    (logical / "work-source.diff").write_bytes(diff)
    (logical / "work-source.untracked.txt").write_text(untracked)
    pristine = subprocess.run(["git", "-C", str(ws / "source"), "status", "--porcelain"], text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
    b = manifest["behavior"]
    record = {
        "schema_version": 1,
        "kind": "ci-init",
        "case_id": attempt["case_id"],
        "rep": attempt["rep"],
        "attempt_no": attempt.get("attempt_no", 1),
        "frozen_at_utc": datetime.now(timezone.utc).isoformat(),
        "prior": str(prior),
        "prior_tree_sha256": tree_hash(prior),
        "skills_tree_sha256": attempt["skills_tree_sha256"],
        "skills_base_commit": attempt["skills_manifest"].get("base_commit"),
        "skills_manifest_tree_sha256": attempt["skills_manifest"].get("tree_sha256"),
        "main_tools": {k: manifest["main_tools"][k] for k in ("root", "manifest_sha256", "tree_sha256",
                                                              "source_commit", "servers")}
        if "main_tools" in manifest else None,
        "source_identity": attempt["source_identity"],
        "synthetic_head": attempt["synthetic_head"],
        "scope_sha256": attempt["scope_sha256"],
        "task_sha256": attempt["task_sha256"],
        "status": manifest["status"],
        "truncated": manifest["status"] in ("BUDGET_CAP", "TIMEOUT"),
        "backend": manifest["backend"], "model": manifest["model"], "effort": manifest["effort"],
        "budget_usd": manifest["budget_usd"], "timeout_seconds": manifest["timeout_seconds"],
        "wall_seconds": manifest["wall_seconds"],
        "cost_usd": b.get("cost_usd"),
        "cost_source": b.get("cost_source"),
        "usage": b.get("usage"),
        "streamed_usage": b.get("streamed_usage"),
        "num_turns": b.get("num_turns"),
        "tlc_commands": b.get("tlc_commands"),
        "skill_files_read": b.get("skill_files_read"),
        "network_audit": b.get("network_audit"),
        "final_response": {k: (final or {}).get(k) for k in ("workflow_status", "trace_validation", "model_checking")}
        | {"present": final is not None, "parse_error": bool((final or {}).get("parse_error"))},
        "pristine_source_clean": pristine.returncode == 0 and not pristine.stdout.strip(),
        "work_source_diff_sha256": sha256(logical / "work-source.diff"),
        "session_log": str(logical / "log/activity.jsonl"),
        "frozen": True,
    }
    write_json(logical / "manifest.json", record)
    return record


def run_once(case_id: str, rep: int, args) -> tuple[dict | None, dict]:
    logical = WORK / "inits" / case_id / f"r{rep}"
    attempt_path = logical / "attempt.json"
    if not attempt_path.exists():
        raise RuntimeError(f"not prepared: {logical} (prepare_init.py)")
    attempt = read_json(attempt_path)
    if attempt.get("agent_started"):
        raise RuntimeError(f"already started: {logical} (prepare a new rep instead of rerunning)")
    args.skills_of[(case_id, rep)] = attempt.get("skills_dir")
    ws = Path(attempt["physical"])
    main_tools = args.main_tools_dir
    mt = read_json(main_tools / "manifest.json")
    attempt["main_tools"] = {"root": str(main_tools), "manifest_sha256": sha256(main_tools / "manifest.json"),
                             "tree_sha256": mt["tree_sha256"], "source_commit": mt["source_commit"],
                             "servers": sorted(mt["servers"])}
    if args.backend == "claude":
        attempt["credential_hours_left_at_start"] = round(wait_for_credentials(args.timeout / 3600 + 0.5), 2)
    attempt["agent_started"] = True
    write_json(attempt_path, attempt)
    manifest = run_agent(
        backend=args.backend, workspace=ws, ro=RO, rw=RW, prompt=(ws / "task.md").read_text(),
        log_dir=logical / "log", timeout_s=args.timeout, model=args.model, effort=args.effort,
        budget_usd=args.budget, schema="/work/final-schema.json", final_path=FINAL_CODEX,
        extra_binds=[(str(ws / ".agents/skills"), "/work/.claude/skills")],
        meta={"kind": "ci-init", "case_id": case_id, "rep": rep, "attempt_no": attempt.get("attempt_no", 1),
              "skills_tree_sha256": attempt["skills_tree_sha256"]},
        main_tools=main_tools, specular_env=True,
    )
    if manifest["status"] in ("USAGE_LIMIT", "AUTH_ERROR"):
        return None, manifest
    record = freeze(logical, ws, attempt, manifest, args.backend)
    print(f"init {case_id} r{rep}: {record['status']} workflow={record['final_response']['workflow_status']} "
          f"trace={record['final_response']['trace_validation']} mc={record['final_response']['model_checking']} "
          f"${record['cost_usd']} {record['wall_seconds']:.0f}s "
          f"contaminated={record['network_audit']['contaminated']}", flush=True)
    return record, manifest


def run_one(case_id: str, rep: int, args) -> dict:
    for attempt_no in range(1, args.max_attempts + 1):
        if STOP.is_set():
            return {"case_id": case_id, "rep": rep, "status": "NOT_RUN_QUEUE_STOPPED"}
        record, manifest = run_once(case_id, rep, args)
        if manifest["status"] not in ("USAGE_LIMIT", "AUTH_ERROR"):
            return record
        dest = archive_invalid(case_id, rep, manifest)
        wait = 60 if manifest["status"] == "AUTH_ERROR" else limit_wait_seconds(manifest["behavior"], dest / "log/stderr.log")
        print(f"init {case_id} r{rep}: {manifest['status']} (attempt {attempt_no}) archived to {dest}; wait {wait}s",
              flush=True)
        if wait is None:
            STOP.set()
            raise StopQueue(f"usage limit without a 5-hour reset time: {(manifest['behavior'].get('error') or {}).get('text')}")
        time.sleep(wait)
        skills = args.skills_of.get((case_id, rep))
        logical = prepare_init(case_id, rep, Path(skills) if skills else None, args.main_tools_dir)
        attempt = read_json(logical / "attempt.json")
        attempt["attempt_no"] = attempt_no + 1
        write_json(logical / "attempt.json", attempt)
    raise RuntimeError(f"init {case_id} r{rep}: still usage-limited after {args.max_attempts} attempts")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--case", action="append", dest="cases")
    parser.add_argument("--all-cases", action="store_true")
    parser.add_argument("--rep", action="append", dest="reps", type=int)
    parser.add_argument("--jobs", type=int, default=1, help="parallel runs; keep 1 under a 5-hour usage window")
    parser.add_argument("--max-attempts", type=int, default=10, help="usage-limit retries per run")
    parser.add_argument("--backend", default="claude", choices=("claude",),
                        help="main tools (MCP) are wired for the claude backend only")
    parser.add_argument("--model")
    parser.add_argument("--effort")
    parser.add_argument("--timeout", type=int, default=14400, help="seconds per run (run_baselines.py: 4 h)")
    parser.add_argument("--budget", type=float, default=100.0, help="USD cap per run (claude backend)")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--main-tools", action="store_true", required=True,
                        help="required: the Specular environment needs the main-tools build (CLI, MCP servers)")
    parser.add_argument("--main-tools-dir", type=Path, default=WORK / "main-tools")
    args = parser.parse_args()
    args.skills_of = {}
    cases = list(CASE_IDS) if args.all_cases else (args.cases or [])
    for case_id in cases:
        check_case(case_id)
    if not (args.main_tools_dir / "manifest.json").is_file() or not (args.main_tools_dir / "specular").is_file():
        raise SystemExit(f"no main-tools build with the specular CLI at {args.main_tools_dir}")
    jobs = [(case_id, rep) for rep in (args.reps or [1]) for case_id in cases]
    if not jobs:
        raise SystemExit("nothing to run: give --case or --all-cases")
    if args.plan:
        for job in jobs:
            print(*job)
        return 0
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = [pool.submit(run_one, case_id, rep, args) for case_id, rep in jobs]
        results = []
        for (case_id, rep), fut in zip(jobs, futures):
            try:
                results.append(fut.result())
            except StopQueue as exc:
                results.append({"case_id": case_id, "rep": rep, "status": "QUEUE_STOPPED", "error": str(exc)})
                print(f"QUEUE STOPPED: {exc}", flush=True)
            except Exception as exc:
                results.append({"case_id": case_id, "rep": rep, "status": "RUNNER_ERROR", "error": repr(exc)})
                print(f"init {case_id} r{rep}: RUNNER_ERROR {exc!r}", flush=True)
    return 0 if all(r.get("status") == "EXITED_0" for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
