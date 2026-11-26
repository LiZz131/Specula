#!/usr/bin/env python3
"""Summarize TLC logs under spec/output into spec/output/mc-campaign-summary.tsv."""
import re, sys, pathlib
out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else '.')
rows = []
for f in sorted(out.glob('*.log')):
    t = f.read_text(errors='replace')
    m = re.search(r'^# command: .*-config (\S+) (\S+)', t, re.M)
    if not m:
        continue
    cfg, module = m.group(1), m.group(2)
    sim = '-simulate' in t.splitlines()[0]
    viol = re.search(r'Error: (Invariant \S+ is violated|Action property \S+ is violated|.*Temporal properties were violated|TLC threw an unexpected exception)', t)
    fin = re.search(r'^# finished: (\S+) rc=(\d+)', t, re.M)
    rc = fin.group(2) if fin else 'running'
    done = 'Model checking completed. No error has been found.' in t
    prog = re.findall(r'Progress\((\d+)\) at [^:]+:\d+:\d+: ([\d,]+) states generated.*?, ([\d,]+) distinct states found.*?, ([\d,]+) states left on queue', t)
    simp = re.findall(r'Progress: (\d+) states checked, (\d+) traces generated', t)
    final = re.search(r'(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue', t)
    depth = re.search(r'depth of the complete state graph search is (\d+)', t)
    tl = len(re.findall(r'^State \d+:', t, re.M))
    if viol:
        result = viol.group(1) + (f' (trace {tl} states)' if tl else '')
    elif done:
        result = 'NO_VIOLATION_EXHAUSTIVE'
    elif rc == '124':
        result = 'NO_VIOLATION_BUDGET_LIMITED'
    elif rc in ('143', 'running'):
        result = 'STOPPED/RUNNING'
    else:
        result = f'rc={rc}'
    if sim and simp:
        cov = f'sim states_checked={simp[-1][0]} traces={simp[-1][1]}'
    elif final:
        cov = f'generated={final.group(1)} distinct={final.group(2)} queue={final.group(3)}' + (f' depth={depth.group(1)}' if depth else '')
    elif prog:
        p = prog[-1]
        cov = f'bfs_level={p[0]} generated={p[1]} distinct={p[2]} queue={p[3]}'
    else:
        cov = '-'
    rows.append((f.name, module, cfg, 'simulate' if sim else 'bfs', result, cov, rc))
with open(out / 'mc-campaign-summary.tsv', 'w') as w:
    w.write('log\tmodule\tcfg\tmode\tresult\tcoverage\trc\n')
    for r in rows:
        w.write('\t'.join(r) + '\n')
for r in rows:
    print('\t'.join(r))
