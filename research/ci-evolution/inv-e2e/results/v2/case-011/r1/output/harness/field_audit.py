import json, glob, re, sys
root = sys.argv[1]
t = open(root + '/spec/Trace.tla').read()
# wrapper body per event name
wrappers = {}
for m in re.finditer(r'e\.name = "(\w+)"\s*->\s*(\w+)\(e\)', t):
    name, op = m.group(1), m.group(2)
    body = re.search(r'^' + op + r'\(e\) ==(.*?)(?=^\S)', t, re.S | re.M)
    wrappers[name] = body.group(1) if body else ''
helpers = {'SnapshotVote': ['term', 'node', 'committed'], 'SnapshotLog': ['present', 'term', 'node', 'index'],
           'JsonSet': [], 'JsonConfig': []}
seen = {}
for f in sorted(glob.glob(root + '/traces/*.ndjson')):
    for line in open(f):
        e = json.loads(line)['event']
        for k, v in e['args'].items():
            seen.setdefault((e['name'], k), set()).add(type(v).__name__)
print("State fields (pre via ValidatePre, post via ValidatePost; both use StateMatches):")
sm = re.search(r'StateMatches\(s,.*?\) ==(.*?)(?=^\S)', t, re.S | re.M).group(1)
state_fields = set()
for f in glob.glob(root + '/traces/*.ndjson'):
    for line in open(f):
        e = json.loads(line)['event']; state_fields |= set(e['pre']) | set(e['post'])
for x in sorted(state_fields):
    where = 'StateMatches' if re.search(r's\.' + x + r'\b', sm) else ('TracePreElect' if re.search(r'post\.' + x + r'\b', t) else None)
    print("  %-26s %s" % (x, 'CONSUMED by ' + where if where else 'NOT-CONSUMED'))
print("Event args (per wrapper):")
for (name, k), types in sorted(seen.items()):
    body = wrappers.get(name, '')
    m = re.search(r'(\w+)\(e\.args\.' + re.escape(k) + r'(\.\w+)?\)', body)
    direct = re.search(r'e\.args\.' + re.escape(k) + r'\b', body)
    if m:
        how = 'CONSUMED via %s' % m.group(1)
    elif direct:
        how = 'CONSUMED'
    else:
        how = 'NOT-CONSUMED'
    print("  %-22s %-20s %s" % (name, k, how))
