#!/usr/bin/env python3
"""Archive what export.py leaves out of git to durable storage (re-runnable).

    python3 archive.py --epoch epoch-1 [--dest /proj/aiopslab-PG0/specula-ci/inv-e2e] [--force]

DEST/<epoch>/ receives:
- logs/: every session log (activity.jsonl, command.json, run-manifest.json, stderr.log) and
  attempt.json of the runs, the annotation sessions and the invalid attempts, plus the pipeline
  logs and decision records at the top of WORK. Copied with rsync, so reruns add only what is new.
- workspaces/<arm>-<case>-r<N>.tar.zst: the run's /work minus build and TLC-state directories and
  the read-only inputs that materialize.py/prepare.py regenerate (lib, new-source, old-source,
  skills, tools). Source trees the agent edited are kept whole, with their .git.
- workspaces/annotate-<case>-<step>.tar.zst: the annotation and review workspaces' out/.
- MANIFEST.json: size and sha256 of every tarball.

Regenerable and not archived: neutral/ build caches, subjects/, history/, repos/, skills/.
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path

from common import WORK, sha256, write_json

EXCLUDES = ["target", "build", "states", "node_modules", ".gradle", ".m2", ".cargo", "__pycache__",
            "*.fp", "./lib", "./new-source", "./old-source", "./.agents", "./tools", "./.cache"]
LOG_FILTER = ["--include=*/", "--include=attempt.json", "--include=invalid.json", "--include=check.json",
              "--include=log/**", "--exclude=*"]


def sh(args: list[str]) -> None:
    subprocess.run(args, check=True)


def tar(src: Path, out: Path, force: bool) -> None:
    if out.exists() and not force:
        return
    tmp = out.with_suffix(out.suffix + ".part")
    args = ["tar", "-C", str(src), "-I", "zstd -T0 -10"]
    args += [f"--exclude={e}" for e in EXCLUDES]
    sh(args + ["-cf", str(tmp), "."])
    tmp.rename(out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--epoch", required=True)
    ap.add_argument("--dest", default="/proj/aiopslab-PG0/specula-ci/inv-e2e")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    root = Path(a.dest) / a.epoch
    (root / "logs").mkdir(parents=True, exist_ok=True)
    (root / "workspaces").mkdir(parents=True, exist_ok=True)

    for sub in ("attempts", "annotate", "invalid"):
        if (WORK / sub).is_dir():
            sh(["rsync", "-a", "-m", *LOG_FILTER, f"{WORK / sub}/", f"{root / 'logs' / sub}/"])
    top = [str(p) for p in WORK.iterdir() if p.is_file() and p.suffix in (".log", ".md", ".out", ".py", ".json")]
    sh(["rsync", "-a", *top, f"{root / 'logs'}/"])

    for ws in sorted(WORK.glob("attempts/*/*/r*/ws")):
        arm, case, rep = ws.parts[-4:-1]
        tar(ws.resolve(), root / "workspaces" / f"{arm}-{case}-{rep}.tar.zst", a.force)
        print("workspace", arm, case, rep, flush=True)
    for out in sorted(WORK.glob("annotate/*/*/ws/out")):
        case, step = out.parts[-4:-2]
        tar(out, root / "workspaces" / f"annotate-{case}-{step}.tar.zst", a.force)
    for d in sorted(WORK.glob("invalid/*/")):
        # retire_incremental_attempt.py moves the workspace to ws-physical; ws is then a dangling link.
        ws = next((p for p in (d / "ws-physical", d / "ws") if p.exists()), None)
        if ws is not None:
            tar(ws.resolve(), root / "workspaces" / f"invalid-{d.name}.tar.zst", a.force)

    manifest = {p.name: {"bytes": p.stat().st_size, "sha256": sha256(p)}
                for p in sorted((root / "workspaces").glob("*.tar.zst"))}
    write_json(root / "MANIFEST.json", {"work": str(WORK), "workspaces": manifest})
    total = sum(v["bytes"] for v in manifest.values())
    print(f"{len(manifest)} tarballs, {total / 1e9:.2f} GB -> {root}")


if __name__ == "__main__":
    main()
