import json, sys
# usage: mutate.py src dst line_no(1-based) path value_json
src, dst, ln, path, val = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], json.loads(sys.argv[5])
lines = open(src).read().splitlines()
o = json.loads(lines[ln-1])
cur = o
keys = path.split('.')
for k in keys[:-1]:
    cur = cur[k]
cur[keys[-1]] = val
lines[ln-1] = json.dumps(o)
open(dst, 'w').write('\n'.join(lines) + '\n')
