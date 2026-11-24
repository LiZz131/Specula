#!/usr/bin/env python3
"""Build runs.csv from results.jsonl + changes.json. Usage: summarize.py <results.jsonl> <changes.json> <runs.csv>"""
import csv, json, sys
res = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ch = {(c['arm'], c['case'], c['cfg']): c for c in json.load(open(sys.argv[2]))}
cols = ['arm', 'case', 'cfg', 'module', 'variant', 'mode', 'constants_changed', 'timeout_s', 'seconds', 'result',
        'violation', 'kind', 'cex_states', 'bfs_depth', 'states', 'distinct', 'queue', 'sim_traces', 'error']
order = {'sim': 0, 'bfs': 1}
res.sort(key=lambda r: (r['arm'], r['case'], r['cfg'], r['variant'] != 'plus1', order.get(r['mode'], 2)))
with open(sys.argv[3], 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(cols)
    for r in res:
        c = ch.get((r['arm'], r['case'], r['cfg']), {'changes': []})
        cc = ' '.join(f"{x['const']}:{x['old']}->{x['new']}" for x in c['changes']) if r['variant'] == 'plus1' else '(original)'
        w.writerow([r['arm'], r['case'], r['cfg'], r['module'], r['variant'], r['mode'], cc, r['timeout'], r['seconds'],
                    r['result'], r['violation'], r['kind'], r['cex_len'], r['depth'], r['states'], r['distinct'],
                    r['queue'], r['traces'], r['error']])
print(len(res), 'rows')
