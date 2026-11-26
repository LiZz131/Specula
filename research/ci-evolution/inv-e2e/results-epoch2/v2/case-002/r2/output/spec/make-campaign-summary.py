#!/usr/bin/env python3
"""Write spec/output/mc/campaign-summary.md from campaigns.ndjson (latest run per label)."""
import json, re, os
os.chdir('/work/current/.specular-output/spec')
rows = {}
for l in open('output/mc/campaigns.ndjson'):
    d = json.loads(l); rows[d['label']] = d
model = {
 "mc-small-r1": "pre-FIFO", "base-standard-r1": "pre-FIFO", "mc-standard-r1": "pre-FIFO",
 "update-hunt-durable-bfs": "pre-FIFO", "update-hunt-loss-sim": "pre-FIFO",
 "mc-small-r2": "FIFO", "mc-standard-final": "FIFO", "base-standard-final": "FIFO",
 "update-full-bfs": "FIFO", "update-focused-bfs": "FIFO", "update-open-bfs": "FIFO",
 "update-discharge-bfs": "FIFO", "update-hunt-loss-sim-r2": "FIFO", "update-hunt-durable-final": "FIFO",
}
for k in list(rows):
    if k.startswith('canary-') and not k.startswith('canary-final-'):
        model[k] = "pre-FIFO"
model["update-hunt-durable-2s-final"] = "FIFO (log moved to output/mc/superseded-r2/)"
model["update-hunt-loss-witness-bfs"] = "FIFO (log moved to output/mc/superseded-r2/)"
model["canary-MC-hunt-newleader"] = "pre-FIFO (MaxEpoch 1: target unreachable, cfg fixed)"
def classify(d):
    st = d['last_stats']; v = d['violation']
    q = re.search(r"(\d+) states left on queue", st)
    if v:
        return ("expected canary violation (reachability witness): " if d['label'].startswith('canary') else "VIOLATION: ") + v
    if d['mode'] == 'sim':
        return "no violation; simulation budget-terminated (LIMITED_COVERAGE)"
    if q and int(q.group(1)) == 0:
        return "no violation; state space exhausted" + (" within CanonicalDepthBound (level <= 23)" if d['cfg'] in ('MC.cfg', 'base.cfg') else "")
    return "no violation; BFS budget-terminated with %s states queued (LIMITED_COVERAGE)" % (q.group(1) if q else "?")
out = ["# Model-checking campaign summary", "",
       "Model column: `pre-FIFO` = before the ReceiveProposal FIFO / SelectSync repairs; `FIFO` = after them but before the FollowLeader-from-LOOKING / volatile-votes restriction (a superset of the final transition relation, so a no-violation result within the same bounds carries over); `final` = final artifacts.", "",
       "| label | cfg | mode | model | outcome | statistics | depth |", "|---|---|---|---|---|---|---|"]
for k, d in rows.items():
    out.append("| %s | `%s` | %s | %s | %s | %s | %s |" % (k, d['cfg'], d['mode'], model.get(k, "final"), classify(d), d['last_stats'], d['depth'].replace('depth of the complete state graph search is ', '')))
out += ["", "Reachability canaries (`canary-*`, `Not*Reached`) are expected violations; they are witnesses, not findings.",
        "Logs: `spec/output/mc/<label>.log`; decoded counterexamples: `<label>.decoded.txt`; exact commands: `campaigns.ndjson`."]
open('output/mc/campaign-summary.md', 'w').write("\n".join(out) + "\n")
print("\n".join(out))
