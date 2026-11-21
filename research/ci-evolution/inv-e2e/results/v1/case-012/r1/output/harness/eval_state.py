#!/usr/bin/env python3
"""Evaluate properties on one concrete state with TLC (one-state spec, PrintT).

usage: eval_state.py <id> <source-log> <state-no> <new|old> <prop,prop,...> [sed-expr ...]
  new: EXTENDS Update (current suite);  old: EXTENDS V0 MC (spec/evidence/v0-model)
  sed-expr: optional python 'old=>new' textual edits applied to the state block
            (used only for constructed variants; recorded in the evidence file).
Writes spec/evidence/<id>/<id>_<mode>.tla/.cfg and spec/evidence/<id>/tlc_<mode>.log
"""
import re, subprocess, sys, pathlib, shutil
eid, src, sno, mode, props = sys.argv[1:6]
edits = sys.argv[6:]
root = pathlib.Path("/work/current/.specula-output/spec")
log = (root / src).read_text() if not src.startswith("/") else pathlib.Path(src).read_text()
blocks = dict((n, body) for n, _a, body in re.findall(r'State (\d+): <([^>]*)>\n(.*?)(?=\nState \d+:|\n\n|\Z)', log, re.S))
block = blocks[sno].strip()
for e in edits:
    a, b = e.split("=>", 1)
    assert a in block, f"edit target not found: {a}"
    block = block.replace(a, b)
d = root / "evidence" / eid
d.mkdir(parents=True, exist_ok=True)
consts = """CONSTANTS
    n1 = n1
    n2 = n2
    n3 = n3
    Server <- MCServer
    AllowedConfigs <- MCAllowedConfigs
    MaxTerm = 2
    MaxIndex = 1
    MaxElectionActions = 2
    MaxClientAppends = 2
    MaxMembershipChanges = 2
    MaxCrashes = 1
    MaxLosses = 1
"""
if mode == "new":
    ext, workdir = "Update", root
    consts += "    ServerOrder <- MCServerOrder\n"
else:
    ext, workdir = "MC", root / "evidence" / "v0-model"
    block = "\n".join(l for l in re.split(r'\n(?=/\\ )', block)
                      if not l.startswith("/\\ leaderActive") and not l.startswith("/\\ progress") and not l.startswith("/\\ logConfig"))
plist = props.split(",")
mod = f"{eid}_{mode}"
tla = f"""---- MODULE {mod} ----
EXTENDS {ext}
\\* state source: {src} State {sno}; edits: {edits if edits else 'none'}
EvInit ==
{chr(10).join('    ' + l for l in block.splitlines())}
    /\\ PrintT(<<"EVAL", "{eid}", "{mode}", {', '.join(f'<<"{p}", {p}>>' for p in plist)}>>)
EvNext == UNCHANGED <<vars, electionActions, clientAppends, membershipChanges, crashes, losses>>
====
"""
(workdir / f"{mod}.tla").write_text(tla)
(workdir / f"{mod}.cfg").write_text(f"INIT EvInit\nNEXT EvNext\nCHECK_DEADLOCK FALSE\n{consts}")
meta = f"/dev/shm/specula-e2e-case-012/ev-{mod}"
r = subprocess.run(["timeout", "300", "java", "-cp", "/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar",
                    "tlc2.TLC", "-config", f"{mod}.cfg", "-metadir", meta, "-workers", "1", f"{mod}.tla"],
                   cwd=workdir, capture_output=True, text=True)
shutil.rmtree(meta, ignore_errors=True)
(d / f"tlc_{mode}.log").write_text(r.stdout + r.stderr)
if workdir != d:
    for ext2 in ("tla", "cfg"):
        shutil.move(str(workdir / f"{mod}.{ext2}"), str(d / f"{mod}.{ext2}"))
m = re.search(r'<< "EVAL",(.*?)>> >>', r.stdout, re.S)
print(eid, mode, " ".join(m.group(1).split()) if m else "NO-EVAL-OUTPUT\n" + r.stdout[-1500:])
