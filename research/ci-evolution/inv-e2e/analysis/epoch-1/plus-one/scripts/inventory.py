#!/usr/bin/env python3
"""Inventory all cfgs of every arm/case copy: spec name, constants, checks, guessed module.
Usage: inventory.py <workroot>  -> prints JSON lines."""
import json, os, re, sys

root = sys.argv[1]

def parse_cfg(text):
    text = re.sub(r'\\\*.*', '', text)
    text = re.sub(r'\(\*.*?\*\)', '', text, flags=re.S)
    toks = text.split('\n')
    sec = None
    out = {'spec': None, 'init': None, 'next': None, 'consts': {}, 'inv': [], 'prop': [], 'constraint': [], 'other': []}
    for line in toks:
        s = line.strip()
        if not s:
            continue
        m = re.match(r'^(SPECIFICATION|INIT|NEXT|CONSTANTS?|INVARIANTS?|PROPERT(?:Y|IES)|CONSTRAINTS?|ACTION_CONSTRAINTS?|SYMMETRY|VIEW|CHECK_DEADLOCK|ALIAS|POSTCONDITION)\b\s*(.*)$', s)
        if m:
            kw, rest = m.group(1), m.group(2)
            sec = kw
            if kw in ('SPECIFICATION', 'INIT', 'NEXT'):
                out[kw.lower() if kw != 'SPECIFICATION' else 'spec'] = rest.split()[0] if rest else None
                sec = kw
                if not rest:
                    sec = kw + '_pending'
                continue
            if not rest:
                continue
            s = rest
        if sec in ('SPECIFICATION_pending',):
            out['spec'] = s.split()[0]; sec = None; continue
        if sec in ('INIT_pending',):
            out['init'] = s.split()[0]; sec = None; continue
        if sec in ('NEXT_pending',):
            out['next'] = s.split()[0]; sec = None; continue
        if sec and sec.startswith('CONSTANT'):
            for mm in re.finditer(r'([A-Za-z_][A-Za-z0-9_]*)\s*(=|<-)\s*(\{[^}]*\}|[^\s]+)', s):
                out['consts'][mm.group(1)] = (mm.group(2), mm.group(3))
        elif sec and sec.startswith('INVARIANT'):
            out['inv'] += s.split()
        elif sec and sec.startswith('PROPERT'):
            out['prop'] += s.split()
        elif sec and sec.startswith('CONSTRAINT'):
            out['constraint'] += s.split()
    return out

def defs(mod_path):
    try:
        t = open(mod_path, errors='replace').read()
    except OSError:
        return set(), []
    d = set(re.findall(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?:\([^)]*\))?\s*==', t, flags=re.M))
    ext = []
    m = re.search(r'^\s*EXTENDS\s+([^\n]+)', t, flags=re.M)
    if m:
        ext = [x.strip() for x in m.group(1).split(',')]
    for mm in re.finditer(r'INSTANCE\s+([A-Za-z0-9_]+)', t):
        ext.append(mm.group(1))
    return d, ext

def closure(dirp, mod, seen=None):
    seen = seen or set()
    if mod in seen:
        return set()
    seen.add(mod)
    d, ext = defs(os.path.join(dirp, mod + '.tla'))
    for e in ext:
        if os.path.exists(os.path.join(dirp, e + '.tla')):
            d |= closure(dirp, e, seen)
    return d

for arm in sorted(os.listdir(root)):
    ap = os.path.join(root, arm)
    if not os.path.isdir(ap) or arm not in ('v0', 'v1', 'v2'):
        continue
    for case in sorted(os.listdir(ap)):
        cp = os.path.join(ap, case)
        mods = sorted(f[:-4] for f in os.listdir(cp) if f.endswith('.tla'))
        cl = {m: closure(cp, m) for m in mods}
        for f in sorted(os.listdir(cp)):
            if not f.endswith('.cfg'):
                continue
            c = parse_cfg(open(os.path.join(cp, f), errors='replace').read())
            names = [x for x in [c['spec'], c['init'], c['next']] + c['inv'] + c['prop'] + c['constraint'] if x]
            cands = [m for m in mods if all(n in cl[m] for n in names)]
            # prefer modules not named Trace*
            pref = [m for m in cands if not m.startswith('Trace')] or cands
            # smallest closure
            pref.sort(key=lambda m: len(cl[m]))
            c.update(arm=arm, case=case, cfg=f, module_cands=cands, module=(pref[0] if pref else None))
            print(json.dumps(c))
