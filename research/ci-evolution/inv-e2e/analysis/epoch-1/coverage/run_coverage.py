#!/usr/bin/env python3
"""Run update-coverage/check.py on the final spec of an epoch-1 run, unchanged except for two adaptations.

    python3 run_coverage.py <arm> <case> [--seconds 120 --retry-seconds 240 --jobs 16]

1. Config discovery: every MC*.cfg and Update*.cfg (epoch-1 suites also use MC-x.cfg and Update-x.cfg,
   which check.py's MC.cfg / MC_* / Update_* patterns miss).
2. Module per config: the probe module EXTENDS the module whose EXTENDS closure defines every
   operator the cfg names (SPECIFICATION, INIT, NEXT, CONSTRAINT, VIEW, SYMMETRY, `<-` substitutions)
   and includes Update (where AffectedActions lives); the smallest such closure wins. A cfg with no
   such module (base.cfg, Trace.cfg, old-model cfgs) is skipped and listed in skipped.json. If TLC then
   reports an unassigned constant (Update.tla declaring scenario constants an MC cfg does not set), the
   config is rerun on MC, which suffices when the probes use only MC's definitions.
3. Reachability canaries are left out of the gap report by name (--ignore).

    python3 run_coverage.py --rebuild     # rebuild every out/*/*/report.md with the current --ignore

Everything else (probes from AffectedActions, simulation, retry, report) is check.py's own code.
Output: out/<arm>/<case>/report.{md,json}, skipped.json.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
INV = HERE.parents[2]
SPECULA = INV.parents[2]
sys.path.insert(0, str(INV.parent / "update-coverage"))
import check  # noqa: E402

DEF = re.compile(r"^([A-Za-z_]\w*)\s*(\([^)]*\))?\s*==", re.M)


def modules(spec: Path) -> dict[str, tuple[set[str], list[str]]]:
    out = {}
    for p in spec.glob("*.tla"):
        text = check.strip_comments(p.read_text(errors="replace"))
        m = re.search(r"^\s*EXTENDS\s+([^\n]+)", text, re.M)
        ext = [w.strip() for w in m.group(1).split(",")] if m else []
        out[p.stem] = ({d for d, _ in DEF.findall(text)} | set(re.findall(r"^\s*(?:CONSTANTS?|VARIABLES?)\s+([^\n]+)", text, re.M) and []), ext)
    return out


def closure(name: str, mods: dict) -> set[str]:
    seen, todo = set(), [name]
    while todo:
        n = todo.pop()
        if n in seen or n not in mods:
            continue
        seen.add(n)
        todo += mods[n][1]
    return seen


def cfg_names(text: str) -> set[str]:
    text = check.strip_comments(text)
    names = set()
    for kw in ("SPECIFICATION", "INIT", "NEXT", "CONSTRAINT", "CONSTRAINTS", "ACTION_CONSTRAINT", "VIEW", "SYMMETRY"):
        for m in re.finditer(rf"^\s*{kw}\s+([^\n]+)", text, re.M):
            names |= set(re.findall(r"[A-Za-z_]\w*", m.group(1)))
    names |= set(re.findall(r"<-\s*([A-Za-z_]\w*)", text))
    return names


def pick_module(cfg: Path, mods: dict) -> str | None:
    need = cfg_names(cfg.read_text(errors="replace"))
    best = None
    for name in mods:
        clo = closure(name, mods)
        if "Update" not in clo:
            continue
        defined = set().union(*(mods[m][0] for m in clo))
        if need <= defined and (best is None or len(clo) < best[1]):
            best = (name, len(clo))
    return best[0] if best else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("arm", nargs="?")
    ap.add_argument("case", nargs="?")
    ap.add_argument("--rebuild", action="store_true")
    ap.add_argument("--seconds", type=int, default=120)
    ap.add_argument("--retry-seconds", type=int, default=240)
    ap.add_argument("--depth", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=16)
    ap.add_argument("--heap", default="3g")
    ap.add_argument("--ignore", default=r"(?i)canary|NotReach|NeverReach|NotAppended|Reachable|Witness")
    a = ap.parse_args()
    if a.rebuild:
        for rep in sorted(HERE.glob("out/*/*/report.json")):
            record = json.loads(rep.read_text())
            probes = [check.Probe(**{**p, "label": check.probe_label(p["formula"])}) for p in record["probes"]]
            configs = [check.Config(**c) for c in record["configs"]]
            check.write(argparse.Namespace(out=rep.parent, ignore=a.ignore), record["spec"],
                        {**record["settings"], "ignore": a.ignore}, probes, configs)
        return
    spec = INV / "results" / a.arm / a.case / "r1" / "output" / "spec"
    out = HERE / "out" / a.arm / a.case
    out.mkdir(parents=True, exist_ok=True)
    mods = modules(spec)
    probes = check.affected_probes(spec / "Update.tla", "AffectedActions")
    configs, skipped = [], []
    for p in sorted(set(spec.glob("MC*.cfg")) | set(spec.glob("Update*.cfg"))):
        m = pick_module(p, mods)
        (configs.append(check.Config(p.name, m)) if m else skipped.append(p.name))
    (out / "skipped.json").write_text(json.dumps({"skipped": skipped,
        "modules": {c.name: c.module for c in configs}}, indent=2) + "\n")
    jars = f"{os.environ.get('TLA2TOOLS', SPECULA / 'lib/tla2tools.jar')}:" \
           f"{os.environ.get('COMMUNITY_MODULES', f'/mydata/bingzhuo/inv-e2e/attempts/{a.arm}/{a.case}/r1/ws/lib/CommunityModules-deps.jar')}"

    def run_all(batch, seconds, seed):
        with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
            futs = [pool.submit(check.run_config, spec, c, probes, c.module, seconds, a.depth, seed, a.heap, jars) for c in batch]
            for f in concurrent.futures.as_completed(futs):
                d = f.result()
                print(f"{a.arm}/{a.case} {d.name} [{d.module}]: {d.status}, reached {len(d.taken)}/{len(probes)}", flush=True)

    run_all(configs, a.seconds, a.seed)
    fallback = [c for c in configs if "is not assigned a value" in c.status and c.module != "MC"
                and (spec / "MC.tla").is_file()]
    for c in fallback:
        c.module, c.status, c.seconds = "MC", "not run", None
    if fallback:
        run_all(fallback, a.seconds, a.seed)
    first = check.analyse(probes, configs, a.ignore)
    behind = {n for g in first["gaps"] for n in g["configs"]}
    retry = [c for c in configs if c.name in behind]
    for c in retry:
        c.retried = True
    if retry and a.retry_seconds:
        run_all(retry, a.retry_seconds, a.seed + 1)
    args = argparse.Namespace(out=out, ignore=a.ignore)
    settings = {"actions": "Update.tla:AffectedActions", "seconds": a.seconds, "retry_seconds": a.retry_seconds,
                "depth": a.depth, "seed": a.seed, "heap": a.heap, "wrapper": "run_coverage.py"}
    check.write(args, f"results/{a.arm}/{a.case}/r1/output/spec", settings, probes, configs)


if __name__ == "__main__":
    main()
