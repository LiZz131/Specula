#!/usr/bin/env python3
"""Run TLC jobs with bounded concurrency; resumable; trims logs and counterexamples.
Usage: run_jobs.py <jobs.jsonl> <concurrency> <results.jsonl>
job: {id, arm, case, cfg, module, mode: sim|bfs, variant: plus1|orig, timeout}
Paths are fixed below (work copy, TLC jars, output dir)."""
import json, os, re, shutil, subprocess, sys, threading, time, glob
from concurrent.futures import ThreadPoolExecutor

WORK = '/mydata/bingzhuo/evidence-work/i5'
OUT = '/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/analysis/epoch-1/plus-one'
TLA2 = '/mydata/bingzhuo/src/Specula/lib/tla2tools.jar'
lock = threading.Lock()


def cp_for(arm, case):
    return TLA2 + ':' + f'/mydata/bingzhuo/inv-e2e/attempts/{arm}/{case}/r1/ws/lib/CommunityModules-deps.jar'


def parse(log):
    r = {'violation': '', 'kind': '', 'result': '', 'states': '', 'distinct': '', 'queue': '', 'depth': '',
         'traces': '', 'cex_len': '', 'error': ''}
    m = re.search(r'Error: Invariant (\S+) is violated', log)
    if m:
        r['violation'], r['kind'] = m.group(1), 'invariant'
    m2 = re.search(r'Error: Action property (\S+) is violated', log)
    if not r['violation'] and m2:
        r['violation'], r['kind'] = m2.group(1), 'action-property'
    if not r['violation'] and re.search(r'Error: Temporal properties were violated', log):
        r['violation'], r['kind'] = 'TemporalProperty', 'temporal'
    if not r['violation'] and re.search(r'Error: Deadlock reached', log):
        r['violation'], r['kind'] = 'Deadlock', 'deadlock'
    if r['violation']:
        r['result'] = 'violation'
        st = [int(x) for x in re.findall(r'^State (\d+):', log, flags=re.M)]
        if st:
            r['cex_len'] = max(st)
    elif 'Model checking completed. No error has been found.' in log:
        r['result'] = 'exhausted'
    elif re.search(r'^Error:|Exception|Assumption .* is false|Parse Error|Semantic errors', log, flags=re.M):
        r['result'] = 'error'
        m = re.search(r'^(Error:.*|.*Exception.*|Assumption.*false.*)$', log, flags=re.M)
        r['error'] = m.group(1)[:200] if m else 'error'
    else:
        r['result'] = 'no violation in budget'
    # BFS stats
    fin = re.findall(r'([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue', log)
    prog = re.findall(r'Progress\((\d+)\) at \S+ \S+: ([\d,]+) states generated(?: \([^)]*\))?, ([\d,]+) distinct states found(?: \([^)]*\))?, ([\d,]+) states left on queue', log)
    if fin:
        r['states'], r['distinct'], r['queue'] = [x.replace(',', '') for x in fin[-1]]
    elif prog:
        r['states'], r['distinct'], r['queue'] = [x.replace(',', '') for x in prog[-1][1:]]
    m = re.findall(r'The depth of the complete state graph search is (\d+)', log)
    if m:
        r['depth'] = m[-1]
    elif prog:
        r['depth'] = prog[-1][0]
    # simulation stats
    sp = re.findall(r'Progress: ([\d,]+) states checked, ([\d,]+) traces generated', log)
    if sp:
        r['states'], r['traces'] = sp[-1][0].replace(',', ''), sp[-1][1].replace(',', '')
    m = re.findall(r'The number of states generated: ([\d,]+)', log)
    if m:
        r['states'] = m[-1].replace(',', '')
    m = re.findall(r'Simulation using seed \S+ and aril \S+|traces generated', log)
    return r


def trim(log, maxcex=40000):
    lines = log.split('\n')
    keep = []
    for i, l in enumerate(lines):
        if l.startswith(('TLC2 Version', 'Running', 'Starting', 'Computed', 'Finished computing', 'Progress', 'Model checking completed',
                         'The depth', 'Finished in', 'Error:', 'Warning: The', 'Assumption')) or \
           re.search(r'states generated|distinct states|states checked|Exception|is violated|is false', l):
            keep.append(l[:400])
    # cap progress lines: first 2 + last 4
    prog = [k for k in keep if k.startswith('Progress')]
    if len(prog) > 6:
        drop = set(prog[2:-4])
        keep = [k for k in keep if k not in drop]
    # counterexample
    cex = ''
    idx = None
    for i, l in enumerate(lines):
        if l.startswith('Error: The behavior up to this point is') or l.startswith('Error: The following behavior') \
                or re.match(r'^State 1:', l):
            idx = i
            break
    if idx is not None:
        body = '\n'.join(lines[idx:])
        body = re.split(r'\n(?=\d+ states generated|The number of states generated|Finished in|Progress)', body)[0]
        if len(body) > maxcex:
            # keep the action header of every state, plus the full last two states
            blocks = re.split(r'\n(?=State \d+:|Back to state)', body)
            heads = [b.split('\n', 1)[0] for b in blocks]
            cex = '[trimmed: action headers of all %d blocks, full text of last 2]\n' % len(blocks) + \
                  '\n'.join(heads) + '\n\n' + '\n'.join(blocks[-2:])
            if len(cex) > maxcex:
                cex = cex[:maxcex] + '\n[truncated]'
        else:
            cex = body
    return '\n'.join(keep), cex


def run(job, resf):
    jid = job['id']
    cwd = os.path.join(WORK, job['arm'], job['case'])
    meta = os.path.join(WORK, 'meta', jid)
    os.makedirs(os.path.join(WORK, 'logs'), exist_ok=True)
    logp = os.path.join(WORK, 'logs', jid + '.log')
    if job['mode'] == 'sim':
        jv = ['-Xmx4g', '-XX:+UseParallelGC', '-XX:ParallelGCThreads=2']
        tlc = ['-simulate', '-depth', '100', '-seed', str(job.get('seed', 1)), '-workers', '1']
    else:
        jv = ['-Xmx16g', '-XX:+UseParallelGC', '-XX:ParallelGCThreads=8']
        tlc = ['-workers', '8', '-fpmem', '0.25']
    cmd = ['timeout', '-k', '15', str(job['timeout']), 'java'] + jv + ['-cp', cp_for(job['arm'], job['case']), 'tlc2.TLC'] + tlc + \
          ['-deadlock', '-nowarning', '-metadir', meta, '-config', job['cfgfile'], job['module'] + '.tla']
    t0 = time.time()
    with open(logp, 'w') as f:
        f.write('COMMAND: cd %s && %s\n' % (cwd, ' '.join(cmd)))
        f.flush()
        rc = subprocess.call(cmd, cwd=cwd, stdout=f, stderr=subprocess.STDOUT)
    secs = round(time.time() - t0, 1)
    shutil.rmtree(meta, ignore_errors=True)
    for p in glob.glob(os.path.join(cwd, '*_TTrace_*')):
        try:
            os.remove(p)
        except OSError:
            pass
    log = open(logp, errors='replace').read()
    r = parse(log)
    if rc == 124 and r['result'] in ('no violation in budget',):
        r['result'] = 'no violation in budget'
    tl, cex = trim(log)
    od = os.path.join(OUT, job['arm'], job['case'])
    os.makedirs(od, exist_ok=True)
    open(os.path.join(od, jid.split('__', 2)[-1] + '.log'), 'w').write(log.split('\n', 1)[0][:600] + '\n' + tl + '\n')
    if cex:
        open(os.path.join(od, jid.split('__', 2)[-1] + '.cex.txt'), 'w').write(cex)
    row = dict(job, rc=rc, seconds=secs, **r)
    with lock:
        with open(resf, 'a') as f:
            f.write(json.dumps(row) + '\n')
    print(time.strftime('%H:%M:%S'), jid, r['result'], r['violation'], r['depth'] or r['cex_len'], secs, flush=True)


def main():
    jobs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
    conc = int(sys.argv[2])
    resf = sys.argv[3]
    done = set()
    if os.path.exists(resf):
        done = {json.loads(l)['id'] for l in open(resf) if l.strip()}
    todo = [j for j in jobs if j['id'] not in done]
    print('todo', len(todo), flush=True)
    with ThreadPoolExecutor(conc) as ex:
        list(ex.map(lambda j: run(j, resf), todo))
    print('ALL DONE', flush=True)


if __name__ == '__main__':
    main()
