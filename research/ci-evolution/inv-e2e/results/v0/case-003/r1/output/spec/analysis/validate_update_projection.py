"""Exhaustive old-vs-new projection of ConsensusParams.ValidateUpdate.

Transcribed line-by-line from
  old: /work/old-source/types/params.go:208-229
  new: /work/new-source/types/params.go:208-261
Inputs: c = current ABCI.VoteExtensionsEnableHeight, u = updated value
(None == updated.Abci nil), h = header.Height passed by
internal/state/execution.go:622. ValidateBasic (types/params.go:188-190) runs
first on the *resulting* params, so u < 0 is rejected there in both versions.
"""
import itertools, json, sys

def old_vu(c, u, h):
    if u is None: return True
    if c == u: return True
    if c != 0 and u == 0: return False
    if u <= h: return False
    if c <= h: return False
    return True

def new_vu(c, u, h):
    if u is None: return True                      # 1
    if u < 0: return False                         # 2
    if c <= 0 and u == 0: return True              # 3
    if c > 0 and u == 0:
        return not (c <= h)                        # 4 / 5
    if u <= h: return False                        # 6
    if c <= 0: return True                         # 7
    if c <= h: return False                        # 8
    return True                                    # 9

def basic_ok(c, u):
    v = c if u is None else u
    return v >= 0

def enabled(v, h):                                 # types/params.go:75-83
    return v != 0 and v <= h

rows = []
dom = range(-1, 8)
for c, h in itertools.product(range(0, 8), range(1, 7)):
    for u in [None] + list(dom):
        o = basic_ok(c, u) and old_vu(c, u, h)
        n = basic_ok(c, u) and new_vu(c, u, h)
        # closed form claimed in the analysis
        cf = (u is None) or (u >= 0 and not enabled(c, h) and not enabled(u, h))
        assert n == cf, (c, u, h)
        if o != n:
            rows.append(dict(c=c, u=u, h=h, old=o, new=n,
                             cls=("fix:enable-from-zero" if (c == 0 and u is not None and u > h) else
                                  "fix:cancel-future-proposal" if (c > h and u == 0) else
                                  "regression:unchanged-after-enable" if (u == c and enabled(c, h)) else
                                  "other")))
from collections import Counter
print("closed form for new accept == (Abci nil) or (u>=0 and not Enabled(c,h) and not Enabled(u,h)): verified on grid")
print("differing (c,u,h) tuples:", len(rows))
print(Counter(r["cls"] for r in rows))
for k in ["fix:enable-from-zero", "fix:cancel-future-proposal", "regression:unchanged-after-enable", "other"]:
    ex = [r for r in rows if r["cls"] == k][:3]
    print(k, ex)
