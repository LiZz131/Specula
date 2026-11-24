#!/usr/bin/env python3
"""Check whether scenario-precondition predicates are reached in a run's own configs.

    python3 run_census.py <arm> <case> [--seconds 120 --retry-seconds 240 --jobs 2]

Inputs (written by hand, strictly from the agent's own wording):
    probes/<arm>/<case>/CensusProbes.tla   a module that EXTENDS one of the arm's modules and defines one
                                           state predicate per declared item, named SC_<item>. No actions.
    probes/<arm>/<case>/plan.json          {"configs": [{"name": "Update_full.cfg",
                                                         "extends": "Update",
                                                         "probes": ["SC_U1", "SC_U2"]}, ...]}

For each planned config this copies results/<arm>/<case>/r1/output/spec to a scratch directory under
/mydata/bingzhuo/evidence-work/census/<arm>/<case>/, adds CensusProbes.tla and the probe module that
update-coverage/check.py generates (EXTENDS <extends>, CensusProbes, TLC), and runs check.py's own
run_config: the config's INVARIANT/PROPERTY sections are dropped (nothing is checked, nothing stops
the run), an ACTION_CONSTRAINT records the first state in which each probe holds (for a state
predicate P, ENABLED P = P), and TLC simulates at depth 100 with one worker. A config in which some
probe is not reached gets a second pass of --retry-seconds with seed+1 (as check.py retries).

Output: runs/<arm>/<case>/result.json and runs/<arm>/<case>/logs/<cfg>.log (trimmed TLC log).
The scratch directory is removed after each run (no states/ or TTrace files are kept).
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
INV = HERE.parents[2]
import sys

sys.path.insert(0, str(INV.parent / "update-coverage"))
import check  # noqa: E402

WORK = Path("/mydata/bingzhuo/evidence-work/census")
TLA2TOOLS = os.environ.get("TLA2TOOLS", "/mydata/bingzhuo/src/Specula/lib/tla2tools.jar")


def trim(text: str) -> str:
    lines = text.splitlines()
    keep = set(range(min(25, len(lines)))) | set(range(max(0, len(lines) - 25), len(lines)))
    keep |= {i for i, line in enumerate(lines) if "update-coverage" in line or line.startswith("Error")}
    out, last = [], -1
    for i in sorted(keep):
        if i != last + 1:
            out.append("[... trimmed ...]")
        out.append(lines[i][:400])
        last = i
    return "\n".join(out) + "\n"


def run_one(spec: Path, scratch: Path, preds: Path, cfg: dict, seconds: int, depth: int, seed: int,
            heap: str, jars: str, logdir: Path, state: dict) -> dict:
    probes = [check.Probe(i + 1, "census", name, name) for i, name in enumerate(cfg["probes"])]
    checks, body = check.split_config((spec / cfg["name"]).read_text())
    work = scratch / f"{cfg['name']}.seed{seed}"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    try:
        for path in spec.glob("*.tla"):
            shutil.copy(path, work / path.name)
        shutil.copy(preds, work / "CensusProbes.tla")
        extends = cfg["extends"] if cfg["extends"] == "CensusProbes" else f"{cfg['extends']}, CensusProbes"
        (work / f"{check.PROBE_MODULE}.tla").write_text(check.probe_module(probes, extends))
        (work / "probe.cfg").write_text(body + "ACTION_CONSTRAINT UCAll\nCHECK_DEADLOCK FALSE\n")
        command = ["java", f"-Xmx{heap}", "-XX:+UseParallelGC", "-Dtlc2.TLC.progressInterval=10", "-cp", jars,
                   "tlc2.TLC", "-simulate", "-depth", str(depth), "-seed", str(seed), "-workers", "1",
                   "-nowarning", "-config", "probe.cfg", check.PROBE_MODULE]
        started = time.monotonic()
        with (work / "tlc.log").open("w") as log:
            proc = subprocess.Popen(command, cwd=work, stdout=log, stderr=subprocess.STDOUT)
            try:
                proc.wait(timeout=seconds)
                timed_out = False
            except subprocess.TimeoutExpired:
                timed_out = True
                proc.send_signal(signal.SIGINT)
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()
        text = (work / "tlc.log").read_text(errors="replace")
        (logdir / f"{cfg['name']}.seed{seed}.log").write_text(trim(text))
        flat = re.sub(r"\s+", " ", text)
        hit = {int(k) for k in re.findall(r'<< ?"update-coverage(?:-enabled)?", (\d+) ?>>', flat)}
        traces = re.findall(r"([\d,]+) traces generated", text)
        errors = [i for i, line in enumerate(text.splitlines()) if line.startswith("Error:")]
        status = ("error: " + " ".join(text.splitlines()[errors[0]:errors[0] + 3])[6:].strip()) if errors \
            else ("budget used" if timed_out else "finished")
        rec = state.setdefault(cfg["name"], {"extends": cfg["extends"], "checks": checks, "passes": [],
                                             "reached": []})
        rec["passes"].append({"seed": seed, "seconds": round(time.monotonic() - started, 1), "status": status,
                              "traces": int(traces[-1].replace(",", "")) if traces else None})
        rec["reached"] = sorted(set(rec["reached"]) | {cfg["probes"][k - 1] for k in hit})
        rec["probes"] = cfg["probes"]
        return rec
    finally:
        shutil.rmtree(work, ignore_errors=True)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("arm")
    ap.add_argument("case")
    ap.add_argument("--seconds", type=int, default=120)
    ap.add_argument("--retry-seconds", type=int, default=240)
    ap.add_argument("--depth", type=int, default=100)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--jobs", type=int, default=2)
    ap.add_argument("--heap", default="3g")
    ap.add_argument("--only", action="append", default=[], help="run only these cfg names")
    a = ap.parse_args()
    spec = INV / "results" / a.arm / a.case / "r1" / "output" / "spec"
    pdir = HERE / "probes" / a.arm / a.case
    plan = json.loads((pdir / "plan.json").read_text())
    cfgs = [c for c in plan["configs"] if not a.only or c["name"] in a.only]
    out = HERE / "runs" / a.arm / a.case
    logdir = out / "logs"
    logdir.mkdir(parents=True, exist_ok=True)
    scratch = WORK / a.arm / a.case
    scratch.mkdir(parents=True, exist_ok=True)
    jars = f"{TLA2TOOLS}:/mydata/bingzhuo/inv-e2e/attempts/{a.arm}/{a.case}/r1/ws/lib/CommunityModules-deps.jar"
    result_path = out / "result.json"
    state = json.loads(result_path.read_text())["configs"] if (a.only and result_path.exists()) else {}
    for c in cfgs:
        state.pop(c["name"], None)

    def batch(items, seconds, seed):
        with concurrent.futures.ThreadPoolExecutor(max_workers=a.jobs) as pool:
            futs = [pool.submit(run_one, spec, scratch, pdir / "CensusProbes.tla", c, seconds, a.depth, seed,
                                a.heap, jars, logdir, state) for c in items]
            for c, f in zip(items, futs):
                rec = f.result()
                print(f"{a.arm}/{a.case} {c['name']} seed{seed}: {rec['passes'][-1]['status']}, "
                      f"reached {rec['reached']} of {c['probes']}", flush=True)

    batch(cfgs, a.seconds, a.seed)
    retry = [c for c in cfgs if not state[c["name"]]["passes"][-1]["status"].startswith("error")
             and set(c["probes"]) - set(state[c["name"]]["reached"])]
    if retry and a.retry_seconds:
        batch(retry, a.retry_seconds, a.seed + 1)
    for name, rec in state.items():
        rec["not_reached"] = sorted(set(rec["probes"]) - set(rec["reached"]))
    result_path.write_text(json.dumps({"arm": a.arm, "case": a.case, "depth": a.depth, "configs": state},
                                      indent=2) + "\n")


if __name__ == "__main__":
    main()
