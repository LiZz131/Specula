#!/usr/bin/env python3
"""Build and run a one-state TLC evaluation of UpdateProps/base properties.
usage: mkeval.py <id> <tlc-log> <state-no> <logs-pending TRUE|FALSE> <maxepoch> <prop>[,<prop>...] [var=expr ...]
Writes spec/evidence/<id>/<id>.tla/.cfg, tlc-<prop>.log, and prints {prop: verdict}."""
import sys, re, os, subprocess, json, shutil
eid, log, sno, lp, maxep, props = sys.argv[1:7]
eid = eid.replace('-', '_')
edits = dict(a.split('=', 1) for a in sys.argv[7:])
spec = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
d = os.path.join(spec, 'evidence', eid); os.makedirs(d, exist_ok=True)
txt = open(log, errors='replace').read()
m = re.search(r'^State %s:.*?\n(.*?)\n\n' % sno, txt, re.S | re.M)
body = m.group(1)
# drop MC-only variables
lines = []; cur = None
for ln in body.split('\n'):
    if ln.startswith('/\\ '):
        cur = ln[3:].split(' = ', 1)[0]
    if cur in ('counters', 'seen'):
        continue
    lines.append(ln)
body = '\n'.join(lines)
for var, expr in edits.items():
    body = re.sub(r'^/\\ %s = .*?(?=^/\\ |\Z)' % re.escape(var), '/\\\\ %s = %s\n' % (var, expr), body, flags=re.S | re.M)
init = body.replace('\n', '\n    ')
mod = f'''---- MODULE {eid} ----
(* Divergence evidence {eid}: state {sno} of {os.path.relpath(log, spec)}; edits: {edits or 'none'} *)
EXTENDS UpdateProps, TLC
CONSTANTS s1, s2, s3, t1
EvInit ==
    {init}
EvSpec == EvInit /\\ [][UNCHANGED allVars]_allVars
====
'''
open(os.path.join(d, eid + '.tla'), 'w').write(mod)
for f in ('base.tla', 'UpdateProps.tla'):
    shutil.copy(os.path.join(spec, f), d)
res = {}
for p in props.split(','):
    cfg = f'''SPECIFICATION EvSpec
CONSTANTS
    s1 = s1
    s2 = s2
    s3 = s3
    t1 = t1
    Server = {{s1, s2, s3}}
    Txn = {{t1}}
    Nil = Nil
    MaxEpoch = {maxep}
    NewLeaderLogsPending = {lp}
INVARIANT {p}
'''
    open(os.path.join(d, f'{eid}-{p}.cfg'), 'w').write(cfg)
    lg = os.path.join(d, f'tlc-{p}.log')
    cmd = ['timeout', '120', 'java', '-cp', '/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar', 'tlc2.TLC',
           '-config', f'{eid}-{p}.cfg', '-metadir', f'/dev/shm/specular-e2e-case-002/ev-{eid}-{p}', '-cleanup', '-workers', '1', eid + '.tla']
    r = subprocess.run(cmd, cwd=d, capture_output=True, text=True)
    open(lg, 'w').write(' '.join(cmd) + '\n' + r.stdout + r.stderr)
    shutil.rmtree(f'/dev/shm/specular-e2e-case-002/ev-{eid}-{p}', ignore_errors=True)
    out = r.stdout
    if 'is violated' in out: res[p] = False
    elif 'Model checking completed. No error has been found' in out: res[p] = True
    else: res[p] = 'ERROR'
print(json.dumps({'id': eid, 'results': res}))
