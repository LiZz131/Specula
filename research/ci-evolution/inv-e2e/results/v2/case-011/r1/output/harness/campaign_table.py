import re, glob, os, sys
root = sys.argv[1]
rows = []
for f in sorted(glob.glob(root + '/spec/output/mc-*.log')):
    t = open(f, errors='replace').read()
    head = re.search(r'# campaign=(\S+) module=(\S+) cfg=(\S+) mode=(\S+) budget=(\S+) workers=(\S+)', t)
    if not head: continue
    name, module, cfg, mode, budget, workers = head.groups()
    viol = re.search(r'Error: (Action property|Invariant) (\S+) is violated', t)
    dead = 'Error: Deadlock reached' in t
    comp = 'Model checking completed. No error has been found.' in t
    fin = re.search(r'# finished (\S+) rc=(\d+)', t)
    gen = re.findall(r'([\d,]+) states generated(?: \([^)]*\))?, ([\d,]+) distinct states found(?: \([^)]*\))?, ([\d,]+) states left on queue', t)
    depth = re.search(r'The depth of the complete state graph search is (\d+)', t)
    prog = re.findall(r'Progress\((\d+)\)', t)
    sim = re.findall(r'Progress: (\d+) states checked, (\d+) traces generated \(trace length: mean=(\d+)', t)
    simfinal = re.search(r'(\d+) states checked, (\d+) traces generated', t.split('Finished')[-1]) if 'Finished' in t else None
    if viol:
        states = len(re.findall(r'^State \d+:', t, re.M))
        outcome = 'VIOLATION %s (%d-state trace)' % (viol.group(2), states)
    elif dead:
        outcome = 'deadlock (bounded terminal state)'
    elif comp or (mode == 'sim' and 'Finished in' in t and 'Error' not in t):
        outcome = 'no violation (budget-limited)' if (mode == 'sim' or (gen and gen[-1][2] != '0')) else 'no violation (exhausted)'
    elif fin:
        outcome = 'ended rc=%s' % fin.group(2)
    else:
        outcome = 'RUNNING'
    if mode == 'sim':
        s = sim[-1] if sim else ('?', '?', '?')
        cov = '%s states checked, %s traces, mean length %s' % s
    else:
        g = gen[-1] if gen else ('?', '?', '?')
        d = depth.group(1) if depth else (prog[-1] if prog else '?')
        cov = '%s distinct, depth %s, queue %s' % (g[1], d, g[2])
    rows.append('| %s | %s | %s | %s | %s | %s |' % (name, cfg, mode, budget, outcome, cov))
print('| Campaign | Config (module Update unless MC) | Mode | Budget | Outcome | Coverage |')
print('|---|---|---|---|---|---|')
print('\n'.join(rows))
