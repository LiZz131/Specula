#!/usr/bin/env python3
"""Summarize bounded TLC campaign logs (spec/output/<label>.log) into campaigns.md."""
import glob, os, re, sys
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
out = os.path.join(root, 'spec', 'output')
rows = []
for p in sorted(glob.glob(os.path.join(out, '*.log'))):
    name = os.path.basename(p)[:-4]
    txt = open(p, errors='replace').read()
    m = re.search(r'^# command: \(cd spec && (.*)\)$', txt, re.M)
    if not m:
        continue
    cmd = m.group(1)
    cfg = re.search(r'-config (\S+)', cmd).group(1)
    module = cmd.split()[-1]
    sim = '-simulate' in cmd
    mode = 'simulation' if sim else 'BFS'
    viol = re.search(r'Error: (Invariant|Action property|Temporal properties?) ?(\S*) (is|were) violated', txt)
    ex = re.search(r'^# exit: (\d+)', txt, re.M)
    gen = re.findall(r'([\d,]+) states generated', txt)
    dist = re.findall(r'([\d,]+) distinct states found', txt)
    left = re.findall(r'([\d,]+) states left on queue', txt)
    depth = re.search(r'depth of the complete state graph search is (\d+)', txt)
    simtraces = re.findall(r'(\d[\d,]*) traces generated|traces \(num\): (\d+)|generated (\d[\d,]*) traces', txt)
    done = 'Model checking completed. No error has been found.' in txt
    simstates = re.search(r'The number of states generated: (\d+)', txt)
    simtr = re.findall(r'(\d+) traces generated \(trace length: mean=(\d+)', txt)
    if sim and simstates:
        gen = [simstates.group(1)]
        dist = [f"{simtr[-1][0]} traces, mean len {simtr[-1][1]}" if simtr else '-']
        left = ['n/a']
    stopped = 'TLC stopped' in txt or 'stopAfter' in txt and not done
    if viol:
        res = f"VIOLATION {viol.group(1)} {viol.group(2)}".strip()
    elif done and not sim and left and left[-1] == '0':
        res = 'no violation; state space exhausted'
    elif done:
        res = 'no violation; budget-limited' if sim or (left and left[-1] != '0') else 'no violation'
    elif sim and simstates and ex is not None:
        res = 'no violation; budget-limited (simulation)'
    elif ex is None:
        res = 'RUNNING'
    else:
        res = f'no violation reported; stopped at budget (exit {ex.group(1)})'
    rows.append((name, module, cfg, mode, res, gen[-1] if gen else '-', dist[-1] if dist else '-',
                 left[-1] if left else '-', depth.group(1) if depth else '-', ex.group(1) if ex else '-'))
with open(os.path.join(out, 'campaigns.md'), 'w') as f:
    f.write('# Model-checking campaigns (run incr-705b7bab5f0d)\n\n')
    f.write('Budget-limited runs are LIMITED_COVERAGE, not proofs. Exact commands are the `# command:` header of each log.\n\n')
    f.write('| label (log) | module | cfg | mode | result | states generated | distinct (BFS) / traces (sim) | queue left | BFS depth | exit |\n|---|---|---|---|---|---|---|---|---|---|\n')
    for r in rows:
        f.write('| ' + ' | '.join([f'`spec/output/{r[0]}.log`'] + list(r[1:])) + ' |\n')
print(open(os.path.join(out, 'campaigns.md')).read())
