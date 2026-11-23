#!/usr/bin/env python3
"""Lightweight action check for case-012 (suggestion E2/M6): differential execution of a
line-by-line Python port of openraft VecProgress (buggy-tree openraft/src/progress/mod.rs)
against the idealised commit operator that v2's model uses (GreatestQuorumValue,
v2 spec/base.tla:169-178: the greatest stored value whose >=-set is a quorum of every group).

Usage: python3 vecprogress_diff.py [max_steps=4] [max_value=2]
       python3 vecprogress_diff.py --conform <trace.ndjson>...
The second form checks the port against real Rust executions: every ProgressUpdate event
(pre vector + committed, update(target, value)) recorded by the arms' harnesses is replayed on
the port and its post vector/committed compared (three trace formats: v0, v1, v2).
Exit code 1 if a divergence is found (expected on the buggy tree) / a conformance mismatch.
"""
import json
import itertools, sys

# ---- quorum sets (quorum/joint.rs:56-74, quorum/quorum_set_impl.rs:36-52) ----
class Joint:
    def __init__(self, groups): self.groups = [sorted(g) for g in groups]
    def ids(self):                       # BTreeSet union -> ascending ids (joint.rs:65-74)
        return sorted(set().union(*map(set, self.groups)))
    def is_quorum(self, it):             # every child majority (joint.rs:56-63)
        it = list(it)
        for g in self.groups:
            count, limit, ok = 0, len(g), False
            for i in it:                 # quorum_set_impl.rs:36-48 (count += 2 > len)
                if i in g:
                    count += 2
                    if count > limit: ok = True; break
            if not ok: return False
        return True
    def __repr__(self): return repr(self.groups)

# ---- VecProgress port (progress/mod.rs:80-232) ----
class VecProgress:
    def __init__(self, qs, default=0):           # new: mod.rs:80-89
        self.qs, self.default = qs, default
        self.committed = default
        self.vector = [[i, default] for i in qs.ids()]
    def index(self, target):                    # mod.rs:92-101
        for i, e in enumerate(self.vector):
            if e[0] == target: return i
        return None
    def move_up(self, index):                   # mod.rs:104-117
        for i in reversed(range(index)):
            if self.vector[i][1] < self.vector[i + 1][1]:
                self.vector[i], self.vector[i + 1] = self.vector[i + 1], self.vector[i]
            else:
                return i + 1
        return 0
    def update(self, id_, value):               # mod.rs:163-205
        index = self.index(id_)
        if index is None: return self.committed
        prev = self.vector[index][1]
        if prev == value: return self.committed
        assert value > prev                     # debug_assert!(value > prev)
        self.vector[index][1] = value           # mod.rs:182  (in place)
        if prev <= self.committed and self.committed < value:   # mod.rs:184
            new_index = self.move_up(index)
            for i in range(new_index, len(self.vector)):
                if self.vector[i][1] <= self.committed: break
                it = [x[0] for x in self.vector[0:i + 1]]
                if self.qs.is_quorum(it):
                    self.committed = self.vector[i][1]; break
        return self.committed
    def get(self, id_): return self.vector[self.index(id_)][1]
    def upgrade_quorum_set(self, qs):           # mod.rs:222-232
        n = VecProgress(qs, self.default)
        for i in self.qs.ids(): n.update(i, self.get(i))
        return n
    def sorted_above_committed(self):           # documented invariant, mod.rs:56-59
        above = [v for _, v in self.vector if v > self.committed]
        prefix = [v for _, v in self.vector[:len(above)]]
        return prefix == sorted(above, reverse=True) and all(v > self.committed for v in prefix)

def ideal(qs, values, default=0):
    """v2 GreatestQuorumValue: greatest stored v such that {j : val[j] >= v} is a quorum."""
    qv = [v for v in set(values.values()) if qs.is_quorum([j for j in values if values[j] >= v])]
    return max(qv) if qv else default

def search(groups, max_steps, max_value):
    qs = Joint(groups); ids = qs.ids()
    steps = [(i, v) for i in ids for v in range(1, max_value + 1)]
    total = bad = 0; first = None
    for n in range(1, max_steps + 1):
        for seq in itertools.product(steps, repeat=n):
            p = VecProgress(qs); vals = {i: 0 for i in ids}; ok = True
            for (i, v) in seq:
                if v <= vals[i]: ok = False; break      # values only grow (mod.rs:3-4)
                vals[i] = v; p.update(i, v)
            if not ok: continue
            total += 1
            if p.committed != ideal(qs, vals):
                bad += 1
                if first is None: first = (seq, p.committed, ideal(qs, vals), [tuple(e) for e in p.vector])
    return total, bad, first

def replay_tlc_cex():
    """The 11-state counterexample of v0 P-J-u1 / v1 P-J-full, at the VecProgress level.
    LogIds as (term, index); None = (0, -1)."""
    N = (0, -1)
    p = VecProgress(Joint([[1, 2, 3]]), N)                  # leader n2 elected, new_leader
    p.update(2, (1, 0)); p.update(1, (1, 0))                # blank entry, n1 ack -> commit (1,0)
    log = [("after blank ack", p.committed, [tuple(e) for e in p.vector])]
    p = p.upgrade_quorum_set(Joint([[1, 2, 3], [1, 3]]))      # joint append: upgrade (ids ascending)
    log.append(("after upgrade", p.committed, [tuple(e) for e in p.vector]))
    p.update(2, (1, 1))                                     # leader's own joint entry: prev>committed -> in place
    log.append(("leader self (1,1)", p.committed, [tuple(e) for e in p.vector]))
    p.update(3, (1, 1))                                     # n3 acks the joint entry
    vals = {i: p.get(i) for i in (1, 2, 3)}
    log.append(("n3 ack (1,1)", p.committed, [tuple(e) for e in p.vector]))
    return log, p.committed, ideal(Joint([[1, 2, 3], [1, 3]]), vals, N)

def _val(v):
    if isinstance(v, int): return v                                     # v2 progress test (u64)
    if isinstance(v, dict) and v.get("kind") == "raw": return v["raw"]   # v0 raw
    if isinstance(v, dict) and "index" in v:                            # LogId: (term, node, index)
        return (v.get("term", 0), int(v.get("node", 0) or 0), v["index"])
    if isinstance(v, dict) and "value" in v: return _val(v["value"])
    raise ValueError(v)

def _norm(e):
    """-> (groups, pre_vec, pre_committed, target, value, post_vec, post_committed) or None"""
    if "pre_values" in e:                                               # v2
        vec = lambda xs: [[x["id"], _val(x["value"])] for x in xs]
        return (e["configs"], vec(e["pre_values"]), _val(e["pre_committed"]), e["args"]["target"],
                _val(e["args"]["value"]), vec(e["post_values"]), _val(e["post_committed"]))
    if "pre_vector" in e:                                               # v1
        vec = lambda xs: [[x["id"], _val(x)] for x in xs]
        a = e["args"]
        return (e["configs"], vec(e["pre_vector"]), _val(e["pre_committed"]), a["target"], _val(a),
                vec(e["post_vector"]), _val(e["post_committed"]))
    if "pre" in e and "vector" in e["pre"]:                             # v0
        vec = lambda xs: [[x["id"], _val(x["value"])] for x in xs]
        return (e["pre"]["qs"], vec(e["pre"]["vector"]), _val(e["pre"]["committed"]), e["args"]["target"],
                _val(e["args"]["value"]), vec(e["post"]["vector"]), _val(e["post"]["committed"]))
    return None

def conform(files):
    ok = bad = 0
    for f in files:
        n_ok = n_bad = 0
        for line in open(f):
            if '"ProgressUpdate"' not in line: continue
            ev = json.loads(line); ev = ev.get("event", ev)
            t = _norm(ev)
            if t is None: continue
            groups, pre, pc, target, value, post, postc = t
            p = VecProgress(Joint(groups)); p.vector = [list(x) for x in pre]; p.committed = pc
            p.update(target, value)
            if p.vector == post and p.committed == postc: n_ok += 1
            else:
                n_bad += 1
                if n_bad == 1: print(f"  MISMATCH {f}: port {p.vector} c={p.committed} vs impl {post} c={postc}")
        print(f"{f}: {n_ok} events match, {n_bad} mismatch"); ok += n_ok; bad += n_bad
    print(f"total: {ok} match, {bad} mismatch")
    return bad

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--conform":
        sys.exit(1 if conform(sys.argv[2:]) else 0)
    k = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    mv = int(sys.argv[2]) if len(sys.argv) > 2 else 2
    found = False
    for groups in ([[1, 2, 3]], [[1, 2, 3], [1, 2]], [[1, 2, 3], [1, 3]], [[1, 2, 3], [2, 3]]):
        total, bad, first = search(groups, k, mv)
        print(f"quorum set {groups}: {total} monotone update sequences (<= {k} steps, values 1..{mv}); "
              f"{bad} diverge from GreatestQuorumValue")
        if first:
            found = True
            seq, got, want, vec = first
            print(f"  first: updates {list(seq)} -> VecProgress.committed={got}, ideal={want}, vector={vec}")
    print("\nReplay of the TLC counterexample (v0 P-J-u1 / v1 P-J-full) on the port:")
    log, got, want = replay_tlc_cex()
    for step, c, vec in log: print(f"  {step:18s} committed={c} vector={vec}")
    print(f"  => VecProgress committed {got}; GreatestQuorumValue {want}")
    found = found or got != want
    sys.exit(1 if found else 0)
