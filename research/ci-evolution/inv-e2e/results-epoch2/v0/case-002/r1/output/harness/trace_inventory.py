"""Event inventory + update-window coverage for fresh traces (stdlib only)."""
import json, sys, collections, hashlib, glob, os
root = sys.argv[1]
rows = {}
for path in sorted(glob.glob(os.path.join(root, "traces", "*.ndjson"))):
    recs = [json.loads(x) for x in open(path)]
    c = collections.Counter(r["event"]["name"] for r in recs)
    # update-window facts
    skipped_initial = sum(1 for r in recs if r["event"]["name"] == "ZkShutdownSkipped" and r["event"]["aux"]["zkState"] == "INITIAL")
    nl_logged = 0
    step = {}
    for r in recs:
        e = r["event"]; n = e["node"]
        if e["name"] == "ZkServerState" and e["aux"]["zkState"] == "INITIAL":
            step[n] = "started"
        elif e["name"] == "ProposalQueued" and step.get(n) == "started":
            nl_logged += 1
        elif e["name"] == "NewLeaderAckSent":
            step[n] = "acked"
    rows[os.path.basename(path)] = {
        "records": len(recs),
        "sha256": hashlib.sha256(open(path, "rb").read()).hexdigest(),
        "events": dict(sorted(c.items())),
        "proposals_logged_between_startup_and_newleader_ack": nl_logged,
        "shutdown_skipped_in_INITIAL": skipped_initial,
    }
print(json.dumps(rows, indent=1))
