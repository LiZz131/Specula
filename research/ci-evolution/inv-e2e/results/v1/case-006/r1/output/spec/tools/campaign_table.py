"""Build spec/output/mc/campaigns.md from run_tlc.sh logs (TLC output only)."""
import glob, os, re, sys
root = sys.argv[1] if len(sys.argv) > 1 else "spec/output/mc"
rows = []
for log in sorted(glob.glob(os.path.join(root, "*.log"))):
    name = os.path.basename(log)[:-4]
    txt = open(log, errors="replace").read()
    cmd = re.search(r"^# cmd: run_tlc.sh (\S+) (\S+) (\S+) (\d+) (\d+) (\S+)(.*)$", txt, re.M)
    if not cmd:
        continue
    _, module, cfg, secs, workers, heap, extra = cmd.groups()
    mode = "simulation" if "-simulate" in extra else "BFS"
    start = re.search(r"^# start: (\S+)", txt, re.M)
    end = re.search(r"^# end: (\S+) rc=(\d+)", txt, re.M)
    err = re.search(r"^Error: (.*)$", txt, re.M)
    gen = re.findall(r"^(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue\.", txt, re.M)
    depth = re.findall(r"^The depth of the complete state graph search is (\d+)\.", txt, re.M)
    simst = re.findall(r"^Progress: (\d+) states checked, (\d+) traces generated", txt, re.M)
    simn = re.findall(r"The number of states generated: (\d+)", txt)
    cexlen = len(re.findall(r"^State \d+:", txt, re.M))
    if mode == "BFS" and gen:
        g, d, q = gen[-1]
        cov = f"{int(g):,} gen / {int(d):,} distinct / {int(q):,} queued, depth {depth[-1] if depth else '?'}"
        exhaust = (q == "0" and not err)
    elif mode == "simulation":
        st = simst[-1] if simst else ("?", "?")
        cov = f"{st[0]} states checked, {st[1]} traces (depth<=100)"
        exhaust = False
    else:
        cov = "n/a"; exhaust = False
    if not end:
        status = "RUNNING/INTERRUPTED"
    elif err:
        status = "VIOLATION: " + err.group(1).strip() + (f" ({cexlen}-state trace)" if cexlen else "")
    elif exhaust:
        status = "no violation, EXHAUSTED"
    elif "Model checking completed" in txt or "simulation" == mode or "Finished" in txt:
        status = "no violation, LIMITED_COVERAGE (time budget)"
    else:
        status = f"rc={end.group(2)} (check log)"
    rows.append((name, module, cfg, mode, f"{secs}s x{workers}", status, cov))
out = ["| Run | Module | Config | Mode | Budget | Result | Coverage |", "|---|---|---|---|---|---|---|"]
out += ["| " + " | ".join(r) + " |" for r in rows]
open(os.path.join(root, "campaigns.md"), "w").write("\n".join(out) + "\n")
print("\n".join(out))
