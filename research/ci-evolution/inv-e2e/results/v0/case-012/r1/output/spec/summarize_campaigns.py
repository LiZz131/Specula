#!/usr/bin/env python3
"""Tabulate TLC campaign logs in spec/output/ (written by run_tlc.sh)."""
import re, sys, pathlib
out = pathlib.Path(__file__).resolve().parent / "output"
runs = sys.argv[1:]
print("| Run | Module / cfg | Mode | Elapsed | Distinct states | Queue left | Depth | Outcome |")
print("|---|---|---|---:|---:|---:|---:|---|")
for tag in runs:
    p = out / f"{tag}.log"
    if not p.exists():
        print(f"| {tag} | (missing) | | | | | | NOT RUN |"); continue
    t = p.read_text(errors="replace")
    cmd = re.search(r"CMD: (\S+) -config (\S+) -workers (\d+)(.*)\(outer", t)
    mod, cfg, extra = (cmd.group(1), cmd.group(2), cmd.group(4).strip()) if cmd else ("?", "?", "")
    sim = "-simulate" in extra
    el = re.search(r"EXIT: rc=(\d+) elapsed=(\d+)s", t)
    rc, secs = (int(el.group(1)), int(el.group(2))) if el else (None, None)
    st = re.findall(r"([\d,]+) states generated(?:[^,\n]*)?, ([\d,]+) distinct states found, ([\d,]+) states left on queue", t)
    distinct = st[-1][1] if st else ""
    queue = st[-1][2] if st else ""
    if sim:
        g = re.findall(r"([\d,]+) states generated|The number of states generated: ([\d,]+)", t)
        tr = re.findall(r"([\d,]+) traces? (?:generated|checked)|traces generated: ([\d,]+)|average length of ([\d.,]+)", t)
        n = [x for pair in g for x in pair if x]
        trc = re.findall(r"([\d]+) traces generated \(trace length: mean=(\d+)", t)
        distinct = (n[-1] + " states checked" + (f", {trc[-1][0]} traces (mean len {trc[-1][1]})" if trc else "")) if n else ""
        queue = "n/a"
    depth = re.findall(r"depth of the complete state graph search is (\d+)", t)
    depth = depth[-1] if depth else ("100 (sim)" if sim else "")
    viol = re.search(r"Error: (Invariant (\w+) is violated|Action property (\w+).*violated|Temporal properties were violated|.*)", t)
    if re.search(r"Invariant (\w+) is violated", t):
        name = re.search(r"Invariant (\w+) is violated", t).group(1)
        outcome = f"REACH WITNESS ({name})" if name.startswith("NotReach") else f"VIOLATION {name}"
    elif re.search(r"Action property \w+ .*violated|property .* violated", t, re.I):
        outcome = "VIOLATION " + re.search(r"(\w+ property \w+)", t).group(1)
    elif sim and rc == 0 and "Error:" not in t:
        outcome = "no error (simulation, time budget)"
    elif "Model checking completed. No error has been found." in t:
        if sim:
            outcome = "no error (simulation, time budget)"
        elif queue and queue.replace(",", "") != "0":
            outcome = "no error; BUDGET-LIMITED (queue not empty)"
        else:
            outcome = "COMPLETE, no error"
    else:
        outcome = f"rc={rc} (see log)"
    print(f"| {tag} | {mod} / {cfg}{(' ' + extra) if extra else ''} | {'simulation' if sim else 'BFS'} | {secs}s | {distinct} | {queue} | {depth} | {outcome} |")
