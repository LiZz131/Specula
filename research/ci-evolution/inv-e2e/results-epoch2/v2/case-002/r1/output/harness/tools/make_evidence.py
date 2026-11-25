"""Build one-state / one-step TLC evidence modules from extracted trace states."""
import re, sys, os
def load(p): return open(p).read().strip()
def primed(block):
    return re.sub(r'^/\\ (\w+) =', r"/\\ \1' =", block, flags=re.M)
def edit_var(block, var, newval):
    # replace the full value of one variable (value may span lines)
    pat = re.compile(r'^/\\ ' + var + r' = .*?(?=^/\\ |\Z)', re.M | re.S)
    assert pat.search(block), var
    return pat.sub('/\\\\ ' + var + ' = ' + newval + '\n', block)
MC_EXTRA = """/\\ counters = [crash |-> 0, drop |-> 0, snapshot |-> 0]
/\\ seen = {}
/\\ everCommitted = {}"""
def module(name, body):
    return "---- MODULE %s ----\nEXTENDS Update\nOld == INSTANCE OldBase\n%s\n====\n" % (name, body)
def write(name, body, cfg):
    open(name + '.tla', 'w').write(module(name, body))
    open(name + '.cfg', 'w').write(cfg)
CONST = """CONSTANTS
    Server = {"s0", "s1", "s2"}
    Txn = {0, 1, 2, 3, 4, 5, 6, 7, 1000}
    MaxEpoch = 3
    Nil = "Nil"
    MaxCrash = 0
    MaxDrop = 0
    MaxSnapshot = 0
CHECK_DEADLOCK FALSE
"""
s97 = load('state-diffsync-l97.tla'); s96 = load('state-diffsync-l96.tla')
s91 = load('state-diffsync-l91.tla'); s92 = load('state-diffsync-l92.tla')
n11 = load('state-snap-l11.tla'); n12 = load('state-snap-l12.tla')
# ---- E2: state predicate on the trace state after the leader becomes active
rep2 = '''Report == PrintT(<<"%s", "new UpdEstablishedHistoryDurableOnQuorum", UpdEstablishedHistoryDurableOnQuorum,
                    "old", "not checked (no V0 counterpart)">>)'''
for nm, st in [('E2', s97), ('E2c', edit_var(s97, 'durable',
        '[s0 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>, s1 |-> <<[id |-> 1, epoch |-> 1]>>, s2 |-> <<[id |-> 1, epoch |-> 1], [id |-> 2, epoch |-> 1]>>]'))]:
    body = "EInit ==\n%s\n%s\nESpec == EInit /\\ [][UNCHANGED uvars]_uvars\n%s\n" % (st, MC_EXTRA, rep2 % nm)
    write(nm, body, "SPECIFICATION ESpec\n" + CONST + "INVARIANTS\n    Report\n    UpdEstablishedHistoryDurableOnQuorum\n")
# ---- E1: one-step action property at the NEWLEADER ACK
for nm, pre, post in [('E1', s91, s92), ('E1c', n11, n12)]:
    body = ("EInit ==\n%s\n%s\nENext ==\n%s\n/\\ UNCHANGED <<counters, seen, everCommitted>>\n"
            "ESpec == EInit /\\ [][ENext]_uvars\n"
            "Report == PrintT(<<\"%s\", \"pre-state newLeaderAcked/proposed/durable\", newLeaderAcked, proposed, durable>>)\n") % (pre, MC_EXTRA, primed(post), nm)
    write(nm, body, "SPECIFICATION ESpec\n" + CONST + "INVARIANTS\n    Report\nPROPERTIES\n    UpdNewLeaderAckAfterDurable\n")
# ---- K: kept affected properties, old vs new definitions on the changed-behaviour state
kprops = ['CommittedHistoriesPrefix', 'ApplyRequiresCommitCertificate', 'PipelinePrefix',
          'EpochHistoryConsistency', 'SyncCompletionJustified']
rep = 'Report == PrintT(<<"K", %s>>)' % ', '.join('<<"%s", "old", Old!%s, "new", %s>>' % (p, p, p) for p in kprops)
body = "EInit ==\n%s\n%s\nENext ==\n%s\n/\\ UNCHANGED <<counters, seen, everCommitted>>\nESpec == EInit /\\ [][ENext]_uvars\n%s\nOldNoIllegalRollback == [][Old!NoIllegalRollback]_uvars\n" % (s96, MC_EXTRA, primed(s97), rep)
write('K', body, "SPECIFICATION ESpec\n" + CONST + "INVARIANTS\n    Report\n" + ''.join('    %s\n' % p for p in kprops) + "PROPERTIES\n    HistoryPositionsMonotonicExceptRecovery\n    OldNoIllegalRollback\n")
print("written")
