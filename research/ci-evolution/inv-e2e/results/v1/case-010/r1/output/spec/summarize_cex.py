import re,sys
txt=open(sys.argv[1]).read()
m=re.search(r'Error: (Invariant \w+ is violated|.*?violated.*?)\n',txt); print(m.group(0).strip() if m else "no error line")
blocks=re.findall(r'State (\d+): <([^>]*)>\n(.*?)(?=\nState \d+: |\n\n|\Z)', txt, re.S)
prev={}
skip=set(sys.argv[2].split(',')) if len(sys.argv)>2 else {'seen','counters'}
for num,act,body in blocks:
    vars={}
    for mm in re.finditer(r'^/\\ (\w+) = (.*?)(?=\n/\\ |\Z)', body, re.S|re.M):
        vars[mm.group(1)]=' '.join(mm.group(2).split())
    ch={k:v for k,v in vars.items() if prev.get(k)!=v and k not in skip}
    print(f"--- {num} {act.split(' line')[0]}")
    if num!='1':
        for k,v in ch.items(): print(f"   {k} = {v[:200]}")
    prev=vars
