#!/usr/bin/env python3
"""Static generation preflight (no TLC exploration):
 1. every cfg-referenced operator/constant exists in the module chain;
 2. every base action assigns or UNCHANGEs every variable exactly once."""
import re, sys, glob, os
os.chdir(os.path.dirname(os.path.abspath(__file__)) + "/..")
mods = {m: open(m + ".tla").read() for m in ["base", "MC", "Trace", "Update"]}
chain = {"base": ["base"], "MC": ["MC", "base"], "Trace": ["Trace", "base"], "Update": ["Update", "MC", "base"]}
def defs(m):
    names = set()
    for mm in chain[m]:
        t = mods[mm]
        names |= set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)(?:\([^)]*\))?\s*==", t, re.M))
        for blk in re.findall(r"^(?:CONSTANTS?|VARIABLES?)\s+(.*?)(?=\n\S|\Z)", t, re.M | re.S):
            names |= set(re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", re.sub(r"\\\*.*", "", blk)))
    return names
ok = True
for cfg in sorted(glob.glob("*.cfg")):
    txt = re.sub(r"\\\*.*", "", open(cfg).read())
    spec = re.search(r"SPECIFICATION\s+(\w+)", txt)
    m = "Update" if cfg.startswith("Update") else "Trace" if cfg.startswith("Trace") else "base" if cfg.startswith("base") else "MC"
    names = defs(m)
    used = set()
    for sect in re.findall(r"(?:INVARIANTS?|PROPERTY|PROPERTIES|SPECIFICATION|INIT|NEXT)\s+((?:\s*\w+\s*\n?)+)", txt):
        used |= set(re.findall(r"\w+", sect))
    used |= set(re.findall(r"^\s*(\w+)\s*(?:=|<-)", txt, re.M))
    used |= set(re.findall(r"<-\s*(\w+)", txt))
    kw = {"INVARIANT","INVARIANTS","PROPERTY","PROPERTIES","SPECIFICATION","INIT","NEXT","CONSTANTS","CONSTANT"}
    missing = sorted(u for u in used - kw if u not in names and not u.isdigit())
    print(f"{cfg} [{m}]: {'OK' if not missing else 'MISSING ' + str(missing)}")
    ok &= not missing
# variable assignment check for base actions
b = mods["base"]
vars_ = re.findall(r"\b(\w+)\b", re.search(r"VARIABLES(.*?)\n\nvars", b, re.S).group(1).split("vars ==")[0])
vars_ = [v for v in re.findall(r"^\s+(\w+),?\s*(?:\\\*.*)?$", re.search(r"VARIABLES\n(.*?)\n\n", b, re.S).group(1), re.M)]
actions = ["SaveBlock","ApplyBlockStart","FinalizeBlock(p, abci)","SaveFinalizeBlockResponse","UpdateStateAccepted",
           "UpdateStateRejectedBasic","UpdateStateRejectedVE","CommitApp","SaveState","AbortRejectedApply","Crash",
           "AppReportsOlderHeight(h)","BeginHandshake","ReplayAppBlock","SelectRealReplay","SelectMockReplay","CompleteHandshake"]
for a in actions:
    m = re.search(r"^" + re.escape(a) + r" ==\n(.*?)(?=\n\n)", b, re.S | re.M)
    body = re.sub(r"\\\*.*", "", m.group(1))
    primed = re.findall(r"\b(\w+)'", body)
    unch = re.search(r"UNCHANGED <<(.*?)>>", body, re.S)
    unch = re.findall(r"\w+", unch.group(1)) if unch else []
    allv = primed + unch
    dup = sorted({v for v in allv if allv.count(v) > 1})
    miss = sorted(set(vars_) - set(allv))
    extra = sorted(set(allv) - set(vars_))
    st = "OK" if not (dup or miss or extra) else f"dup={dup} missing={miss} extra={extra}"
    print(f"VAV {a}: {st}")
    ok &= st == "OK"
print("vars:", len(vars_), vars_)
sys.exit(0 if ok else 1)
