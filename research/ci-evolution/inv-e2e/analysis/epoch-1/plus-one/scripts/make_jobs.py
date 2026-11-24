#!/usr/bin/env python3
"""Make job lists from changes.json. Usage: make_jobs.py <changes.json> <workroot> <sim_secs> <bfs_secs>"""
import json, sys
ch = json.load(open(sys.argv[1]))
work, sim_t, bfs_t = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
for mode, t in (('sim', sim_t), ('bfs', bfs_t)):
    with open(f'{work}/jobs-{mode}.jsonl', 'w') as f:
        for c in ch:
            b = c['cfg'][:-4]
            f.write(json.dumps({'id': f"{c['arm']}__{c['case']}__{b}.plus1.{mode}", 'arm': c['arm'], 'case': c['case'],
                                'cfg': c['cfg'], 'cfgfile': c['plus1'], 'module': c['module'], 'mode': mode,
                                'variant': 'plus1', 'timeout': t}) + '\n')
