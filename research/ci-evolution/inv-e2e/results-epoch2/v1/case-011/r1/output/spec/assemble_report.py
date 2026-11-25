#!/usr/bin/env python3
"""Assemble spec/bug-report.md from the part files and campaign-summary.json."""
import json, os
S = os.path.dirname(os.path.abspath(__file__))
rows = json.load(open(os.path.join(S, 'output', 'campaign-summary.json')))
scen = {'MC': 'V0 standard', 'MC-membership': 'V0 standard (single voter seed)', 'Update_full': 'full update (all)',
        'Update_full_cont1': 'full update (MC-2 disabled)', 'Update_full_cont2': 'full update (MC-1, MC-2 disabled)',
        'Update_full_cont2-sim': 'full update (MC-1, MC-2 disabled)', 'Update_focused': 'concrete focused', 'Update_focused-sim': 'concrete focused',
        'Update_focused_cont': 'concrete focused (MC-1, MC-2 disabled)', 'Update_open': 'open focused (EnvUpdate)',
        'Update_open_cont': 'open focused (MC-1, MC-2 disabled)', 'Update_open-evalerror': 'open focused (aborted: TLC evaluation error)',
        'Update_discharge': 'discharge (EnvUpdate)', 'hunt-leader-demote-bfs': 'U-S3', 'hunt-leader-demote-cont': 'U-S3 (MC-2 disabled)',
        'hunt-leader-demote-cont-sim': 'U-S3 (MC-2 disabled)', 'hunt-livelock-bfs': 'U-S2', 'hunt-livelock-phased-bfs': 'U-S2 (phased monitor)',
        'hunt-livelock-cont-sim': 'U-S2 (MC-1 disabled)', 'hunt-livelock-directed-bfs': 'U-S2 (monitor, superseded)',
        'hunt-livelock-directed-sim': 'U-S2 (reduced domains, superseded)'}
out = [open(os.path.join(S, 'bug-report-head.part.md')).read()]
out.append('## Campaigns\n\n| Run | Scenario | Config | Mode | Outcome | Violation | Distinct states / sim states | Depth | Queue left | Log |\n|---|---|---|---|---|---|---|---|---|---|\n')
for r in rows:
    if r['run'].startswith('canary-'):
        continue
    out.append('| %s | %s | `%s` | %s | %s | %s | %s | %s | %s | `%s` |\n' % (
        r['run'], scen.get(r['run'], ''), r['config'], r['mode'], r['verdict'] + (' — ' + '; '.join(r['notes']) if r.get('notes') else ''), r['violation'] or '-',
        r.get('distinct', r.get('states_checked', '-')), r.get('depth', r.get('last_progress_depth', '-')),
        r.get('queue', '-'), r['log']))
out.append('\nReachability canaries (each expected VIOLATED = reachable): ' + ', '.join(
    '%s (%s, %s states)' % (r['run'][7:], 'reached' if r['violation'] else 'not reached', r.get('counterexample_states') or '-')
    for r in rows if r['run'].startswith('canary-')) +
    '. `CanaryNoPreVoteTally` was retired (unreachable by construction with three uniform voters).\n\n')
out.append(open(os.path.join(S, 'bug-report-mc1.part.md')).read() + '\n---\n\n')
out.append(open(os.path.join(S, 'bug-report-mc2.part.md')).read())
out.append('\n---\n\n## Not Reproduced\n\n| Scenario | Config | States Explored | Result |\n|---|---|---|---|\n')
for r in rows:
    if r['run'].startswith('canary-') or r['violation'] or 'ERROR' in r['verdict']:
        continue
    res = ('Stopped early by operator (superseded); no violation before stop' if 'rc=143' in r['verdict']
           else 'No violation (%s)' % r['verdict'])
    out.append('| %s | `%s` (%s) | %s | %s |\n' % (scen.get(r['run'], r['run']), r['config'], r['mode'],
               r.get('distinct', r.get('states_checked', '-')), res))
out.append(open(os.path.join(S, 'bug-report-tail.part.md')).read())
open(os.path.join(S, 'bug-report.md'), 'w').write(''.join(out))
print('bug-report.md written')
