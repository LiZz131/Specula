#!/usr/bin/env python3
"""Tabulate every TLC model-checking/simulation log in spec/output (excluding trace validation)."""
import re, sys, pathlib
out = pathlib.Path(sys.argv[1]) / "spec/output"
rows = []
for log in sorted(out.glob("*.log")):
    t = log.read_text(errors="replace")
    if not t.startswith("# cmd:") or "Trace.tla" in t.split("\n")[0]: continue
    cmd = t.split("\n")[0]
    cfg = re.search(r"-config (\S+)", cmd).group(1)
    mod = cmd.split()[-1]
    mode = "simulation" if "-simulate" in cmd else "BFS"
    stop = re.search(r"stopAfter=(\d+)", cmd); stop = stop.group(1) + "s" if stop else "-"
    viol = re.search(r"Error: (.*?is violated)\.", t)
    dead = "Deadlock reached" in t
    gen = re.findall(r"([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue", t)
    depth = re.findall(r"The depth of the complete state graph search is (\d+)", t)
    simstat = re.findall(r"(\d+) states checked, (\d+) traces generated \(trace length: mean=(\d+)", t)
    simfin = re.findall(r"The number of states generated: (\d+)", t)
    cex = len(re.findall(r"^State \d+:", t, re.M))
    if viol: res = viol.group(1) + f" (trace {cex} states)"
    elif dead: res = "deadlock (counter exhaustion)"
    elif "No error has been found" in t: res = "no violation"
    elif mode == "simulation" and re.search(r"# exit: 0 ", t): res = "no violation"
    else: res = "incomplete"
    if mode == "BFS" and gen:
        g, d, q = gen[-1]; stats = f"gen {g}; distinct {d}; queue {q}; depth {depth[-1] if depth else '?'}"
        budget = "exhausted" if q == "0" else ("budget-limited" if not viol else "stopped at violation")
    else:
        s = simfin[-1] if simfin else (simstat[-1][0] if simstat else "?")
        tr = simstat[-1][1] if simstat else "?"
        stats = f"states {s}; traces {tr}"
        budget = "budget-limited" if not viol else "stopped at violation"
    rows.append((log.name, mod, cfg, mode, stop, res, stats, budget))
print("| Log | Module | Config | Mode | Budget | Result | Statistics | Coverage |")
print("|---|---|---|---|---|---|---|---|")
for r in rows: print("| " + " | ".join(r) + " |")
