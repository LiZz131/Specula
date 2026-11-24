#!/usr/bin/env python3
"""Merge items.jsonl with probe results (probes/*/*/Probe_<id>.{sim,bfs}.json) into dismissals.csv."""
import csv, json, os, glob
D = os.path.dirname(os.path.abspath(__file__))
items = [json.loads(l) for l in open(os.path.join(D, "items.jsonl")) if l.strip()]
res = {}
for f in glob.glob(os.path.join(D, "probes/*/*/Probe_*.json")):
    r = json.load(open(f))
    res.setdefault(r["id"], {})[r["mode"]] = r
cols = ["arm", "case", "id", "quote", "source", "in_starting_list", "class", "canary", "cfg",
        "result", "depth", "seconds", "sim_result", "sim_seconds", "bfs_result", "bfs_seconds",
        "judgment", "note"]
rows = []
for it in items:
    r = res.get(it["id"], {})
    sim, sim2, bfs = r.get("sim"), r.get("sim2"), r.get("bfs")
    if sim and sim2:
        merged = dict(sim)
        merged["seconds"] = round(sim["seconds"] + sim2["seconds"], 1)
        if sim2["result"] == "reachable" and sim["result"] != "reachable":
            merged["result"], merged["depth"] = "reachable", sim2["depth"]
        merged["result_detail"] = "%s + %s" % (sim["result"], sim2["result"])
        sim = merged
    row = {c: it.get(c, "") for c in cols}
    if sim:
        row["sim_result"], row["sim_seconds"] = sim["result"], sim["seconds"]
    if bfs:
        row["bfs_result"], row["bfs_seconds"] = bfs["result"], bfs["seconds"]
    if not it.get("result"):
        if sim and sim["result"] == "reachable":
            row["result"], row["depth"] = "reachable", sim["depth"]
        elif bfs and bfs["result"] == "reachable":
            row["result"], row["depth"] = "reachable", bfs["depth"]
        elif bfs and bfs["result"] == "exhausted_not_reached":
            row["result"] = "not_reachable_exhaustive_bfs"
        elif bfs or sim:
            row["result"] = "not_reached_in_budget" if (bfs or sim)["result"] in ("not_reached_in_budget", "sim_finished_not_reached", "exhausted_not_reached") else (bfs or sim)["result"]
        elif it.get("class") == "a":
            row["result"] = "pending"
    tot = sum(x["seconds"] for x in (sim, bfs) if x)
    if sim or bfs:
        row["seconds"] = round(tot, 1)
    rows.append(row)
order = {"v0": 0, "v1": 1, "v2": 2}
rows.sort(key=lambda r: (order[r["arm"]], r["case"], r["id"]))
with open(os.path.join(D, "dismissals.csv"), "w", newline="") as o:
    w = csv.DictWriter(o, fieldnames=cols)
    w.writeheader()
    w.writerows(rows)
print(len(rows))
