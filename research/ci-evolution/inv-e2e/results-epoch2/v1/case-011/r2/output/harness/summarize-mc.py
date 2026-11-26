#!/usr/bin/env python3
"""Summarize spec/output/mc-*.log TLC runs into a Markdown table (stdout)."""
import glob, os, re, sys
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'spec', 'output')
rows = []
for f in sorted(glob.glob(os.path.join(out, 'mc-*.log'))):
    s = open(f, errors='replace').read()
    cmd = re.search(r'# command: .* -config (\S+) .*?(\S+)\s*(\(TLC|$)', s)
    cfg = re.search(r'-config (\S+)', s)
    sim = '-simulate' in s.split('\n', 1)[0]
    viol = re.search(r'Error: (Invariant|Action property) (\w+) is violated', s)
    other = re.search(r'^Error: (.*)$', s, re.M)
    done = re.search(r'Model checking completed\. No error has been found', s)
    stats = re.findall(r'([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue', s)
    depth = re.findall(r'The depth of the complete state graph search is (\d+)', s)
    simst = re.findall(r'Progress: (\d+) states checked, (\d+) traces generated \(trace length: mean=(\d+)', s)
    fin = re.search(r'# finished: (\S+) rc=(\d+)', s)
    dur = re.findall(r'Finished in (.+?) at', s)
    if viol:
        outcome = f'VIOLATION {viol.group(1).lower()} {viol.group(2)}'
    elif other and 'is violated' not in other.group(1):
        outcome = 'ERROR ' + other.group(1)[:60]
    elif done and stats and stats[-1][2] == '0':
        outcome = 'completed, no violation (exhaustive: queue 0)'
    elif fin and fin.group(2) == '0':
        outcome = 'no violation; stopped at time budget' if not sim else 'no violation; simulation time budget'
    elif not fin:
        outcome = 'RUNNING/INTERRUPTED'
    else:
        outcome = f'rc={fin.group(2)}'
    if sim and simst:
        cov = f'{simst[-1][0]} states checked, {simst[-1][1]} traces, mean length {simst[-1][2]}'
    elif stats:
        g, d, q = stats[-1]
        cov = f'{d} distinct / {g} generated, queue {q}, depth {depth[-1] if depth else "?"}'
    else:
        cov = '-'
    rows.append((os.path.basename(f), cfg.group(1) if cfg else '?', 'simulation' if sim else 'BFS', outcome, cov, dur[-1] if dur else '-'))
print('| log | cfg | mode | outcome | coverage | duration |')
print('|---|---|---|---|---|---|')
for r in rows:
    print('| ' + ' | '.join(r) + ' |')
