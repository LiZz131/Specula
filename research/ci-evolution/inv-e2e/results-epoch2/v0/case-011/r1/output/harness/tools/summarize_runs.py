#!/usr/bin/env python3
"""Summarize TLC run logs in spec/output into Markdown + JSON.
Usage: summarize_runs.py <spec/output dir> <run-name>... """
import re, sys, json, os
out_dir = sys.argv[1]
rows = []
for name in sys.argv[2:]:
    p = os.path.join(out_dir, name + ".log")
    if not os.path.exists(p):
        rows.append({"run": name, "status": "NOT RUN"}); continue
    s = open(p, errors="replace").read()
    cfg = re.search(r"-config (\S+)", s); mod = re.search(r"-config \S+ (?:.* )?(\w+)\n", s)
    mode = "simulation" if " -simulate" in s else "BFS"
    r = {"run": name, "cfg": cfg.group(1) if cfg else "?", "mode": mode}
    v = re.search(r"Error: (Invariant|Action property) (\w+) is violated", s)
    rc = re.search(r"# exit code: (\d+)", s)
    prog = re.findall(r"Progress\((\d+)\) at [^:]+:\d+:\d+: ([\d,]+) states generated \([^)]*\), ([\d,]+) distinct states found \([^)]*\), ([\d,]+) states left", s)
    fin = re.search(r"([\d]+) states generated, ([\d]+) distinct states found, ([\d]+) states left on queue", s)
    depth = re.search(r"The depth of the complete state graph search is (\d+)", s)
    simtr = re.search(r"(\d+) states generated.*?\n.*?traces? generated|The number of states generated: ([\d,]+)", s)
    if fin:
        r.update(generated=int(fin.group(1)), distinct=int(fin.group(2)), queue=int(fin.group(3)))
    elif prog:
        d, g, ds, q = prog[-1]
        r.update(generated=int(g.replace(",", "")), distinct=int(ds.replace(",", "")), queue=int(q.replace(",", "")), depth=int(d))
    if depth: r["depth"] = int(depth.group(1))
    simp = re.findall(r"Progress: (\d+) states checked, (\d+) traces generated \(trace length: mean=(\d+)", s)
    if mode == "simulation" and simp:
        r["sim_states_checked"], r["sim_traces"], r["sim_mean_len"] = map(int, simp[-1])
    if v:
        r["status"] = "VIOLATION"; r["property"] = v.group(2); r["trace_states"] = len(re.findall(r"^State \d+: ", s, re.M))
    elif "Model checking completed. No error has been found." in s:
        r["status"] = "COMPLETE (no violation)" if mode == "BFS" else "SIM COMPLETE"
    elif rc and rc.group(1) == "124":
        r["status"] = "LIMITED_COVERAGE (time budget, no violation)"
    else:
        r["status"] = "OTHER (exit %s)" % (rc.group(1) if rc else "?")
    rows.append(r)
print("| Run | Cfg | Mode | Status | Distinct | Depth | Queue left | Violated / trace |")
print("|---|---|---|---|---|---|---|---|")
for r in rows:
    print("| %s | %s | %s | %s | %s | %s | %s | %s |" % (r["run"], r.get("cfg","-"), r.get("mode","-"), r["status"],
          format(r["distinct"], ",") if "distinct" in r else ("%s checked / %s traces" % (format(r["sim_states_checked"], ","), format(r["sim_traces"], ",")) if "sim_traces" in r else "-"),
          r.get("depth", ("mean len %d, bound 60" % r["sim_mean_len"]) if "sim_mean_len" in r else "-"),
          format(r["queue"], ",") if "queue" in r else "-",
          ("%s (%d states)" % (r["property"], r["trace_states"])) if "property" in r else "-"))
json.dump(rows, open(os.path.join(out_dir, "campaign-summary.json"), "w"), indent=1)
