#!/usr/bin/env python3
"""Print markdown tables (per arm x case x cfg; per arm counts; cost) from reparsed results.
Usage: tables.py <results.jsonl> <changes.json>"""
import json, sys, collections
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
ch = {(c['arm'], c['case'], c['cfg']): c for c in json.load(open(sys.argv[2]))}
R = {(r['arm'], r['case'], r['cfg'], r['variant'], r['mode']): r for r in rows}


def cell(r):
    if not r:
        return '-'
    if r['result'] == 'violation':
        return f"VIOLATION {r['violation']} (cex {r['cex_len']} states, {r['seconds']:.0f}s)"
    if r['result'] == 'exhausted':
        return f"exhausted ({r['distinct']} distinct, depth {r['depth']}, {r['seconds']:.0f}s)"
    if r['mode'] == 'bfs':
        return f"no violation in budget (depth {r['depth']}, {r['distinct']} distinct, queue {r['queue']})"
    if r['result'] == 'error':
        return 'ERROR ' + r['error']
    return f"no violation in budget ({r['states']} states, {r['traces']} traces)"


print('| arm | case | cfg | constants raised | +1 simulate (240 s, depth 100, seed 1) | +1 BFS (300 s, 8 workers) |')
print('|---|---|---|---|---|---|')
for (a, c, f), cc in sorted(ch.items()):
    chs = ', '.join(f"{x['const']} {x['old']}→{x['new']}" for x in cc['changes'])
    print(f"| {a} | {c} | {f} | {chs} | {cell(R.get((a, c, f, 'plus1', 'sim')))} | {cell(R.get((a, c, f, 'plus1', 'bfs')))} |")

print()
print('| arm | cfgs | cfgs with any violation at +1 | sim violations | BFS violations | BFS exhausted | sum of run seconds |')
print('|---|---|---|---|---|---|---|')
for a in ('v0', 'v1', 'v2'):
    cfgs = [k for k in ch if k[0] == a]
    anyv = sum(1 for k in cfgs if any(R.get(k + ('plus1', m), {}).get('result') == 'violation' for m in ('sim', 'bfs')))
    sv = sum(1 for k in cfgs if R.get(k + ('plus1', 'sim'), {}).get('result') == 'violation')
    bv = sum(1 for k in cfgs if R.get(k + ('plus1', 'bfs'), {}).get('result') == 'violation')
    be = sum(1 for k in cfgs if R.get(k + ('plus1', 'bfs'), {}).get('result') == 'exhausted')
    secs = sum(r['seconds'] for r in rows if r['arm'] == a)
    print(f'| {a} | {len(cfgs)} | {anyv} | {sv} | {bv} | {be} | {secs:.0f} |')

print()
print('| arm | case | sum of run seconds (sim + BFS + orig re-runs; runs overlapped) |')
print('|---|---|---|')
for (a, c) in sorted({(k[0], k[1]) for k in ch}):
    print(f"| {a} | {c} | {sum(r['seconds'] for r in rows if r['arm'] == a and r['case'] == c):.0f} |")
