import re, sys
path, out, marker = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path, errors='replace').read().split('\n')
start = max(i for i, l in enumerate(lines) if marker in l)
pat = re.compile(r'(--- |new pre-candidate|a quorum would grant|handle_pre_vote_resp|ignored because|panicked|become_following|voting:)')
res = []
for l in lines[start:]:
    if 'RaftCore#' in l and '{id=1 ' not in l:
        continue
    if not pat.search(l):
        continue
    st = re.findall(r'\{state=(\w+) id=1\}', l)
    fn = re.findall(r'openraft::[\w:]+@(\w+)#', l)
    msg = l.rsplit(': ', 1)[-1][:200]
    res.append('%s state=%s fn=%s :: %s' % (l[:27], st[-1] if st else '-', fn[-1] if fn else '-', msg))
open(out, 'w').write('\n'.join(res) + '\n')
print('\n'.join(res[:30]))
