#!/usr/bin/env python3
"""Tabulate TLC runs from spec/output/mc-*.log (markdown)."""
import glob, os, re, sys
root = "/work/current/.specula-output/spec/output"
rows = []
for f in sorted(glob.glob(os.path.join(root, "mc-*.log"))):
    t = open(f, errors="replace").read()
    tag = os.path.basename(f)[3:-4]
    cmd = re.search(r"# cmd: .*?-config (\S+)", t)
    cfg = cmd.group(1) if cmd else ("(see log)")
    sim = "-simulate" in (cmd.group(0) if cmd else "") or "simulate" in t[:400]
    viol = re.findall(r"(Invariant \w+ is violated|Action property \w+ is violated|Temporal properties were violated)", t)
    done = "Model checking completed. No error has been found." in t
    ds = re.findall(r"([\d,]+) distinct states found", t)
    q = re.findall(r"([\d,]+) states left on queue", t)
    gen = re.findall(r"([\d,]+) states generated", t)
    depth = re.findall(r"depth of the complete state graph search is (\d+)", t)
    trace_len = re.findall(r"The (?:maximum|average) height of the trace", t)
    mean = re.search(r"The number of states generated: ([\d,]+)", t)
    if "# start:" in t and "# exit:" not in t:
        res = "interrupted (tool timeout; superseded by a later run)"
    elif viol:
        res = "VIOLATION: " + viol[0].split()[1]
    elif done and q and q[-1] == "0":
        res = "complete (queue 0), no error"
    elif done and sim:
        res = "simulation time-bounded, no error (LIMITED_COVERAGE)"
    elif re.search(r"exit: 0", t) or "Stopping TLC" in t or "Exploring the state space has been stopped" in t or q:
        res = "time-bounded, no error (LIMITED_COVERAGE)"
    else:
        res = "see log"
    rows.append((tag, cfg, "sim" if sim else "bfs", ds[-1] if ds else (mean.group(1) if mean else (gen[-1] if gen else "-")), q[-1] if q else "-", depth[-1] if depth else "-", res))
print("| run | cfg | mode | distinct states (sim: generated) | queue | depth | result |")
print("|---|---|---|---|---|---|---|")
for r in rows:
    print("| " + " | ".join(r) + " |")
