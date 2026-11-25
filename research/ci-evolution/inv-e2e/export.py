#!/usr/bin/env python3
"""Export the reviewable outputs of finished runs and their inputs into the repository.

    python3 export.py runs [--arm A] [--case C] [--rep N]   # results/<arm>/<case>/r<N>/{output,instrumentation,timeline.md,export.json}
    python3 export.py inputs [--case C]                      # inputs/<case>/ and inputs/skills/
    python3 export.py all

What a run keeps (results/<arm>/<case>/r<N>/):
- output/: the agent's .specula-output (model, harness, traces, reports, evidence, TLC logs), minus
  source trees, build/TLC-state directories, binaries and TTrace dumps. A source tree is a directory
  holding .git, or a copy of the upstream tree (a build manifest and a root listing that mostly
  matches the artifact repository's).
  TLC logs drop TLC's per-state variable dumps (lines starting with "/\\", a space or a tab; the
  same rule as ../etcd-v0-v3/prefix-ablation) and profiler noise. Any file still over MAX_FILE is cut
  to its head and tail. Every skipped, trimmed or cut file is listed in export.json.
- instrumentation/<dir>.diff: for every source tree the agent modified (work-source, repro trees,
  old controls), the diff against its own HEAD, or for a copy against the artifact's baseline or
  update commit (whichever is smaller), plus untracked files.
- timeline.md: the agent's messages and a one-line summary of every tool call, in order, from
  log/activity.jsonl. The full log stays in WORK and in the /proj archive (archive.sh).

The full workspace, the session log and every skipped file stay under WORK/attempts and in the
archive; nothing here is the only copy of anything.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

from common import ARMS, HERE, RESULTS, V0_ROOT, WORK, read_json, sha256, tree_hash, write_json

INPUTS = HERE / "inputs"
MAX_FILE = 2 * 1024 * 1024
HEAD_LINES, TAIL_LINES = 300, 300
SKIP_DIRS = {"build", "target", "states", "node_modules", "__pycache__", ".gradle", ".m2", ".cargo",
             ".git", "tmp", ".cache", ".pytest_cache"}
BINARY = re.compile(r"\.(bin|jar|class|o|a|so|rlib|rmeta|d|zip|gz|tgz|xz|tar|pyc|fp|st|ser)$", re.I)
TEXT_LOG = re.compile(r"\.(log|out|txt)$", re.I)
TTRACE = re.compile(r"_TTrace_\d+\.(tla|bin)$")
INPUT_FILES = ("case.json", "task.md", "model-scope.md", "final-schema.json", "input-manifest.json")


def git(repo: Path, *args: str) -> str:
    done = subprocess.run(["git", "-C", str(repo), *args], text=True, stdout=subprocess.PIPE,
                          stderr=subprocess.DEVNULL, errors="replace")
    return done.stdout


MANIFESTS = ("pom.xml", "Cargo.toml", "go.mod", "build.gradle", "CMakeLists.txt", "Makefile")


def is_snapshot(d: Path) -> bool:
    return (d / ".git").exists()


def artifact_top(src: Path) -> set[str]:
    art = src / "artifact"
    return {p.name for p in art.iterdir() if p.name != ".git"} if art.is_dir() else set()


def is_source_copy(d: Path, top: set[str]) -> bool:
    """A copy of the upstream tree without its own .git: a build manifest at the root and a root
    listing that mostly matches the artifact repository's."""
    if not top or not any((d / m).is_file() for m in MANIFESTS):
        return False
    names = {p.name for p in d.iterdir()}
    return len(names & top) >= max(3, len(top) // 2)


def copy_diff(d: Path, artifact: Path) -> tuple[str, str]:
    """Diff a source copy against the artifact's baseline and update commits; return the smaller."""
    best = ("", "")
    for commit in ("HEAD~1", "HEAD"):
        rev = git(artifact, "rev-parse", "--short", commit).strip()
        if not rev:
            continue
        idx = d.parent / f".export-index-{os.getpid()}"
        env = dict(os.environ, GIT_INDEX_FILE=str(idx), GIT_DIR=str(artifact / ".git"), GIT_WORK_TREE=str(d))
        try:
            subprocess.run(["git", "read-tree", rev], env=env, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            diff = subprocess.run(["git", "-c", "core.quotepath=off", "diff", "--binary"], env=env, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, errors="replace").stdout
            others = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "-z"], env=env, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, errors="replace").stdout
        finally:
            idx.unlink(missing_ok=True)
        for rel in others.split("\0"):
            if not rel or any(part in SKIP_DIRS for part in Path(rel).parts):
                continue
            f = d / rel
            if f.is_file() and f.stat().st_size <= MAX_FILE and not BINARY.search(rel):
                diff += subprocess.run(["git", "diff", "--no-index", "--", "/dev/null", str(f)], text=True,
                                       stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, errors="replace").stdout
        if not best[0] or len(diff) < len(best[1]):
            best = (f"{commit} ({rev})", diff)
    return best


def snapshot_diff(repo: Path) -> str:
    """Tracked changes against HEAD plus untracked files, as one patch."""
    out = git(repo, "-c", "core.quotepath=off", "diff", "--binary", "HEAD")
    for rel in git(repo, "ls-files", "--others", "--exclude-standard", "-z").split("\0"):
        if not rel or any(part in SKIP_DIRS for part in Path(rel).parts):
            continue
        f = repo / rel
        if f.is_file() and f.stat().st_size <= MAX_FILE and not BINARY.search(rel):
            done = subprocess.run(["git", "-C", str(repo), "diff", "--no-index", "--", "/dev/null", rel],
                                  text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, errors="replace")
            out += done.stdout
    return out


NOISE = ("CostModel lookup failed",)


def trim_tlc(text: str) -> str:
    """Drop per-state variable dumps and TLC profiler noise; keep statistics, coverage and actions."""
    return "".join(l for l in text.splitlines(keepends=True)
                   if not l.startswith(("/\\", " ", "\t")) and not l.startswith(NOISE))


def cut(text: str) -> str:
    lines = text.splitlines(keepends=True)
    if len(lines) <= HEAD_LINES + TAIL_LINES:
        return text[:MAX_FILE // 2] + "\n[export: cut]\n" + text[-MAX_FILE // 2:]
    omitted = len(lines) - HEAD_LINES - TAIL_LINES
    return "".join(lines[:HEAD_LINES]) + f"\n[export: {omitted} lines cut]\n\n" + "".join(lines[-TAIL_LINES:])


def copy_output(src: Path, dst: Path, record: dict) -> None:
    top = artifact_top(src)
    for root, dirs, files in os.walk(src):
        root_p = Path(root)
        rel_root = root_p.relative_to(src)
        keep = []
        for d in sorted(dirs):
            p = root_p / d
            rel = (rel_root / d).as_posix()
            if d in SKIP_DIRS or p.is_symlink():
                record["skipped"].append({"path": rel + "/", "reason": "dir"})
            elif is_snapshot(p):
                record["snapshots"].append(rel)
            elif is_source_copy(p, top):
                record["copies"].append(rel)
            else:
                keep.append(d)
        dirs[:] = keep
        for name in sorted(files):
            p = root_p / name
            rel = (rel_root / name).as_posix()
            if p.is_symlink() or not p.is_file():
                record["skipped"].append({"path": rel, "reason": "symlink/special"})
                continue
            size = p.stat().st_size
            if BINARY.search(name) or TTRACE.search(name):
                record["skipped"].append({"path": rel, "reason": "binary/ttrace", "bytes": size})
                continue
            target = dst / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            if not TEXT_LOG.search(name) and size <= MAX_FILE:
                shutil.copy2(p, target)
                continue
            data = p.read_bytes()
            if b"\0" in data[:8192]:
                record["skipped"].append({"path": rel, "reason": "binary", "bytes": size})
                continue
            text = data.decode("utf-8", errors="replace")
            how = []
            if TEXT_LOG.search(name) and "TLC2 Version" in text[:4096]:
                text = trim_tlc(text)
                how.append("tlc-trim")
            if len(text.encode()) > MAX_FILE:
                text = cut(text)
                how.append("cut")
            target.write_text(text, encoding="utf-8")
            if target.stat().st_size < size:
                record["trimmed"].append({"path": rel, "how": "+".join(how), "bytes": size,
                                          "kept": target.stat().st_size, "sha256": sha256(p)})


def summarize_tool(c: dict) -> str:
    inp = c.get("input") or {}
    name = c.get("name", "?")
    if "command" in inp:
        s = inp["command"]
    elif "file_path" in inp:
        s = inp["file_path"]
    elif "pattern" in inp:
        s = f'{inp.get("pattern")} {inp.get("path", "")}'
    else:
        s = json.dumps(inp, ensure_ascii=False)
    s = " ".join(str(s).split())
    return f"`{name}` {s[:240]}{'…' if len(s) > 240 else ''}"


VIOL = re.compile(r"(?:Invariant|Property|Temporal properties?)\s+(\w+)?\s*(?:is|was|were)\s+violated", re.I)


def timeline(activity: Path) -> str:
    out = ["# Timeline\n", "Generated by export.py from log/activity.jsonl: agent messages in full, one line per "
           "tool call, and TLC violations seen in tool results. The full log is archived outside git.\n"]
    turn = 0
    for line in activity.open(encoding="utf-8", errors="replace"):
        if not line.strip().startswith("{"):
            continue
        e = json.loads(line)
        if e.get("type") == "assistant":
            turn += 1
            for c in e["message"].get("content", []) or []:
                if c.get("type") == "text" and c.get("text", "").strip():
                    out.append(f"\n**[{turn}]** {c['text'].strip()}\n")
                elif c.get("type") == "tool_use":
                    out.append(f"- [{turn}] {summarize_tool(c)}")
        elif e.get("type") == "user":
            for c in e["message"].get("content", []) or []:
                if isinstance(c, dict) and c.get("type") == "tool_result":
                    s = json.dumps(c.get("content"), ensure_ascii=False)
                    props = sorted({m.group(1) or "?" for m in VIOL.finditer(s)})
                    if props:
                        out.append(f"  - ⚠ violated: {', '.join(props)}")
        elif e.get("type") == "result":
            out.append(f"\n**[result]** subtype={e.get('subtype')} cost={e.get('total_cost_usd')} "
                       f"turns={e.get('num_turns')}\n")
    return "\n".join(out) + "\n"


def export_run(arm: str, case: str, rep: str) -> dict | None:
    att = WORK / "attempts" / arm / case / f"r{rep}"
    out_dir = read_json(att / "attempt.json").get("output_dir", ".specula-output") \
        if (att / "attempt.json").is_file() else ".specula-output"
    src = att / "ws" / "current" / out_dir
    res = RESULTS / arm / case / f"r{rep}"
    if not src.is_dir() or not (res / "run.json").is_file():
        return None
    for old in ("output", "instrumentation", "partial"):
        if (res / old).exists():
            shutil.rmtree(res / old)
    record = {"source": str(src.relative_to(WORK)), "skipped": [], "trimmed": [], "snapshots": [],
              "copies": [], "instrumentation": {}}
    copy_output(src, res / "output", record)
    for rel in record["snapshots"]:
        repo = src / rel
        diff = snapshot_diff(repo)
        head = git(repo, "log", "--oneline", "-1").strip()
        entry = {"head": head, "bytes": len(diff.encode())}
        if diff.strip():
            name = rel.replace("/", "__") + ".diff"
            if len(diff.encode()) > MAX_FILE:
                diff = cut(diff)
                entry["cut"] = True
            (res / "instrumentation").mkdir(parents=True, exist_ok=True)
            (res / "instrumentation" / name).write_text(diff, encoding="utf-8")
            entry["file"] = f"instrumentation/{name}"
        record["instrumentation"][rel] = entry
    for rel in record["copies"]:
        base, diff = copy_diff(src / rel, src / "artifact")
        entry = {"against": f"artifact {base}", "bytes": len(diff.encode())}
        if diff.strip():
            name = rel.replace("/", "__") + ".diff"
            if len(diff.encode()) > MAX_FILE:
                diff = cut(diff)
                entry["cut"] = True
            (res / "instrumentation").mkdir(parents=True, exist_ok=True)
            (res / "instrumentation" / name).write_text(diff, encoding="utf-8")
            entry["file"] = f"instrumentation/{name}"
        record["instrumentation"][rel] = entry
    act = att / "log" / "activity.jsonl"
    if act.is_file():
        (res / "timeline.md").write_text(timeline(act), encoding="utf-8")
        record["activity_sha256"] = sha256(act)
        record["activity_bytes"] = act.stat().st_size
    record["output_tree_sha256"] = tree_hash(res / "output")
    write_json(res / "export.json", record)
    return record


def export_inputs(case: str) -> None:
    dest = INPUTS / case
    dest.mkdir(parents=True, exist_ok=True)
    seen: dict[str, str] = {}
    for arm in ARMS:
        ws = WORK / "attempts" / arm / case / "r1" / "ws"
        if not ws.is_dir():
            continue
        for name in INPUT_FILES:
            f = ws / name
            if not f.is_file():
                continue
            h = sha256(f)
            if name == "input-manifest.json":
                shutil.copy2(f, dest / f"input-manifest.{arm}.json")
            elif name not in seen:
                shutil.copy2(f, dest / name)
                seen[name] = h
            elif seen[name] != h:
                shutil.copy2(f, dest / f"{Path(name).stem}.{arm}{Path(name).suffix}")
        prev = next((ws / "previous" / d for d in (".specula-output", ".specular-output")
                     if (ws / "previous" / d).is_dir()), ws / "previous" / ".specula-output")
        if prev.is_dir():
            (dest / f"previous.{arm}.sha256").write_text(tree_hash(prev) + "\n")
    v0 = V0_ROOT / case / ".specula-output"
    if v0.is_dir():
        (dest / "v0-suite.sha256").write_text(tree_hash(v0) + "\n")
    ann = WORK / "annotated" / case
    if ann.is_dir():
        if (dest / "annotated").exists():
            shutil.rmtree(dest / "annotated")
        shutil.copytree(ann, dest / "annotated")
        for step in ("1-annotate", "2-review"):
            chk = WORK / "annotate" / case / step / "check.json"
            if chk.is_file():
                shutil.copy2(chk, dest / "annotated" / f"{step}-check.json")
    (dest / "README.md").write_text(
        f"# Inputs of {case}\n\n"
        "- `case.json`, `task.md`, `model-scope.md`, `final-schema.json`: the neutral task every arm received "
        "(a file suffixed `.<arm>` differs for that arm).\n"
        "- `input-manifest.<arm>.json`: the sandbox input map of that arm's r1 workspace.\n"
        f"- Prior suite of v0/v1: `../../../blind-incremental-bugs/blind-incremental-v0/{case}/.specula-output/` "
        "(tree hash in `v0-suite.sha256`; `previous.<arm>.sha256` is the hash of what each arm actually got).\n"
        "- `annotated/`: v2's prior suite (`spec/`, comments only) with the annotation and review reports, "
        "frozen before any v2 run.\n", encoding="utf-8")


def export_skills() -> None:
    dest = INPUTS / "skills"
    dest.mkdir(parents=True, exist_ok=True)
    for arm in ARMS:
        m = WORK / "skills" / arm / "manifest.json"
        if m.is_file():
            shutil.copy2(m, dest / f"{arm}-manifest.json")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("what", choices=["runs", "inputs", "all"])
    ap.add_argument("--arm", action="append")
    ap.add_argument("--case", action="append")
    ap.add_argument("--rep", default="1")
    a = ap.parse_args()
    arms = a.arm or list(ARMS)
    cases = a.case or sorted(p.name for p in (WORK / "attempts" / "v0").iterdir())
    if a.what in ("inputs", "all"):
        export_skills()
        for c in cases:
            export_inputs(c)
            print(f"inputs {c}")
    if a.what in ("runs", "all"):
        for arm in arms:
            for c in cases:
                r = export_run(arm, c, a.rep)
                if r is None:
                    continue
                size = sum(f.stat().st_size for f in (RESULTS / arm / c / f"r{a.rep}").rglob("*") if f.is_file())
                print(f"{arm} {c}: {size / 1e6:.1f} MB, skipped {len(r['skipped'])}, trimmed {len(r['trimmed'])}, "
                      f"snapshots {len(r['snapshots'])}+{len(r['copies'])}, diffs {sum(1 for e in r['instrumentation'].values() if 'file' in e)}")


if __name__ == "__main__":
    main()
