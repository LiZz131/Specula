#!/usr/bin/env python3
"""Summarise every TLC campaign log spec/output/mc-*.log into
spec/output/campaign-summary.json and a Markdown table (stdout)."""
import glob, json, os, re
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'output')
rows = []
for log in sorted(glob.glob(os.path.join(OUT, 'mc-*.log'))):
    t = open(log, errors='replace').read()
    name = os.path.basename(log)[3:-4]
    cmd = re.search(r'^# cmd: (.*)$', t, re.M)
    cfg = re.search(r'-config (\S+)', cmd.group(1)).group(1) if cmd else None
    mode = 'simulation' if cmd and '-simulate' in cmd.group(1) else 'BFS'
    final = re.findall(r'^(\d+) states generated, (\d+) distinct states found, (\d+) states left on queue\.$', t, re.M)
    prog = re.findall(r'Progress\((\d+)\) at [^:]+:\d+:\d+: ([\d,]+) states generated.*?([\d,]+) distinct states found.*?([\d,]+) states left', t)
    sim = re.findall(r'Progress: (\d+) states checked, (\d+) traces generated', t)
    depth = re.findall(r'The depth of the complete state graph search is (\d+)', t)
    viol = re.findall(r'(?:Invariant|Action property|Temporal properties?) ?(\w*) (?:is|were) violated', t)
    verdict = re.findall(r'^# (?:corrected )?verdict: (.*)$', t, re.M)
    notes = re.findall(r'^# note: (.*)$', t, re.M)
    trace_len = len(re.findall(r'^State \d+: <', t, re.M))
    if mode == 'simulation' and verdict and verdict[-1].startswith('INCOMPLETE(rc=0)'):
        verdict = ['SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0)']
    r = {'run': name, 'config': cfg, 'mode': mode, 'verdict': verdict[-1] if verdict else 'RUNNING/UNKNOWN',
         'violation': viol[0] if viol else None, 'counterexample_states': trace_len or None,
         'log': 'spec/output/' + os.path.basename(log)}
    if final:
        g, d, q = final[-1]; r.update(generated=int(g), distinct=int(d), queue=int(q))
    elif prog:
        dp, g, d, q = prog[-1]; r.update(generated=int(g.replace(',', '')), distinct=int(d.replace(',', '')), queue=int(q.replace(',', '')), last_progress_depth=int(dp))
    if sim:
        r.update(states_checked=int(sim[-1][0]), traces=int(sim[-1][1]))
    if depth: r['depth'] = int(depth[-1])
    if notes: r['notes'] = notes
    rows.append(r)
json.dump(rows, open(os.path.join(OUT, 'campaign-summary.json'), 'w'), indent=1)
print('| Run | Config | Mode | Verdict | Violation | Distinct states | Depth | Queue left |')
print('|---|---|---|---|---|---|---|---|')
for r in rows:
    print('| %s | %s | %s | %s | %s | %s | %s | %s |' % (r['run'], r['config'], r['mode'], r['verdict'], r['violation'] or '-',
          r.get('distinct', r.get('states_checked', '-')), r.get('depth', r.get('last_progress_depth', '-')), r.get('queue', '-')))
