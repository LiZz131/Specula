import re,sys,json,os
# usage: mkvariant.py <src_id> <new_id> '<json {field: value}>' '<json evals>' [two-state: '<json {field: value}> for S1']
src,new,over,evals=sys.argv[1],sys.argv[2],json.loads(sys.argv[3]),json.loads(sys.argv[4])
over1=json.loads(sys.argv[5]) if len(sys.argv)>5 else None
t=open(f"{src}/{src}.tla").read()
t=t.replace(f"MODULE {src} ----",f"MODULE {new} ----")
def setf(text, rec, field, val):
    pat=re.compile(r'(%s == \[.*?)(\b%s \|-> )(.*?)(,\n|\])' % (rec, field), re.S)
    m=pat.search(text); assert m, (rec, field)
    return text[:m.start(3)]+val+text[m.end(3):]
for k,v in over.items(): t=setf(t,"S0",k,v)
if over1 is not None:
    if "S1 ==" not in t:
        s0=re.search(r'S0 == \[.*?\]\n', t, re.S).group(0)
        t=t.replace(s0, s0+s0.replace("S0 ==","S1 ==",1))
        t=re.sub(r'ENext == UNCHANGED vars', "ENext == /\\\\ "+" /\\\\ ".join(f"{k}' = S1.{k}" for k in re.findall(r'^    /\\\\ (\w+) = S0\.\w+$', t, re.M)), t)
    for k,v in over1.items(): t=setf(t,"S1",k,v)
pr="PrintT(<<\""+new+"\", "+", ".join(f"<<\"{a}\", {b}>>" for a,b in evals)+">>)"
t=re.sub(r'PrintT\(<<.*?>>\)\n', pr+"\n", t, count=1, flags=re.S)
if over1 is not None and "ENext == /\\" in t and pr not in t.split("ENext ==")[1]:
    t=t.replace("\nESpec ==", "\n         /\\ "+pr+"\nESpec ==") if False else t
os.makedirs(new, exist_ok=True)
open(f"{new}/{new}.tla","w").write(t)
open(f"{new}/{new}.cfg","w").write(open(f"{src}/{src}.cfg").read())
print("wrote",new)
