"""Static variable-assignment check: every base action assigns or frames every variable."""
import re, sys
src = open(sys.argv[1]).read()
var_block = re.search(r"VARIABLES(.*?)\n\n", src, re.S).group(1)
var_block = re.sub(r"\\\*[^\n]*", "", var_block)
vars_ = [v.strip() for v in var_block.replace("\n", " ").split(",") if v.strip()]
groups = {}
for name in ["electionVars", "histVars", "syncVars", "allVars"]:
    m = re.search(name + r" == <<(.*?)>>", src, re.S)
    groups[name] = [x.strip() for x in re.sub(r"\\\*[^\n]*", "", m.group(1)).replace("\n", " ").split(",")]
helpers = {"NoRollback": ["rollbackAuthorized"]}
# split into top-level definitions
defs = re.split(r"\n(?=[A-Z][A-Za-z]*(?:\([^)]*\))? ==)", src)
actions = sys.argv[2].split(",")
bad = 0
for d in defs:
    m = re.match(r"([A-Za-z]+)(?:\([^)]*\))? ==", d)
    if not m or m.group(1) not in actions:
        continue
    body = re.sub(r"\\\*[^\n]*", "", d)
    covered = set(re.findall(r"([A-Za-z]+)'", body))
    for um in re.findall(r"UNCHANGED\s*<<(.*?)>>", body, re.S):
        for x in um.replace("\n", " ").split(","):
            x = x.strip()
            covered |= set(groups.get(x, [x]))
    for um in re.findall(r"UNCHANGED\s+([A-Za-z]+)", body):
        covered |= set(groups.get(um, [um]))
    for h, vs in helpers.items():
        if re.search(r"\b" + h + r"\b", body):
            covered |= set(vs)
    missing = [v for v in vars_ if v not in covered]
    if missing:
        bad += 1
        print("MISSING", m.group(1), missing)
print("variables:", len(vars_), "actions checked:", len(actions), "bad:", bad)
sys.exit(1 if bad else 0)
