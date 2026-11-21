#!/usr/bin/env python3
"""Render spec/output/mc-summary.md from spec/output/command-results.ndjson."""
import json, re
root = '/work/current/.specula-output/spec'
rows = [json.loads(l) for l in open(f'{root}/output/command-results.ndjson')]
purpose = {
 'mc/MC-standard-bfs': 'Standard convergence round (reference invariants, MC.cfg)',
 'mc/MC-standard-bfs-r1-caseA': 'Standard round 1 (Case A PipelinePrefix, superseded)',
 'mc/update-full-bfs': 'Full update check: update + reference properties over full MCNext',
 'mc/update-focused-bfs': 'Concrete focused: Affected \\/ Interaction actions',
 'mc/update-open-bfs': 'Open focused: Affected \\/ Interaction \\/ EnvUpdate',
 'mc/update-discharge': 'Discharge: omitted TakeSnapshot/DropMessage satisfy EnvUpdate',
 'mc/sim-MC-standard': 'Simulation follow-up of MC.cfg',
 'mc/sim-update-full': 'Simulation follow-up of Update-full.cfg',
}
out = ['# Model-checking campaign summary (case-002)', '',
       'All TLC runs: tla2tools 2026.11.06, metadir under /dev/shm/specula-e2e-case-002 (removed after',
       'each run), outer `timeout` plus `-Dtlc2.TLC.stopAfter`. A run that stops at its time budget with',
       'states left on the queue is LIMITED_COVERAGE (bounded exploration, not a proof).', '',
       '| Campaign | Kind | Config | Result | States / depth | Coverage | Log |', '|---|---|---|---|---|---|---|']
for r in rows:
    if not r['id'].startswith('mc/'):
        continue
    st = r.get('states') or ''
    m = re.search(r'([0-9,]+) states left on queue', st)
    left = int(m.group(1).replace(',', '')) if m else None
    if r.get('violation'):
        res = 'VIOLATION: ' + r['violation']
    elif r['exit_code'] == 0:
        res = 'no violation'
    else:
        res = f"stopped (exit {r['exit_code']})"
    if r.get('classification'):
        res += ' — ' + r['classification']
    if r.get('violation'):
        cov = 'counterexample'
    elif left == 0:
        cov = 'exhausted (within bounds/constraint)'
    elif left:
        cov = 'LIMITED_COVERAGE (budget stop, queue non-empty)'
    else:
        cov = 'LIMITED_COVERAGE (simulation / stopped)'
    desc = purpose.get(r['id'], r['kind'])
    out.append(f"| {r['id']} — {desc} | {r['kind']} | {r['config']} | {res} | {st} depth={r.get('depth','')} | {cov} | {r['log']} |")
open(f'{root}/output/mc-summary.md', 'w').write('\n'.join(out) + '\n')
print('\n'.join(out[-40:]))
