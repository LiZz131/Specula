"""Summarise every spec/output/v1-mc-*.log campaign into a Markdown table."""
import glob, os, re, sys
out = sys.argv[1]
rows = []
for f in sorted(glob.glob(os.path.join(out, "v1-mc-*.log"))):
    name = os.path.basename(f)
    t = open(f, errors="replace").read()
    cmd = re.search(r"# command: timeout (\d+)m .* -config (\S+) (?:.* )?(\w+)$", t, re.M)
    cfg = cmd.group(2) if cmd else "?"
    mode = "simulation" if "-simulate" in t.split("\n", 1)[0] else "BFS"
    viol = re.search(r"Error: (?:Invariant|Action property|Temporal properties?) ?(\S*) (?:is|were) violated", t)
    done = "Model checking completed. No error has been found." in t
    ex = re.search(r"# exit: (\d+)", t)
    prog = re.findall(r"Progress\((\d+)\) at \S+ \S+: ([\d,]+) states generated \([^)]*\), ([\d,]+) distinct states found \([^)]*\), ([\d,]+) states left", t)
    fin = re.search(r"([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue", t)
    depth = re.search(r"The depth of the complete state graph search is (\d+)", t)
    sim = re.search(r"([\d,]+) states generated? .*?traces? .*?", t)
    if fin:
        gen, dist, left = fin.groups(); d = depth.group(1) if depth else (prog[-1][0] if prog else "?")
    elif prog:
        d, gen, dist, left = prog[-1]
    else:
        d = gen = dist = left = "?"
    if viol:
        outcome = "VIOLATED " + viol.group(1)
    elif done:
        outcome = "no violation; state space exhausted"
    elif ex and ex.group(1) == "124":
        outcome = "no violation; BUDGET-LIMITED (LIMITED_COVERAGE)"
    else:
        outcome = "exit %s" % (ex.group(1) if ex else "?")
    if mode == "simulation":
        st = re.findall(r"Progress: ([\d,]+) states checked, ([\d,]+) traces generated", t)
        if st:
            gen, dist = st[-1][0], st[-1][1] + " traces"; left = "-"
    rows.append((name, cfg, mode, outcome, d, gen, dist, left))
print("| Log | Config | Mode | Outcome | Depth/level | States generated | Distinct (or traces) | Queue left |")
print("|---|---|---|---|---|---|---|---|")
for r in rows:
    print("| %s |" % " | ".join(r))
