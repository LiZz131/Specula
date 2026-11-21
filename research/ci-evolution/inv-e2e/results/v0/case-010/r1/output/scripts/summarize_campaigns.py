#!/usr/bin/env python3
"""Summarize final TLC campaign logs into a markdown table (stdout)."""
import re, sys, glob, os
os.chdir('/work/current/.specula-output/spec/output')
rows=[]
for p in sorted(glob.glob('final-*.log')+glob.glob('final2-*.log')+glob.glob('final3-*.log')+glob.glob('final4-*.log')+glob.glob('final5-*.log')):
    if 'gate-trace' in p or 'nonvacuity' in p: continue
    t=open(p).read()
    cmd=re.search(r'-config (\S+)', t); cfg=cmd.group(1) if cmd else '?'
    mode='simulation' if '-simulate' in t.split('\n')[0] else 'BFS'
    ext=re.search(r'# exit: (\d+)', t); ext=ext.group(1) if ext else 'running'
    inv=re.search(r'Error: Invariant (\w+) is violated', t)
    prop=re.search(r'Error: (Action property|Temporal property) (\w+)', t)
    err=re.search(r'Error: (TLC threw|Parsing)', t)
    prog=re.findall(r'Progress\((\d+)\).*?([\d,]+) distinct states found.*?([\d,]+) states left', t)
    fin=re.search(r'([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue', t)
    simp=re.findall(r'Progress: ([\d,]+) states checked, ([\d,]+) traces generated', t)
    depth=re.search(r'The depth of the complete state graph search is (\d+)', t)
    states=depth_s=queue=''
    if fin: states, queue = fin.group(2), fin.group(3)
    elif prog: depth_s, states, queue = prog[-1]
    if depth: depth_s=depth.group(1)
    if mode=='simulation' and simp: states=f"{simp[-1][0]} checked / {simp[-1][1]} traces"
    if inv: res=f"violation: {inv.group(1)}"
    elif prop: res=f"violation: {prop.group(2)}"
    elif err: res="error (see log)"
    elif ext=='0': res="completed, no violation"
    elif ext=='124': res="time bound, no violation (LIMITED_COVERAGE)"
    else: res=f"exit {ext}"
    m=re.search(r'State (\d+): ', t[::-1][:0] or t)
    st=re.findall(r'\nState (\d+): ', t)
    cex_len = st[-1] if st and (inv or prop) else ''
    rows.append((p,cfg,mode,res,states,depth_s or '',queue,cex_len))
print('| Log | Config | Mode | Result | Distinct states | Depth/level | Queue left | Cex length |')
print('|---|---|---|---|---:|---:|---:|---:|')
for r in rows: print('| `%s` | `%s` | %s | %s | %s | %s | %s | %s |'%r)
