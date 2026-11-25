#!/usr/bin/env python3
"""Rebuild the last state of a TLC counterexample log as an Init and run
closure/control checks from it.

usage: make_witness.py <counterexample.log> <name>
Writes spec/witness/<name>/W_<name>.tla and three cfgs:
  closure_on   TickPreVoteModes={TRUE}, no crash/restart/operator: CanaryNoLeader must HOLD (exhaustive)
  closure_on_live  same, PreVoteLivelock must stay true in every reachable state (exhaustive)
  control_off  TickPreVoteModes={FALSE} (pre-update tick): CanaryNoLeader must be VIOLATED
"""
import os, re, sys, shutil, subprocess
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'evidence'))
import dumpstates as d

CP = '/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar'
HERE = os.path.dirname(os.path.abspath(__file__)); SPEC = os.path.dirname(HERE)

def last_state(log):
    text = open(log).read()
    # keep only the error trace part
    i = text.find('Error: The behavior up to this point is:')
    if i < 0:
        i = text.find('State 1:')
    tmp = os.path.join(HERE, '.tmp_states')
    open(tmp, 'w').write(re.sub(r'^State (\d+): <.*$', r'State \1:', text[i:], flags=re.M))
    st = d.parse(tmp); os.remove(tmp)
    s = st[-1]; s.pop('faultCounters', None)
    return s, len(st)

CFG = """CONSTANTS
    Server <- ReferenceServer
    NodeOrder <- ReferenceNodeOrder
    InitialConfig <- ReferenceInitialConfig
    MaxTerm = %(maxterm)s
    MaxLogIndex = 4
    TickPreVoteModes = %(modes)s
    MaxElectionCount = %(elections)s
    MaxExternalCount = 0
    MaxMembershipCount = 0
    MaxCrashCount = 0
    MaxRestartCount = 0
    MaxDropCount = 0
    MaxMessageCount = 8
SPECIFICATION WSpec
INVARIANTS
%(invs)s
"""

def main(log, name, maxterm='5', elections='4'):
    s, n = last_state(log)
    wd = os.path.join(HERE, name); os.makedirs(wd, exist_ok=True)
    for f in ['base.tla', 'MC.tla', 'Update.tla']:
        shutil.copy(os.path.join(SPEC, f), wd)
    mod = 'W_' + name
    open(os.path.join(wd, mod + '.tla'), 'w').write(
        '---- MODULE %s ----\n\\* Init = last state (%d) of %s\nEXTENDS Update\n'
        'WInit ==\n%s\n    /\\ faultCounters = [election |-> 0, external |-> 0, membership |-> 0, crash |-> 0, restart |-> 0, drop |-> 0]\n'
        'WSpec == WInit /\\ [][MCNext]_mcVars\n'
        'WVote == [i \\in Server |-> (%s)[i]]\n'
        'VotesFrozen == \\A i \\in LiveSet : vote[i] = WVote[i]\n'
        'NoLiveLeader == \\A i \\in LiveSet : role[i] /= "Leader"\n====\n' % (mod, n, os.path.relpath(log, SPEC), d.conj(s), s['vote'].replace('\n', ' ')))
    runs = {
        'closure_on': ('{TRUE}', '    NoLiveLeader\n    VotesFrozen\n    PreVoteLivelock'),
        'control_off': ('{FALSE}', '    NoLiveLeader'),
    }
    out = {}
    for r, (modes, invs) in runs.items():
        cfg = os.path.join(wd, r + '.cfg')
        open(cfg, 'w').write(CFG % dict(maxterm=maxterm, modes=modes, elections=elections, invs=invs))
        meta = '/dev/shm/specula-e2e-case-011/witness-%s-%s' % (name, r)
        cmd = ['java', '-XX:+UseParallelGC', '-cp', CP, 'tlc2.TLC', '-noGenerateSpecTE', '-workers', '8',
               '-metadir', meta, '-config', r + '.cfg', mod]
        p = subprocess.run(['timeout', '30m'] + cmd, cwd=wd, capture_output=True, text=True)
        shutil.rmtree(meta, ignore_errors=True)
        open(os.path.join(wd, r + '.log'), 'w').write('# cmd (cwd=%s): %s\n%s%s' % (wd, ' '.join(cmd), p.stdout, p.stderr))
        viol = re.findall(r'Invariant (\w+) is violated', p.stdout)
        stats = re.findall(r'^(\d+ states generated, \d+ distinct states found, \d+ states left on queue\.)$', p.stdout, re.M)
        out[r] = (viol, stats[-1] if stats else None)
        print(name, r, out[r])
    return out

if __name__ == '__main__':
    main(*sys.argv[1:])
