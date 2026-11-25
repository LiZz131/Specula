import re, sys
old = open(sys.argv[1]).read().splitlines()
new = open(sys.argv[2]).read().splitlines()
def blocks(lines):
    out = {}; i = 0
    while i < len(lines):
        m = re.match(r'\\\* REQ-EVIDENCE (\w+)\s*$', lines[i])
        if m:
            j = i
            while j < len(lines) and lines[j].startswith('\\*'):
                j += 1
            out[m.group(1)] = (i, j)
            i = j
        else:
            i += 1
    return out
ob, nb = blocks(old), blocks(new)
result = list(new)
for name in sorted(nb, key=lambda n: -nb[n][0]):
    if name in ob and name != 'TypeOK':
        oi, oj = ob[name]; ni, nj = nb[name]
        newver = [l for l in new[ni:nj] if l.startswith('\\* verified:')]
        blk = [l for l in old[oi:oj]]
        blk = [ (newver[0] if l.startswith('\\* verified:') and newver else l) for l in blk]
        result[ni:nj] = blk
open(sys.argv[2], 'w').write('\n'.join(result) + '\n')
print('restored', [n for n in nb if n in ob and n != 'TypeOK'])
