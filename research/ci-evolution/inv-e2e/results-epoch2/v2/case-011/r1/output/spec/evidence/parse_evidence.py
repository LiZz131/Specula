#!/usr/bin/env python3
"""Extract PrintT report tuples from evidence tlc.log files into evidence-results.json."""
import os, re, json, glob
HERE = os.path.dirname(os.path.abspath(__file__))
out = {}
for log in sorted(glob.glob(os.path.join(HERE, "E_*", "tlc.log"))):
    eid = os.path.basename(os.path.dirname(log))
    txt = open(log).read()
    flat = " ".join(txt.split())
    reports = []
    i = 0
    key = '<< "%s",' % eid
    while True:
        j = flat.find(key, i)
        if j < 0: break
        depth = 0; k = j
        while k < len(flat):
            if flat.startswith("<<", k): depth += 1; k += 2; continue
            if flat.startswith(">>", k):
                depth -= 1; k += 2
                if depth == 0: break
                continue
            k += 1
        tup = flat[j:k]
        toks = re.findall(r'"([A-Za-z_]+)", (TRUE|FALSE)', tup)
        kind = "step" if '"step"' in tup else "state"
        lvl = re.search(r'"state", (\d+), "(old|new)"', tup)
        reports.append({"kind": kind, "level": int(lvl.group(1)) if lvl else None,
                        "defs": lvl.group(2) if lvl else "new", "values": dict(toks)})
        i = k
    status = "completed" if "Model checking completed. No error has been found." in txt else (
             "violation" if "is violated" in txt else "other")
    out[eid] = {"tlc_status": status, "log": os.path.relpath(log, os.path.join(HERE, "..", "..")),
                "reports": reports}
json.dump(out, open(os.path.join(HERE, "evidence-results.json"), "w"), indent=1)
for eid, r in out.items():
    print(eid, r["tlc_status"])
    seen = set()
    for rep in r["reports"]:
        sig = (rep["kind"], rep["level"], rep["defs"], tuple(sorted(rep["values"].items())))
        if sig in seen: continue
        seen.add(sig)
        falses = [k for k, v in rep["values"].items() if v == "FALSE"]
        print("   ", rep["kind"], rep["level"], rep["defs"], "FALSE:", falses)
