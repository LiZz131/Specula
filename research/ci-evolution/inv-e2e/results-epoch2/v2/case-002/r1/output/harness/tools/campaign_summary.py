"""Render spec/output/mc/ledger.ndjson as a campaign table (markdown)."""
import json, sys, re
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print("| id | cfg | minutes | outcome | violation | stats | depth | log |")
print("|---|---|---:|---|---|---|---|---|")
for r in rows:
    import glob, os
    path = '/work/current/.specula-output/' + r['log']
    if not os.path.exists(path):
        alt = glob.glob(path[:-4] + '.*.log')
        r['log'] = alt[0].replace('/work/current/.specula-output/', '') if alt else r['log'] + ' (missing)'
        path = alt[0] if alt else None
    log = open(path).read() if path else ''
    if r['completed_no_error'] and ' 0 states left on queue' in (r['stats'] or ''):
        outcome = 'EXHAUSTED, no violation'
    elif r['completed_no_error']:
        outcome = 'BUDGET-LIMITED, no violation (LIMITED_COVERAGE)'
    elif r['violation']:
        outcome = 'VIOLATION'
    elif 'STOPPED' in log or 'superseded' in r['log'] or 'failed' in r['log']:
        outcome = 'stopped (replaced)'
    elif re.search(r'stopAfter|Stopping|exceeded', log) or r['exit'] in (0,):
        outcome = 'BUDGET-LIMITED (LIMITED_COVERAGE)'
    else:
        outcome = 'BUDGET-LIMITED/terminated exit=%s (LIMITED_COVERAGE)' % r['exit']
    print("| %s | %s | %s | %s | %s | %s | %s | %s |" % (r['id'], r['cfg'], r['minutes'], outcome,
          r['violation'] or '-', r['stats'] or '-', (r['depth'] or '-').replace('depth of the complete state graph search is ', ''), r['log']))
