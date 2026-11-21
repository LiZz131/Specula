import re,sys
# usage: mkstate.py <tlc.log> <stateNumber|last> <EvidenceId> [<stateNumber2 for primed>]
log,which,eid=sys.argv[1],sys.argv[2],sys.argv[3]
txt=open(log).read()
blocks=re.findall(r'State (\d+): <([^>]*)>\n(.*?)(?=\nState \d+: |\n\n|\Z)', txt, re.S)
def get(n):
    b = blocks[-1] if n=='last' else [x for x in blocks if x[0]==n][0]
    vs={}
    for mm in re.finditer(r'^/\\ (\w+) = (.*?)(?=\n/\\ |\Z)', b[2], re.S|re.M):
        vs[mm.group(1)]=' '.join(mm.group(2).split())
    return b[0], b[1].split(' line')[0], vs
num,act,vs=get(which)
print(f"\\* source: {log} state {num} reached by {act}")
for k,v in vs.items():
    if k in ('counters','seen'): continue
    print(f"{eid}_{k} == {v}")
if len(sys.argv)>4:
    num2,act2,vs2=get(sys.argv[4])
    print(f"\\* successor: state {num2} reached by {act2}")
    for k,v in vs2.items():
        if k in ('counters','seen'): continue
        print(f"{eid}_{k}_next == {v}")
