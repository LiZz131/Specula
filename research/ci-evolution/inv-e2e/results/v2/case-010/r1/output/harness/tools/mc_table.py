"""Summarize TLC campaign logs into a Markdown table. Usage: mc_table.py <log>..."""
import re, sys, os
print("| Run | Mode | Result | Distinct states | Depth / traces | Queue left | Wall |")
print("|---|---|---|---:|---|---:|---|")
for p in sys.argv[1:]:
    t = open(p).read(); n = os.path.basename(p)[:-4]
    sim = 'simulat' in t[:3000].lower()
    viol = re.search(r'Error: (?:Invariant|Action property|Temporal property) (\w+) is violated', t)
    res = f"VIOLATION {viol.group(1)}" if viol else ("no violation" if 'Finished in' in t else "INCOMPLETE")
    ds = re.findall(r'([\d,]+) distinct states found', t)
    depth = re.findall(r'depth of the complete state graph search is (\d+)', t)
    q = re.findall(r'([\d,]+) states left on queue', t)
    tr = re.findall(r'([\d,]+) traces generated', t)
    gen = re.findall(r'The number of states generated: (\d+)', t)
    wall = re.findall(r'Finished in (.*?) at', t)
    if sim:
        print(f"| {n} | simulation d<=100 | {res} | {gen[-1] if gen else '-'} generated | {tr[-1] if tr else '-'} traces | - | {wall[-1] if wall else '-'} |")
    else:
        print(f"| {n} | BFS | {res} | {ds[-1] if ds else '-'} | {depth[-1] if depth else '-'} | {q[-1] if q else '-'} | {wall[-1] if wall else '-'} |")
