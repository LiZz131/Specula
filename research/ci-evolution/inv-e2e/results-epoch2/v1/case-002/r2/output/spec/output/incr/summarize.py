#!/usr/bin/env python3
"""Render spec/model-checking-summary.md from command-results.ndjson (latest record per run id)."""
import json, os, re
here = os.path.dirname(os.path.abspath(__file__))
recs = {}
for l in open(os.path.join(here, 'command-results.ndjson')):
    r = json.loads(l); recs[r['id']] = r
order = [k for k in recs if not k.startswith(('trace-', 'archived-', 'control-'))]
rows = []
for k in order:
    r = recs[k]; log = os.path.join('/work/current/.specular-output', r['log'])
    txt = open(log, errors='replace').read() if os.path.exists(log) else ''
    viol = re.findall(r'(Invariant \w+ is violated|Temporal property \w+ was violated|Action property \w+ is violated)', txt)
    timed_out = r['exit_code'] == 124
    if viol: outcome = viol[0]
    elif r['completed']: outcome = 'no violation; search exhausted within the configured bound'
    elif timed_out: outcome = 'no violation; stopped at time budget (LIMITED_COVERAGE)'
    else: outcome = 'exit %s' % r['exit_code']
    depth = r['depth'] or (re.findall(r'Progress\((\d+)\)', txt) or ['?'])[-1]
    sim = re.findall(r'Progress: (\d+) states checked, (\d+) traces generated \(trace length: mean=(\d+)', txt)
    if '-simulate' in r['command'] and sim:
        r = dict(r); r['distinct_states'] = sim[-1][0] + ' checked (sim)'; r['states_left'] = sim[-1][1] + ' traces'
        depth = 'mean ' + sim[-1][2]
    cfg = re.search(r'-config (\S+)', r['command']); spec = r['command'].split()[-1]
    rows.append(f"| {k} | {spec} / {cfg.group(1) if cfg else '?'} | {r['distinct_states'] or '?'} | {r['states_left'] or '?'} | {depth} | {outcome} | {r['log']} |")
out = ['# Model-checking summary (run incr-8c80add29fe2)', '',
       'Generated from `spec/output/incr/command-results.ndjson` (latest record per run id; superseded runs are kept as',
       '`*-r1-pre-discovery-guard.log` / `*-attempt1-*.log`). Bounded explorations are LIMITED_COVERAGE, never proofs.', '',
       '| Run | Spec / cfg | Distinct states | Left on queue | Depth | Outcome | Log |', '|---|---|---:|---:|---:|---|---|'] + rows
open('/work/current/.specular-output/spec/model-checking-summary.md', 'w').write('\n'.join(out) + '\n')
print('\n'.join(out[-len(rows):]))
