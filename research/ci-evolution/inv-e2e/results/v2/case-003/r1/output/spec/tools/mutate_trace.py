#!/usr/bin/env python3
"""Create single-field mutations of fresh traces (negative controls showing that
Trace.tla consumes the field). usage: mutate_trace.py <outdir>"""
import json, sys, os, copy
out = sys.argv[1]
T = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "traces")
def load(n): return [json.loads(l) for l in open(os.path.join(T, n + ".ndjson"))]
def save(name, evs, desc):
    with open(os.path.join(out, name + ".ndjson"), "w") as f:
        for e in evs: f.write(json.dumps(e) + "\n")
    with open(os.path.join(out, name + ".txt"), "w") as f: f.write(desc + "\n")
def idx(evs, name, nth=0):
    return [i for i, e in enumerate(evs) if e["event"]["name"] == name][nth]
m = []
evs = load("ve_unchanged_after_enable"); i = idx(evs, "UpdateStateRejected")
e = copy.deepcopy(evs); e[i]["event"]["state"]["rejectRule"] = "r8"
save("M1_rejectRule", e, "ve_unchanged_after_enable: UpdateStateRejected.state.rejectRule r6 -> r8")
e = copy.deepcopy(evs); e[i]["event"]["state"]["veHist"] = [1, 0]
save("M2_veHist", e, "ve_unchanged_after_enable: UpdateStateRejected.state.veHist [1,1] -> [1,0]")
j = idx(evs, "FinalizeBlock", 1)
e = copy.deepcopy(evs); e[j]["event"]["msg"]["proposedParam"]["abci"] = 2
save("M3_proposedAbci", e, "ve_unchanged_after_enable: 2nd FinalizeBlock.msg.proposedParam.abci 1 -> 2")
e = copy.deepcopy(evs); e[i]["event"]["state"]["activeParam"]["ve"] = 0
save("M4_activeVE", e, "ve_unchanged_after_enable: UpdateStateRejected.state.activeParam.ve 1 -> 0")
evs = load("ve_enable_future"); i = idx(evs, "UpdateStateAccepted")
e = copy.deepcopy(evs)[:i + 1]; s = e[i]["event"]
s["name"] = "UpdateStateRejected"; st = e[i - 1]["event"]["state"]
s["state"] = dict(st, phase="rejected", validationOutcome="rejected", rejectRule="r8")
save("M5_enableRejected", e, "ve_enable_future: first UpdateStateAccepted (0 -> 2 at h=1) replaced by an UpdateStateRejected (the V0 behavior); trace truncated there")
e = copy.deepcopy(evs); e[i]["event"]["state"]["lastParamChange"] = 1
save("M6_lastParamChange", e, "ve_enable_future: first UpdateStateAccepted.state.lastParamChange 2 -> 1")
evs = load("replay_mock_ve_update")
e = copy.deepcopy(evs); e[0]["event"]["state"]["responseParam"]["abci"] = 4
save("M7_responseParam", e, "replay_mock_ve_update: HandshakeStart.state.responseParam.abci 3 -> 4")
evs = load("ve_cancel_scheduled"); i = idx(evs, "UpdateStateAccepted")
e = copy.deepcopy(evs); e[i]["event"]["state"]["activeParam"]["ve"] = 5
save("M8_cancelIgnored", e, "ve_cancel_scheduled: first UpdateStateAccepted.state.activeParam.ve 0 -> 5 (cancel not installed)")
print("ok")
