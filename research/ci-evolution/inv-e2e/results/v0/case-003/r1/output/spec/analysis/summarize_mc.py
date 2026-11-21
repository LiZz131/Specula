"""Summarize spec/output/mc-v1-*.log into a markdown table + JSON.
Usage: python3 -I summarize_mc.py <spec-dir>"""
import glob, os, re, sys, json
d = sys.argv[1]
rows = []
for f in sorted(glob.glob(os.path.join(d, "output", "mc-v1-*.log"))):
    t = open(f).read()
    label = os.path.basename(f)[6:-4]
    cfg = re.search(r"-config (\S+)", t); cfg = cfg.group(1) if cfg else "?"
    mode = "simulation" if "-simulate" in t else "BFS"
    exitc = re.search(r"tlc exit=(\d+)", t); exitc = int(exitc.group(1)) if exitc else None
    viol = re.search(r"(Invariant \w+ is violated|Action property \w+ is violated|Temporal properties were violated|Deadlock reached)", t)
    distinct = re.findall(r"(\d+) distinct states found", t)
    gen = re.findall(r"The number of states generated: (\d+)", t) or re.findall(r"(\d+) states generated", t)
    depth = re.search(r"depth of the complete state graph search is (\d+)", t)
    traces = re.findall(r"(\d+) traces generated", t)
    left = re.findall(r"(\d+) states left on queue", t)
    if viol:
        outcome = "VIOLATION: " + viol.group(1)
    elif exitc == 0 and "Model checking completed. No error has been found." in t:
        outcome = "completed, no violation (bounded space exhausted)"
    elif exitc == 0 and mode == "simulation":
        outcome = "budget-limited simulation, no violation"
    else:
        outcome = f"exit {exitc}"
    rows.append(dict(label=label, cfg=cfg, mode=mode, exit=exitc, outcome=outcome,
                     distinct=int(distinct[-1]) if distinct else None,
                     generated=int(gen[-1]) if gen else None,
                     traces=int(traces[-1]) if traces else None,
                     depth=int(depth.group(1)) if depth else None,
                     queue_left=int(left[-1]) if left else None,
                     log=f"spec/output/{os.path.basename(f)}"))
json.dump(rows, open(os.path.join(d, "output", "mc-v1-summary.json"), "w"), indent=1)
print("| Run | Config | Mode | Distinct / generated | Depth | Outcome |\n|---|---|---|---|---|---|")
for r in rows:
    dg = f"{r['distinct'] or '-'} / {r['generated'] or '-'}" + (f" ({r['traces']} traces)" if r['traces'] else "")
    print(f"| {r['label']} | `{r['cfg']}` | {r['mode']} | {dg} | {r['depth'] or '-'} | {r['outcome']} |")
