#!/usr/bin/env python3
"""Summarize spec/output/mc-*.log into a Markdown table (outcome classification
is derived from TLC output: violation / exhaustive / budget-limited)."""
import re, glob, os, sys
rows = []
for p in sorted(glob.glob(os.path.join(sys.argv[1], 'mc-*.log'))):
    t = open(p, errors='replace').read()
    name = os.path.basename(p)[3:-4]
    cmd = re.search(r'# command: .*?-config (\S+) (\S+)', t)
    cfg = cmd.group(1) if cmd else '?'
    mode = 'sim' if '-simulate' in (t.split('\n')[0]) else 'bfs'
    viol = re.search(r'^Error: (Invariant \S+ is violated|Action property \S+ is violated|.*?violated.*)$', t, re.M)
    gen = re.findall(r'^(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue', t, re.M)
    simn = re.findall(r'The number of states generated: (\d+)', t)
    traces = re.findall(r'(\d+) traces generated', t)
    depth = re.findall(r'depth of the complete state graph search is (\d+)', t)
    fin = re.search(r'Finished in (.*?) at', t)
    rc = re.search(r'# finished: .* rc=(\d+)', t)
    if viol:
        outcome = 'VIOLATION: ' + viol.group(1)
    elif mode == 'bfs' and gen and gen[-1][2] == '0':
        outcome = 'no violation; state space exhausted'
    elif rc and rc.group(1) == '0':
        outcome = 'no violation; LIMITED_COVERAGE (time budget)'
    else:
        outcome = f'rc={rc.group(1) if rc else "?"} (see log)'
    if mode == 'bfs' and gen:
        g, d, q = gen[-1]; stats = f'{int(g):,} gen / {int(d):,} distinct / {int(q):,} queued'
    elif simn:
        stats = f'{int(simn[-1]):,} states; {int(traces[-1]):,} traces' if traces else f'{int(simn[-1]):,} states'
    else:
        stats = '-'
    rows.append(f'| {name} | `{cfg}` | {mode} | {outcome} | {stats} | {depth[-1] if depth else "-"} | {fin.group(1) if fin else "-"} |')
print('| Run | Config | Mode | Outcome | States | Depth | Time |\n|---|---|---|---|---|---|---|\n' + '\n'.join(rows))
