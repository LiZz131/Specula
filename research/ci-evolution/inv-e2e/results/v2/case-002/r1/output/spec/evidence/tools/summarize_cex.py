#!/usr/bin/env python3
import re,sys
txt=open(sys.argv[1]).read()
keys=sys.argv[2].split(',') if len(sys.argv)>2 else ['role','phase','acceptedEpoch','durable','queued','memHist','recovered','committed','nlAcks','commitCertified']
m=re.search(r'Error: (Invariant \S+ is violated|Action property \S+ is violated|Temporal properties were violated)',txt)
print(m.group(1) if m else 'no violation line')
parts=re.split(r'\nState (\d+): ',txt)
for i in range(1,len(parts),2):
    n=parts[i]; body=parts[i+1]; head=body.split('\n')[0]
    act=re.match(r'<(\w+)\(?([^)]*)\)?',head)
    print(f"[{n}] {act.group(1)}({act.group(2)})" if act else f"[{n}] {head[:60]}")
    if i+2>=len(parts) or n in sys.argv[3:]:
        for k in keys:
            mm=re.search(r'^/\\ '+k+r' = (.*?)(?=\n/\\ |\n\n|\Z)',body,re.S|re.M)
            if mm: print('     ',k,'=',re.sub(r'\s+',' ',mm.group(1))[:200])
