"""Static generation preflight: cfg operator resolution + variable assignment.

Usage: python3 -I static_preflight.py <spec-dir>
"""
import re, sys, glob, os
d = sys.argv[1]
mods = {m: open(os.path.join(d, m + ".tla")).read() for m in ["base", "MC", "Trace", "Update"]}
defs = {m: set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\([^)]*\))?\s*==", s, re.M)) for m, s in mods.items()}
consts = set()
for s in mods.values():
    for blk in re.findall(r"^CONSTANTS?\s*\n((?:\s+.*\n)+?)\n", s, re.M):
        consts |= set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)", re.sub(r"\\\*.*", "", blk)))
chain = {"base": ["base"], "MC": ["base", "MC"], "Trace": ["base", "Trace"], "Update": ["base", "MC", "Update"]}
ok = True
for cfg in sorted(glob.glob(os.path.join(d, "*.cfg"))):
    txt = re.sub(r"\\\*.*", "", open(cfg).read())
    spec = re.search(r"SPECIFICATION\s+(\w+)", txt)
    names = [n for n in re.findall(r"^\s+([A-Za-z_]\w*)\s*$", txt, re.M)]
    names = [n for n in re.findall(r"^\s*([A-Za-z_]\w*)\s*$", txt, re.M) if n not in {"CONSTANTS","CONSTANT","INVARIANTS","INVARIANT","PROPERTIES","PROPERTY"}]
    if spec: names.append(spec.group(1))
    for m in re.finditer(r"^(?:INIT|NEXT)\s+(\w+)", txt, re.M): names.append(m.group(1))
    for m in re.finditer(r"<-\s*(\w+)", txt): names.append(m.group(1))
    avail = set()
    owner = None
    for top in ["Update", "Trace", "MC", "base"]:
        if all(n in set().union(*(defs[x] for x in chain[top])) for n in names if n not in consts):
            owner = top; break
    if owner is None:
        missing = [n for n in names if n not in consts and not any(n in defs[x] for x in defs)]
        print("UNRESOLVED", os.path.basename(cfg), missing); ok = False
    else:
        print(f"{os.path.basename(cfg):45s} -> module {owner}: {len(names)} names resolved")
# Variable assignment check over base actions
base = mods["base"]
vars_ = re.search(r"^vars == <<(.*?)>>", base, re.M | re.S).group(1)
V = [v.strip() for v in vars_.replace("\n", " ").split(",")]
actions = ["SaveBlock", "ApplyBlockStart", "FinalizeBlock", "SaveFinalizeBlockResponse",
           "UpdateStateAccepted", "UpdateStateRejected", "CommitApp", "SaveState",
           "AbortRejectedApply", "Crash", "AppReportsOlderHeight", "BeginHandshake",
           "ReplayAppBlock", "SelectRealReplay", "SelectMockReplay", "CompleteHandshake"]
for a in actions:
    m = re.search(r"^" + a + r"(?:\([^)]*\))? ==\n(.*?)(?=^\S)", base, re.M | re.S)
    body = re.sub(r"\\\*.*", "", m.group(1))
    primed = set(re.findall(r"(\w+)'", body))
    unch = set()
    for u in re.findall(r"UNCHANGED\s*<<(.*?)>>", body, re.S):
        unch |= {x.strip() for x in u.replace("\n", " ").split(",")}
    covered = primed | unch
    miss = [v for v in V if v not in covered]
    dup = primed & unch
    status = "OK" if not miss and not dup else f"MISSING {miss} DUP {sorted(dup)}"
    print(f"VAV {a:28s} {status}")
    ok &= (not miss and not dup)
print("PREFLIGHT", "PASS" if ok else "FAIL")
