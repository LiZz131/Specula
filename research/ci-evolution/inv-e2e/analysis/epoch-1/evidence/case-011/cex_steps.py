import re,sys
KEEP=['role','effectiveConfig','preCandidateActive','preCandidateVote','preCandidateConfig','preGrants','crashed']
def recs(s):
    out=[];depth=0;start=None
    for i,ch in enumerate(s):
        if ch=='[':
            if depth==0: start=i
            depth+=1
        elif ch==']':
            depth-=1
            if depth==0: out.append(s[start:i+1])
    return [r for r in out if 'kind |->' in r]
def msum(r):
    g=lambda k: (re.search(k+r' \|-> ("?[\w]+"?)',r) or [None,'?'])[1].strip('"')
    t=re.search(r'vote \|-> \[term \|-> (\d+), node \|-> "(\w+)"',r)
    v=f" probe=({t.group(1)},n{t.group(2)})" if t and 'PreVote' in g('kind') else ''
    gr=' granted='+g('granted') if 'Resp' in g('kind') else ''
    return f"{g('kind')} n{g('source')}->n{g('dest')}{v}{gr}"
def compact(k,v):
    v=' '.join(v.split())
    if k in('preCandidateVote',):
        return ', '.join(f"n{a}:({b})" for a,b in re.findall(r'"(\w+)" :> \[term \|-> (\d+)',v))
    return v.replace('"','')
txt=open(sys.argv[1],errors='replace').read()
blocks=[b for b in re.split(r'\n(?=State \d+: )',txt) if re.match(r'State \d+: ',b)]
prev={};pm=[]
for b in blocks:
    n=re.match(r'State (\d+): (.*)',b); act=(re.search(r'<(\w+)',n.group(2)) or [None,n.group(2)[:30]])[1]
    V={m.group(1):m.group(2) for m in re.finditer(r'^/\\ (\w+) = (.*?)(?=\n/\\ |\Z)',b,re.S|re.M)}
    ms=recs(V.get('messages','')); add=[x for x in ms if x not in pm]; rem=[x for x in pm if x not in ms]
    line=f"[{n.group(1)}] {act}"
    if add: line+="  +"+" ; +".join(msum(x) for x in add)
    if rem: line+="  -"+" ; -".join(msum(x) for x in rem)
    print(line)
    for k in KEEP:
        if k in V and ' '.join(V[k].split())!=' '.join(prev.get(k,'').split()) and n.group(1)!='1': print(f"      {k}: {compact(k,V[k])}")
    prev=V; pm=ms
