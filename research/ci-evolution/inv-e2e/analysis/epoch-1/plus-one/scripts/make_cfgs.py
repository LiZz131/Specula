#!/usr/bin/env python3
"""Write <cfg>.plus1.cfg next to each selected cfg in the work copy, raising every
integer count constant by exactly one. Records changes in changes.json.

Rule: a constant is raised iff its cfg value is an integer literal and its name matches
^Max | Limit$ | Count$ | Budget$ (every integer constant in the selected cfgs except NoNode
matches; NoNode is a sentinel id, not a count). Sets, model values, booleans, strings,
and `<-` substitutions are left alone.
Usage: make_cfgs.py <workroot> <selection.json> <outdir>"""
import json, os, re, shutil, sys

work, selp, outdir = sys.argv[1:4]
sel = json.load(open(selp))
COUNT = re.compile(r'^(Max|.*Limit$|.*Count$|.*Budget$)')
changes = []
for arm, case, cfg, module in sel:
    src = os.path.join(work, arm, case, cfg)
    lines = open(src).read().split('\n')
    out, ch = [], []
    in_const = False
    for line in lines:
        s = line.strip()
        if re.match(r'^(SPECIFICATION|INIT|NEXT|INVARIANTS?|PROPERT(Y|IES)|CONSTRAINTS?|ACTION_CONSTRAINTS?|SYMMETRY|VIEW|CHECK_DEADLOCK|ALIAS|POSTCONDITION)\b', s):
            in_const = False
        if re.match(r'^CONSTANTS?\b', s):
            in_const = True
        if in_const and not s.startswith('\\*'):
            code, sep, comment = line.partition('\\*')
            def rep(m):
                name, val = m.group(1), int(m.group(3))
                if COUNT.match(name):
                    ch.append({'const': name, 'old': val, 'new': val + 1})
                    return f'{m.group(1)}{m.group(2)}{val + 1}'
                return m.group(0)
            code = re.sub(r'\b([A-Za-z_][A-Za-z0-9_]*)(\s*=\s*)(-?\d+)\b(?!\s*\.\.)', rep, code)
            line = code + sep + comment
        out.append(line)
    base = cfg[:-4]
    dst = os.path.join(work, arm, case, base + '.plus1.cfg')
    open(dst, 'w').write('\\* plus-one experiment: generated from ' + cfg + '; changes: ' +
                         ', '.join(f"{c['const']} {c['old']}->{c['new']}" for c in ch) + '\n' + '\n'.join(out))
    od = os.path.join(outdir, arm, case)
    os.makedirs(od, exist_ok=True)
    shutil.copy(dst, od)
    changes.append({'arm': arm, 'case': case, 'cfg': cfg, 'module': module, 'plus1': base + '.plus1.cfg', 'changes': ch})
    print(arm, case, cfg, module, ' '.join(f"{c['const']}:{c['old']}->{c['new']}" for c in ch))
json.dump(changes, open(os.path.join(outdir, 'changes.json'), 'w'), indent=1)
