import re, sys
path, out = sys.argv[1], sys.argv[2]
lines = open(path, errors='replace').read().split('\n')
start = max(i for i, l in enumerate(lines) if 'isolate leader 0' in l)
pat = re.compile(r'(becomes leader|steps down|a quorum would grant the vote; starting a real election|a quorum granted my vote|: trigger pre-vote$|: trigger election$|new candidate:|new pre-candidate:|vote is changing from|panicked|establish_leader)')
res = []
for l in lines[start:]:
    if 'RaftCore#' in l and '{id=1 ' not in l:
        continue
    m = pat.search(l)
    if not m:
        continue
    ts = l[:27]
    st = re.findall(r'\{state=(\w+) id=1\}', l)
    fn = re.findall(r'openraft::[\w:]+@(\w+)#', l)
    msg = l.rsplit(': ', 1)[-1][:160]
    res.append('%s state=%s fn=%s :: %s' % (ts, st[-1] if st else '-', fn[-1] if fn else '-', msg))
open(out, 'w').write('\n'.join(res) + '\n')
print('\n'.join(res[:40]))
