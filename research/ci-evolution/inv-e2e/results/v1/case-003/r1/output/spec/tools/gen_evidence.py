#!/usr/bin/env python3
"""Generate one-state TLC evaluation modules for spec/invariant-evidence.json.
usage: gen_evidence.py <evidence-spec.json>
Each entry: {"id","state": {...new-representation post-state...},
             "props": [new props], "old_props": [old props] (optional),
             "source": "...", "consts": {...} (optional)}
The new state is evaluated through INSTANCE Update (which EXTENDS MC, base);
the old properties through INSTANCE OldBase with params mapped to
"<other>/<veh>" strings (representation-only mapping)."""
import json, sys, os, subprocess
here = os.path.dirname(os.path.abspath(__file__))
spec = os.path.abspath(os.path.join(here, ".."))
evd = os.path.join(spec, "evidence")
def tla(v):
    if isinstance(v, bool): return "TRUE" if v else "FALSE"
    if isinstance(v, int): return str(v)
    if isinstance(v, str): return '"%s"' % v
    if isinstance(v, list): return "{" + ", ".join(tla(x) for x in v) + "}"
    if isinstance(v, dict): return "[" + ", ".join(f"{k} |-> {tla(x)}" for k, x in v.items()) + "]"
    raise TypeError(v)
def oldp(p):
    return "NoParam" if p["other"] == "NoOther" else f'{p["other"]}/{p["veh"]}'
NEWVARS = ["blockStoreHeight","appHeight","stateStoreHeight","stateHeight","activeParam","persistedParam",
           "lastParamChange","persistedLastParamChange","responseHeight","responseParam","responseAbciPresent",
           "phase","replayMutatesState","pendingBlockHeight","pendingParam","pendingAbciPresent","updatePresent",
           "validationOutcome","coverage"]
OLDVARS = [v for v in NEWVARS if v not in ("responseAbciPresent","pendingAbciPresent")]
def main(path):
    items = json.load(open(path))
    results = []
    for it in items:
        eid = it["id"]; s = dict(it["state"])
        s.setdefault("updatePresent", s["pendingParam"]["other"] != "NoOther")
        s.setdefault("coverage", [])
        c = {"MaxHeight": 3, "Others": ["o0","oBad"], "ValidOthers": ["o0"], "VEHeights": [-1,0,1,2,3,4],
             "InitialOthers": ["o0"], "InitialVEHs": [0,1,2]}
        c.update(it.get("consts", {}))
        d = os.path.join(evd, eid); os.makedirs(d, exist_ok=True)
        subs = [f"{k} <- {tla(v)}" for k, v in c.items()]
        subs += [f"{v} <- S.{v}" for v in NEWVARS]
        subs += ["counters <- [blocks |-> 0, crashes |-> 0, appRollbacks |-> 0]",
                 "MaxBlocks <- 3", "MaxCrashes <- 0", "MaxAppRollbacks <- 0"]
        lines = [f"---- MODULE {eid} ----", "EXTENDS Integers, TLC", "VARIABLE dummy",
                 f"\\* source: {it.get('source','constructed')}",
                 "S == " + tla(s),
                 "New == INSTANCE Update WITH " + ",\n    ".join(subs)]
        prints = [f'ASSUME PrintT(<<"{eid}", "new", "{p}", New!{p}>>)' for p in it["props"]]
        if it.get("old_props"):
            params = set()
            for k in ("activeParam","persistedParam","responseParam","pendingParam"):
                if s[k]["other"] != "NoOther": params.add(oldp(s[k]))
            os_ = {v: (oldp(s[v]) if isinstance(s[v], dict) and "veh" in s[v] else s[v]) for v in OLDVARS}
            params |= {f"{o}/{v}" for o in c["Others"] for v in c["VEHeights"]}
            valid = {f"{o}/{v}" for o in c["ValidOthers"] for v in c["VEHeights"] if v >= 0}
            osubs = [f"MaxHeight <- {c['MaxHeight']}", f"Params <- {tla(sorted(params))}",
                     f"ValidParams <- {tla(sorted(valid))}", f'InitialParam <- "o0/0"', 'NoParam <- "NoParam"']
            osubs += [f"{v} <- OS.{v}" for v in OLDVARS]
            lines += ["\\* representation-only mapping: [other |-> o, veh |-> v] -> \"o/v\"",
                      "OS == " + tla(os_),
                      "Old == INSTANCE OldBase WITH " + ",\n    ".join(osubs)]
            prints += [f'ASSUME PrintT(<<"{eid}", "old", "{p}", Old!{p}>>)' for p in it["old_props"]]
        lines += prints + ["Init == dummy = 0", "Next == UNCHANGED dummy", "===="]
        open(os.path.join(d, f"{eid}.tla"), "w").write("\n".join(lines) + "\n")
        open(os.path.join(d, f"{eid}.cfg"), "w").write("INIT Init\nNEXT Next\n")
        cmd = ["timeout", "5m", "java", f"-DTLA-Library={spec}:{evd}", "-cp",
               "/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar", "tlc2.TLC",
               "-metadir", f"/dev/shm/specula-e2e-case-003/evidence-{eid}", "-noGenerateSpecTE",
               "-config", f"{eid}.cfg", f"{eid}.tla"]
        r = subprocess.run(cmd, cwd=d, capture_output=True, text=True)
        subprocess.run(["rm", "-rf", f"/dev/shm/specula-e2e-case-003/evidence-{eid}"])
        log = "# command: (cd spec/evidence/%s && %s)\n" % (eid, " ".join(cmd)) + r.stdout + r.stderr + f"# exit: {r.returncode}\n"
        open(os.path.join(d, "tlc.log"), "w").write(log)
        vals = [l for l in r.stdout.splitlines() if l.startswith("<<\"" + eid)]
        print(eid, "exit", r.returncode, *vals, sep="\n  ")
        results.append((eid, r.returncode, vals))
    return results
if __name__ == "__main__":
    main(sys.argv[1])
