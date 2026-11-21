"""Static cfg check: every referenced operator/constant exists in the module chain."""
import re, sys, glob
mods = {"base": "base.tla", "MC": "MC.tla", "UpdateProps": "UpdateProps.tla", "Update": "Update.tla", "Trace": "Trace.tla"}
chain = {"base": ["base"], "MC": ["base", "MC"], "Update": ["base", "MC", "UpdateProps", "Update"], "Trace": ["base", "Trace"]}
defs = {}
for k, f in mods.items():
    try:
        s = open(f).read()
    except FileNotFoundError:
        continue
    names = set(re.findall(r"^([A-Za-z][A-Za-z0-9_]*)(?:\([^)]*\))?\s*==", s, re.M))
    consts = set()
    for cm in re.findall(r"CONSTANTS?\s+([^\n]+)", s):
        consts |= {c.strip() for c in cm.split(",") if c.strip()}
    defs[k] = (names, consts)
bad = 0
for cfg in sys.argv[2:]:
    mod = sys.argv[1] if not cfg.startswith(("Update", "MC", "base", "Trace")) else None
    root = cfg.split("-")[0].split(".")[0]
    root = {"Update": "Update", "MC": "MC", "base": "base", "Trace": "Trace"}.get(root, "MC")
    names = set(); consts = set()
    for m in chain[root]:
        if m in defs:
            names |= defs[m][0]; consts |= defs[m][1]
    txt = re.sub(r"\\\*[^\n]*", "", open(cfg).read())
    sections = re.split(r"\b(SPECIFICATION|INVARIANTS?|PROPERTIES|PROPERTY|ACTION_CONSTRAINTS?|CONSTRAINTS?|SYMMETRY|VIEW|CONSTANTS?|CHECK_DEADLOCK|ALIAS)\b", txt)
    cur = None
    for tok in sections:
        if tok in ("SPECIFICATION", "INVARIANT", "INVARIANTS", "PROPERTIES", "PROPERTY", "ACTION_CONSTRAINT", "ACTION_CONSTRAINTS", "CONSTRAINT", "CONSTRAINTS", "SYMMETRY", "VIEW", "CONSTANT", "CONSTANTS", "CHECK_DEADLOCK", "ALIAS"):
            cur = tok; continue
        if cur in (None, "CHECK_DEADLOCK"):
            continue
        if cur.startswith("CONSTANT"):
            for line in tok.strip().splitlines():
                line = line.strip()
                if not line: continue
                lhs = re.split(r"=|<-", line)[0].strip()
                rhs = re.split(r"<-", line)[1].strip() if "<-" in line else None
                if lhs not in consts:
                    print(cfg, "unknown CONSTANT", lhs); bad += 1
                if rhs and rhs not in names:
                    print(cfg, "unknown override", rhs); bad += 1
        else:
            for n in tok.split():
                if n not in names:
                    print(cfg, "unknown", cur, n); bad += 1
print("cfgs:", len(sys.argv) - 2, "problems:", bad)
sys.exit(1 if bad else 0)
