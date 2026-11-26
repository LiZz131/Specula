#!/usr/bin/env python3
"""Regenerate spec/output/campaign-summary.md from the TLC logs of this run."""
import re, glob, os
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(root, 'spec', 'output')
rows = []
for log in sorted(glob.glob(os.path.join(out, '*.log'))):
    name = os.path.basename(log)[:-4]
    s = open(log, errors='replace').read()
    if '# command:' not in s or 'tlc2' not in s and 'TLC' not in s:
        continue
    cmd = re.search(r'# command: (.*)', s)
    cfg = re.search(r'-config (\S+)', cmd.group(1)) if cmd else None
    mode = 'simulation' if '-simulate' in (cmd.group(1) if cmd else '') else 'BFS'
    viol = re.search(r'(Invariant \w+ is violated|Action property \w+ is violated|Temporal properties were violated)', s)
    done = 'Model checking completed. No error has been found.' in s
    dist = re.findall(r'(\d+) distinct states found, (\d+) states left on queue', s)
    checked = re.findall(r'Progress: ([\d,]+) states checked, ([\d,]+) traces generated', s)
    depth = re.search(r'depth of the complete state graph search is (\d+)', s)
    ex = re.search(r'# exit: (\d+)', s)
    if viol:
        outcome = 'VIOLATION: ' + viol.group(1)
    elif done and dist and dist[-1][1] == '0':
        outcome = 'no violation (state space exhausted)'
    elif done:
        outcome = 'no violation (budget-stopped: LIMITED_COVERAGE)'
    elif mode == 'simulation' and 'Finished in' in s:
        outcome = 'no violation (simulation budget: LIMITED_COVERAGE)'
    elif ex is None:
        outcome = 'RUNNING/INCOMPLETE'
    else:
        outcome = f'exit {ex.group(1)}'
    states = f'{dist[-1][0]} distinct, queue {dist[-1][1]}' if dist else (f'{checked[-1][0]} states, {checked[-1][1]} traces' if checked else '')
    rows.append((name, cfg.group(1) if cfg else '?', mode, outcome, states, depth.group(1) if depth else ''))
with open(os.path.join(out, 'campaign-summary.md'), 'w') as f:
    f.write('| run (spec/output/<run>.log) | cfg | mode | outcome | states | BFS depth |\n|---|---|---|---|---|---|\n')
    for r in rows:
        f.write('| ' + ' | '.join(r) + ' |\n')
print(len(rows))
