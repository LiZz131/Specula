#!/usr/bin/env python3
"""Build and run the TLC evaluations recorded in spec/invariant-evidence.json.

Each evaluation is a one-state (or two-state) spec over the CURRENT variables;
the prior V0 definitions are evaluated through `OldB == INSTANCE OldBase`
(the prior base.tla with only its MODULE line renamed).
Run from spec/evidence:  python3 make_evidence.py
"""
import os, re, subprocess, sys, json, shutil
import dumpstates as d

CP = '/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar'
HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = os.path.dirname(HERE)
STATE_ROOT = '/dev/shm/specula-e2e-case-011/evidence'
FC0 = '[election |-> 0, external |-> 0, membership |-> 0, crash |-> 0, restart |-> 0, drop |-> 0]'

CFG = """CONSTANTS
    Server <- ReferenceServer
    NodeOrder <- ReferenceNodeOrder
    InitialConfig <- ReferenceInitialConfig
    MaxTerm = 3
    MaxLogIndex = 4
    TickPreVoteModes = %s
    MaxElectionCount = 1
    MaxExternalCount = 0
    MaxMembershipCount = 0
    MaxCrashCount = 0
    MaxRestartCount = 0
    MaxDropCount = 0
    MaxMessageCount = 9
SPECIFICATION ESpec
%s
"""

def state(trace, idx):
    st = d.parse(os.path.join(HERE, trace + '.dump'))
    s = dict(st[idx - 1]); s.pop('cursor', None)
    return s

def run(eid, body, cfgtail, modes='{TRUE, FALSE}'):
    wd = os.path.join(HERE, eid); os.makedirs(wd, exist_ok=True)
    for f in ['base.tla', 'MC.tla', 'Update.tla']:
        shutil.copy(os.path.join(SPEC, f), wd)
    shutil.copy(os.path.join(HERE, 'OldBase.tla'), wd)
    mod = 'E_' + eid.replace('-', '_')
    open(os.path.join(wd, mod + '.tla'), 'w').write(
        '---- MODULE %s ----\nEXTENDS Update, TLC\nOldB == INSTANCE OldBase\nFC0 == %s\n%s\n====\n' % (mod, FC0, body))
    open(os.path.join(wd, mod + '.cfg'), 'w').write(CFG % (modes, cfgtail))
    meta = os.path.join(STATE_ROOT, eid)
    os.makedirs(meta, exist_ok=True)
    cmd = ['java', '-cp', CP, 'tlc2.TLC', '-noGenerateSpecTE', '-workers', '1', '-metadir', meta,
           '-config', mod + '.cfg', mod]
    out = subprocess.run(['timeout', '5m'] + cmd, cwd=wd, capture_output=True, text=True)
    shutil.rmtree(meta, ignore_errors=True)
    log = '# cmd (cwd=%s): %s\n%s%s' % (wd, ' '.join(cmd), out.stdout, out.stderr)
    open(os.path.join(wd, 'tlc.log'), 'w').write(log)
    flat = re.sub(r'\n\s+', ' ', out.stdout)
    prints = [m.strip() for m in re.findall(r'(<<\s*"%s".*?>>)\s*(?:\n|$)' % re.escape(eid), flat)]
    violated = bool(re.search(r'is violated', out.stdout))
    return prints, violated

def one_state(s, override=None, extra=''):
    return 'S ==\n' + d.conj(s, override=override) + '\n    /\\ faultCounters = FC0\n' + \
           'ESpec == S /\\ [][UNCHANGED mcVars]_mcVars\n' + extra

results = {}
# ---- E-TYPE: TypeOK representation change (trace prevote_quorum_elect, post PreElect)
s = state('prevote_quorum_elect', 2)
results['E-TYPE'] = run('E-TYPE', one_state(s, extra='Report == PrintT(<<"E-TYPE", "old", OldB!TypeOK, "new", TypeOK>>)\n'),
                        'INVARIANT Report')
# control: a forged message kind must still be rejected by the new TypeOK
bogus = s['messages'].replace('kind |-> "PreVoteReq"', 'kind |-> "Bogus"', 1)
results['E-TYPEc'] = run('E-TYPEc', one_state(s, override={'messages': bogus},
                         extra='Report == PrintT(<<"E-TYPEc", "new", TypeOK>>)\n'), 'INVARIANT Report')
# ---- E-VRAD: keep VoteRequestAfterDurable (PreVoteReq above the durable vote is legal)
results['E-VRAD'] = run('E-VRAD', one_state(s, extra=(
    'PreVoteReqAboveDurable == \\E m \\in messages : m.kind = "PreVoteReq" /\\ VoteLT(durableVote[m.source], m.vote)\n'
    'ExtendedToPreVote == \\A m \\in messages : m.kind \\in {"VoteReq", "PreVoteReq"} => VoteLE(m.vote, durableVote[m.source])\n'
    'Report == PrintT(<<"E-VRAD", "records", PreVoteReqAboveDurable, "old", OldB!VoteRequestAfterDurable, "new", VoteRequestAfterDurable, "extended", ExtendedToPreVote>>)\n')),
    'INVARIANT Report')
# ---- E-GRAD: keep GrantedResponseAfterDurable (granted PreVoteResp in flight)
s2 = state('prevote_request_branches', 8)
results['E-GRAD'] = run('E-GRAD', one_state(s2, extra=(
    'GrantedPreVoteResp == \\E m \\in messages : m.kind = "PreVoteResp" /\\ m.granted\n'
    'Report == PrintT(<<"E-GRAD", "records", GrantedPreVoteResp, "old", OldB!GrantedResponseAfterDurable, "new", GrantedResponseAfterDurable>>)\n')),
    'INVARIANT Report')
# ---- E-ROLE: keep role/persistence invariants on the pre-vote-triggered election of a Leader
s3 = state('candidate_prevote_then_establish', 26)
results['E-ROLE'] = run('E-ROLE', one_state(s3, extra=(
    'Report == PrintT(<<"E-ROLE", "role1", role["1"], "vote1", vote["1"], "old",\n'
    '   <<OldB!LeaderRoleHasCommittedSelfVote, OldB!CandidateRoleHasPendingSelfVote, OldB!DurableVoteNotAhead>>,\n'
    '   "new", <<LeaderRoleHasCommittedSelfVote, CandidateRoleHasPendingSelfVote, DurableVoteNotAhead>>>>)\n')),
    'INVARIANT Report')
# ---- E-U1: PreCandidateProbesNextTerm (add). keep-state from trace (Leader with live round)
s4 = state('candidate_prevote_then_establish', 25)
results['E-U1k'] = run('E-U1k', one_state(s4, extra=(
    'Report == PrintT(<<"E-U1k", "preActive1", preActive["1"], "vote1", vote["1"], "preVote1", preVote["1"], "new", PreCandidateProbesNextTerm>>)\n')),
    'INVARIANT Report')
# separating (constructed): the node's vote moved to term 2 while the round probing term 2 survived
vote_sep = '[' + s4['vote'] + ' EXCEPT !["1"] = [term |-> 2, node |-> "3", committed |-> FALSE]]'
results['E-U1s'] = run('E-U1s', one_state(s4, override={'vote': vote_sep}, extra=(
    'Report == PrintT(<<"E-U1s", "vote1", vote["1"], "preVote1", preVote["1"], "new", PreCandidateProbesNextTerm>>)\n')),
    'INVARIANT Report')
# ---- E-U2: PreVoteQuorumNeverDemotesLeader (add). separating transition = trace events 4->5,
# with the consumed PreVoteResp put back into the pre-state's message set (short edit).
s5 = state('candidate_prevote_then_establish', 25); s6 = state('candidate_prevote_then_establish', 26)
R = ('MessageR("PreVoteResp", "3", "1", [term |-> 1, node |-> "1", committed |-> FALSE], '
     '[present |-> TRUE, term |-> 1, node |-> "1", index |-> 1], TRUE, FALSE, [term |-> 2, node |-> "1", committed |-> FALSE])')
def two_state(eid, post_override=None):
    body = ('S0 ==\n' + d.conj(s5, override={'messages': '(' + s5['messages'] + ') \\cup {' + R + '}'}) +
            '\n    /\\ faultCounters = FC0\n' +
            'S1p ==\n' + d.conj(s6, prime=True, override=post_override) + "\n    /\\ faultCounters' = FC0\n" +
            'ESpec == S0 /\\ [][(S0 /\\ S1p) \\/ UNCHANGED mcVars]_mcVars\n' +
            'Report == PrintT(<<"%s", "role1", role["1"], "preActive1", preActive["1"]>>)\n' % eid)
    return body
results['E-U2s'] = run('E-U2s', two_state('E-U2s'), 'INVARIANT Report\nPROPERTY PreVoteQuorumNeverDemotesLeader')
keep_leader = {'role': '[' + s6['role'] + ' EXCEPT !["1"] = "Leader"]',
               'vote': '[' + s6['vote'] + ' EXCEPT !["1"] = [term |-> 1, node |-> "1", committed |-> TRUE]]'}
results['E-U2c'] = run('E-U2c', two_state('E-U2c', post_override=keep_leader),
                       'INVARIANT Report\nPROPERTY PreVoteQuorumNeverDemotesLeader')
json.dump({k: {'prints': v[0], 'property_violated': v[1]} for k, v in results.items()},
          open(os.path.join(HERE, 'evidence-results.json'), 'w'), indent=1)
for k, v in results.items():
    print(k, v)
