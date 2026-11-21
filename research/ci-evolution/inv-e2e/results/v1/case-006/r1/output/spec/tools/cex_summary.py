"""Summarize a TLC -dumpTrace json counterexample for this Raft model.
Usage: python3 -I cex_summary.py <cex.json>
Infers each step's action from the state diff (TLC labels focused steps only
by the disjunct of the Next relation)."""
import json, sys

def msgkey(m):
    return (m["mtype"], m["from"], m["to"], m["term"], m["index"], m.get("ctx"), m.get("reject"), m.get("commit"), m.get("entryTerm"))

def fmt(m):
    return f'{m["mtype"]}({m["from"]}->{m["to"]},t{m["term"]},i{m["index"]},c{m["commit"]},ctx={m["ctx"]},rej={m["reject"]})'

d = json.load(open(sys.argv[1]))
states = [s[1] for s in d["counterexample"]["state"]]
prev = None
for k, s in enumerate(states, 1):
    if prev is None:
        print(f"{k:2d} Init")
        prev = s
        continue
    pm = {msgkey(m): m for m in prev["messages"]}
    cm = {msgkey(m): m for m in s["messages"]}
    gone = [fmt(pm[x]) for x in pm if x not in cm]
    new = [fmt(cm[x]) for x in cm if x not in pm]
    ch = []
    for i in sorted(s["term"]):
        parts = []
        for v in ["term", "vote", "role", "leader", "commitIndex", "alive", "readyOutstanding"]:
            if prev[v][i] != s[v][i]:
                parts.append(f"{v}:{prev[v][i]}->{s[v][i]}")
        if prev["logs"][i] != s["logs"][i]:
            parts.append("log=" + str([e["term"] for e in s["logs"][i]]))
        if prev["durableLogs"][i] != s["durableLogs"][i] or prev["durableTerm"][i] != s["durableTerm"][i] or prev["durableCommit"][i] != s["durableCommit"][i]:
            parts.append(f"READY(dTerm={s['durableTerm'][i]},dLog={[e['term'] for e in s['durableLogs'][i]]},dCommit={s['durableCommit'][i]})")
        if prev["readQueue"][i] != s["readQueue"][i]:
            parts.append(f"queue={s['readQueue'][i]}")
        pr = s["pendingReads"][i]
        if prev["pendingReads"][i] != pr:
            parts.append("pending=" + str({c: (v["active"], v["index"], v["acks"], "floor", v["floor"], "fresh", v["fresh"]) for c, v in pr.items()}))
        if prev["producedReads"][i] != s["producedReads"][i]:
            parts.append("produced=" + str([(r["index"], r["acks"], r["fresh"], r["floor"]) for r in s["producedReads"][i]]))
        if parts:
            ch.append(f"{i}: " + "; ".join(parts))
    if prev["publishedReads"] != s["publishedReads"]:
        ch.append("PUBLISHED=" + str([(r["owner"], r["leader"], "idx", r["index"], "floor", r["floor"], "acks", r["acks"], "fresh", r["fresh"]) for r in s["publishedReads"]]))
    if prev["commitHistory"] != s["commitHistory"]:
        ch.append("commitHistory=" + str(sorted((c["index"], c["commitTerm"]) for c in s["commitHistory"])))
    fc = s.get("faultCounters")
    if fc and prev.get("faultCounters") != fc:
        ch.append("counters=" + str({a: b for a, b in fc.items() if b}))
    print(f"{k:2d} " + " | ".join(ch) + (f"  [-{gone}]" if gone else "") + (f"  [+{new}]" if new else ""))
    prev = s
