"""Generate mutated copies of fresh traces; each must be REJECTED by Trace.tla.
Usage: python3 -I mutate_traces.py <traces-dir> <out-dir>"""
import json, sys, os
src, out = sys.argv[1], sys.argv[2]
def load(n): return [json.loads(l) for l in open(os.path.join(src, n + ".ndjson"))]
def save(n, evs):
    with open(os.path.join(out, n + ".ndjson"), "w") as f:
        for e in evs: f.write(json.dumps(e) + "\n")
def walk(o, fn):
    if isinstance(o, dict):
        fn(o)
        for v in o.values(): walk(v, fn)
    elif isinstance(o, list):
        for v in o: walk(v, fn)
# M1: enable-from-zero with proposed u=2 rewritten to u=1 (= h) everywhere:
#     model's ValidateUpdateOK (row 6) must forbid the logged acceptance.
evs = load("apply_ve_enable_from_zero")
def m1(d):
    if d.get("veh") == 2: d["veh"] = 1
walk(evs, m1); save("neg_M1_enable_u_eq_h_logged_accepted", evs)
# M2: unchanged echo: rejection stage relabelled "update" -> "basic".
evs = load("apply_ve_unchanged_echo")
for e in evs:
    if e["event"]["name"] == "UpdateStateRejected": e["event"]["msg"]["stage"] = "basic"
save("neg_M2_echo_stage_basic", evs)
# M3: unchanged echo: rejected event relabelled as accepted with installed record.
evs = load("apply_ve_unchanged_echo")
last = evs[-1]["event"]; st = last["state"]
last["name"] = "UpdateStateAccepted"; st["phase"] = "updated"; st["validationOutcome"] = "accepted"
st["stateHeight"] = st["pendingBlockHeight"]; st["lastParamChange"] = st["pendingBlockHeight"] + 1
st["activeParam"] = {"body": st["pendingParam"]["body"], "veh": st["pendingParam"]["veh"]}
save("neg_M3_echo_logged_accepted", evs)
# M4: accepted VE enable: installed enable height altered (2 -> 3) after acceptance.
evs = load("apply_ve_enable_from_zero")
for e in evs:
    if e["event"]["name"] in ("UpdateStateAccepted", "CommitApp"): e["event"]["state"]["activeParam"]["veh"] = 3
save("neg_M4_installed_veh_altered", evs)
# M5: body validity flag flipped on a valid update (apply_valid).
evs = load("apply_valid")
for e in evs:
    if e["event"]["name"] == "FinalizeBlock": e["event"]["msg"]["proposedBodyValid"] = False
save("neg_M5_body_invalid_logged_accepted", evs)
# M6: mock-replay restart: saved response descriptor differs from replayed one.
evs = load("replay_mock_ve_enable_restart")
evs[0]["event"]["state"]["responseParam"]["veh"] = 3
save("neg_M6_saved_response_mismatch", evs)
print("mutants written to", out)
