import json, sys
for line in open(sys.argv[1]):
    r = json.loads(line)
    if r.get('tag') == 'config':
        print('CONFIG', r['node'], r['servers']); continue
    e = r['event']; s = e['state']
    skip = sys.argv[2:] 
    if e['name'] in skip: continue
    print(r['seq'], r['thread']['name'][:20], e['name'], e['node'], f"z={e['txnEpoch']}.{e['txnCounter']}",
          s['acceptedEpoch'], s['currentEpoch'], s['role'], s['phase'], s['syncMode'], e.get('peer',''), e.get('aux',''))
