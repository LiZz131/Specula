"""Summarise a TLC counterexample: per step, the action label, message changes and the
changed values of the KEEP variables. usage: cex_steps.py <tlc.log> [var,var,...]"""
import re,sys
KEEP=['role','currentTerm','lastLog','committed','effectiveConfig','progVec','progCommitted',
      'progress','matchedIndex','progressConfig','leaderState','leaderActive']
if len(sys.argv)>2: KEEP=sys.argv[2].split(',')
def recs(s):
    out=[];depth=0;start=None
    for i,ch in enumerate(s):
        if ch=='[':
            if depth==0: start=i
            depth+=1
        elif ch==']':
            depth-=1
            if depth==0: out.append(s[start:i+1])
    return [r for r in out if '|->' in r]
def msum(r):
    g=lambda k:(re.search(r'\b'+k+r' \|-> ("?[\w-]+"?)',r) or [None,None])[1]
    parts=[(g('type') or g('kind') or '?').strip('"'),f"{g('from') or g('source')}->{g('to') or g('dest')}"]
    for k in ('term','prev','last','ok','granted','leaderCommit'):
        v=g(k)
        if v is not None: parts.append(f"{k}={v.strip(chr(34))}")
    return ' '.join(parts)
txt=open(sys.argv[1],errors='replace').read()
blocks=[b for b in re.split(r'\n(?=State \d+: )',txt) if re.match(r'State \d+: ',b)]
prev={};pm=[]
for b in blocks:
    n=re.match(r'State (\d+): (.*)',b); lab=n.group(2)
    act=(re.search(r'<(\w+)',lab) or [None,lab[:30]])[1]
    V={m.group(1):' '.join(m.group(2).split()) for m in re.finditer(r'^/\\ (\w+) = (.*?)(?=\n/\\ |\n\n|\Z)',b,re.S|re.M)}
    ms=recs(V.get('messages','')); add=[x for x in ms if x not in pm]; rem=[x for x in pm if x not in ms]
    line=f"[{n.group(1)}] {act}"
    if add: line+="  +"+" ; +".join(msum(x) for x in add)
    if rem: line+="  -"+" ; -".join(msum(x) for x in rem)
    print(line)
    for k in KEEP:
        if k in V and V[k]!=prev.get(k) and n.group(1)!='1': print(f"      {k}: {V[k].replace(chr(34),'')}")
    prev=V; pm=ms
