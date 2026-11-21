#!/usr/bin/env python3
"""Summarize TLC campaign logs (spec/output/<label>.log) into a Markdown table."""
import re, sys, os
rows = [
 # label, cfg, module, purpose
 ("mc-standard-round3", "MC.cfg", "MC", "standard convergence round (final reference)"),
 ("mc-standard-sim", "MC.cfg", "MC", "standard model, simulation depth 100"),
 ("update-full-c1-final", "Update_full.cfg", "Update", "C1 full MCNext, all update properties"),
 ("update-full-c1-panic-final", "Update_full_NoCorePanic.cfg", "Update", "C1 oracle isolation U2"),
 ("update-full-c1-nonvoterleader-final", "Update_full_ElectedLeaderWasVoter.cfg", "Update", "C1 oracle isolation U5 (after R8)"),
 ("update-full-u7", "Update_full_LeaderVoteNotSuperseded.cfg", "Update", "C1 U7 with transfer inputs"),
 ("update-preexisting-u7", "Update_preexisting_LeaderVoteNotSuperseded.cfg", "Update", "U7, transfers disabled (pre-existing path)"),
 ("update-full-residual-c1b", "Update_full_residual.cfg", "Update", "C1b full MCNext, remaining properties"),
 ("update-full-residual-sim", "Update_full_residual.cfg", "Update", "C1b simulation depth 100"),
 ("update-focused-c2-allprops", "Update_focused.cfg", "Update", "C2 concrete focused, all update properties"),
 ("update-focused-residual-c2", "Update_focused_residual.cfg", "Update", "C2 concrete focused, remaining properties"),
 ("update-open-c3-allprops", "Update_open.cfg", "Update", "C3a open focused (EnvUpdate), all update properties"),
 ("update-open-residual-c3a", "Update_open_residual.cfg", "Update", "C3a open focused, remaining properties"),
 ("update-discharge-c3b", "Update_discharge.cfg", "Update", "C3b discharge of EnvUpdate"),
 ("hunt-transfer-learner-bfs", "MC_hunt_transfer_learner.cfg", "Update", "hunt U-S1 learner target"),
 ("hunt-transfer-voter-bfs", "MC_hunt_transfer_voter.cfg", "Update", "hunt U-S3 voter targets, BFS"),
 ("hunt-transfer-voter-sim", "MC_hunt_transfer_voter.cfg", "Update", "hunt U-S3 voter targets, simulation"),
 ("hunt-transfer-membership-bfs", "MC_hunt_transfer_membership.cfg", "Update", "hunt U-S4 membership, BFS"),
 ("hunt-transfer-membership-sim", "MC_hunt_transfer_membership.cfg", "Update", "hunt U-S4 membership, simulation"),
]
canaries = sorted(f[len("canary-"):-4] for f in os.listdir("output") if f.startswith("canary-") and f.endswith(".log"))
for c in canaries:
    rows.append(("canary-" + c, "Update_canary_%s.cfg" % c.replace("-witness", "_witness"), "Update", "reachability canary (violation expected)"))

def summarize(label):
    p = os.path.join("output", label + ".log")
    if not os.path.exists(p):
        return "not run", "", ""
    s = open(p).read()
    viol = re.findall(r"Error: (?:Invariant|Action property|Temporal property) (\w+) is violated", s)
    rc = re.search(r"EXIT rc=(\d+) elapsed=(\d+)s", s)
    rcv, el = (rc.group(1), rc.group(2)) if rc else ("?", "?")
    fin = re.search(r"([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue", s)
    prog = re.findall(r"Progress\((\d+)\) at [^:]+:\d\d:\d\d: ([\d,]+) states generated.*?, ([\d,]+) distinct states found.*?, ([\d,]+) states left on queue", s)
    sim = re.findall(r"Progress: (\d+) states checked, (\d+) traces generated \(trace length: mean=(\d+)", s)
    depth = re.search(r"The depth of the complete state graph search is (\d+)", s)
    if viol:
        cov = "%s gen / %s distinct, depth %s" % (fin.group(1), fin.group(2), depth.group(1) if depth else "?") if fin else ""
        return "VIOLATION: " + ", ".join(sorted(set(viol))), cov, "%ss" % el
    if "Model checking completed. No error has been found" in s:
        return "no violation, state space exhausted", (fin.group(2) + " distinct") if fin else "", "%ss" % el
    if sim:
        st, tr, mean = sim[-1]
        return "no violation; budget-limited simulation", "%s states / %s traces, mean length %s" % (st, tr, mean), "%ss" % el
    if prog:
        d, g, ds, q = prog[-1]
        return "no violation; budget-limited BFS", "%s gen / %s distinct, depth %s, queue %s" % (g, ds, d, q), "%ss" % el
    return "rc=%s (see log)" % rcv, "", "%ss" % el

out = ["| Run (log `spec/output/<run>.log`) | cfg | Purpose | Outcome | Coverage | Time |", "|---|---|---|---|---|---|"]
for label, cfg, mod, purpose in rows:
    o, cov, t = summarize(label)
    out.append("| `%s` | `%s` | %s | %s | %s | %s |" % (label, cfg, purpose, o, cov, t))
print("\n".join(out))
