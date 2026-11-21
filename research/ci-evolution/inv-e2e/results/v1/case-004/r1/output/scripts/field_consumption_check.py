#!/usr/bin/env python3
"""Negative control: for every captured post-state field and every update argument, mutate it in a
copy of a fresh trace and require TLC trace validation to FAIL. Proves Trace.tla consumes the field."""
import json, subprocess, sys, pathlib, copy
root = pathlib.Path(sys.argv[1]); out = root / "spec/output/field-consumption"; out.mkdir(parents=True, exist_ok=True)
def mutate_value(v):
    if isinstance(v, bool): return not v
    if isinstance(v, int): return v + 1
    if isinstance(v, str): return "Leader" if v != "Leader" else "Follower"
    if isinstance(v, list): return v[:-1] if v else [{"term": 9, "node": 9, "index": 9}]
    return v
cases = []
# post-state fields: mutate the last event's state (unit traces) / the step event (window)
base_traces = {
  "elect-learner-Elect": ("traces/elect-learner.ndjson", 1, "Trace.cfg"),
  "transfer-elect-window": (sorted((root/"traces/window/t14-transfer-to-voter").glob("*transfer-elect*"))[0].relative_to(root).as_posix(), 1, "Trace_window.cfg"),
  "follower-membership": ("traces/follower-membership.ndjson", 1, "Trace.cfg"),
  "partial-replication": ("traces/partial-replication.ndjson", 3, "Trace.cfg"),
}
fields = ["vote_term","vote_node","vote_committed","last_seen_term","last_seen_node","last_seen_committed","role",
          "logs","last_index","commit_index","effective_index","committed_membership_index","effective_configs",
          "learners","candidate","candidate_last_term","candidate_last_index","granters","leader","matches",
          "accepted_index","commands"]
def pick(field):
    if field in ("matches","commit_index"): return "partial-replication"
    if field in ("effective_index","committed_membership_index","effective_configs","learners","accepted_index"): return "follower-membership"
    if field in ("candidate_last_term","candidate_last_index","granters"): return "elect-learner-Elect"
    return "transfer-elect-window"
for f in fields:
    key = pick(f); path, ev, cfg = base_traces[key]
    cases.append((f"state-{f}", path, ev, cfg, ("state", f)))
# update arguments
cases.append(("arg-transfer-from_term", base_traces["transfer-elect-window"][0], 1, "Trace_window.cfg", ("args", "from_term")))
cases.append(("arg-transfer-to", base_traces["transfer-elect-window"][0], 1, "Trace_window.cfg", ("args", "to")))
cases.append(("arg-voterequest-last_term", "traces/vote-request-logid.ndjson", 1, "Trace.cfg", ("args", "last_term")))
cases.append(("arg-append-entries", "traces/follower-membership.ndjson", 1, "Trace.cfg", ("args", "entries")))
cases.append(("event-panic-as-normal", "traces/elect-learner.ndjson", 2, "Trace.cfg", ("name", None)))
rows = []
for name, path, ev, cfg, (kind, f) in cases:
    lines = [json.loads(l) for l in open(root/path)]
    m = copy.deepcopy(lines); e = m[ev]["event"]
    if kind == "name": e["name"] = "VoteResponse"
    elif kind == "args":
        e["args"][f] = mutate_value(e["args"][f]) if f != "entries" else [dict(x, configs=[[1,2]]) for x in e["args"][f]]
    else:
        if f == "candidate_last_term" and not e["state"]["candidate"]: pass
        e["state"][f] = mutate_value(e["state"][f])
    mp = out / f"{name}.ndjson"
    mp.write_text("".join(json.dumps(x) + "\n" for x in m))
    log = out / f"{name}.log"
    subprocess.run([str(root/"scripts/tlc.sh"), str(root/"spec"), "Trace.tla", cfg, str(log), "300", "-deadlock", "-workers", "1"],
                   env={"JSON": str(mp), "PATH": "/usr/bin:/bin"}, capture_output=True)
    t = log.read_text()
    passed = "No error has been found" in t and "Finished checking temporal properties" in t
    rows.append((name, path, ev, "REJECTED (field consumed)" if not passed else "ACCEPTED (field NOT consumed)"))
with open(out/"summary.tsv","w") as fh:
    for r in rows: fh.write("\t".join(map(str,r))+"\n")
for r in rows: print("\t".join(map(str,r)))
