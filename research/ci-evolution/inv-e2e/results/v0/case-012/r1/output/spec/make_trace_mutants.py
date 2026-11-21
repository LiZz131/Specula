#!/usr/bin/env python3
"""Create single-field mutants of fresh traces to show Trace.tla consumes the
fields (each mutant must be REJECTED by TLC). Writes to spec/output/mutants/."""
import json, pathlib, copy
T = pathlib.Path(__file__).resolve().parent.parent / "traces"
O = pathlib.Path(__file__).resolve().parent / "output" / "mutants"
O.mkdir(parents=True, exist_ok=True)
def load(n): return [json.loads(l) for l in (T / f"{n}.ndjson").read_text().splitlines()]
def save(name, evs):
    (O / f"{name}.ndjson").write_text("".join(json.dumps(e, separators=(",", ":")) + "\n" for e in evs))
muts = {}
e = load("membership_change_then_acks")
m = copy.deepcopy(e); m[-1]["event"]["post"]["committed"] = 1; muts["m1_engine_committed"] = m
m = copy.deepcopy(e); v = m[-1]["event"]["post"]["progress"]["vector"]; v[0], v[1] = v[1], v[0]; muts["m2_vector_order"] = m
m = copy.deepcopy(e); m[-1]["event"]["post"]["progress"]["committed"] = {"kind": "log", "t": 1, "n": "2", "i": 1}; muts["m3_progress_committed"] = m
m = copy.deepcopy(e); m[2]["event"]["post"]["progress"]["qs"] = [["1", "2", "3"]]; muts["m4_progress_qs"] = m
m = copy.deepcopy(e); m[-1]["event"]["args"]["value"]["n"] = "3"; muts["m5_logid_node"] = m
m = copy.deepcopy(e); m[2]["event"]["post"]["committed_mem_index"] = 2; muts["m6_committed_membership"] = m
p = load("progress")
m = copy.deepcopy(p); v = m[4]["event"]["post"]["vector"]; v[0], v[1] = v[1], v[0]; muts["m7_unit_vector_order"] = m
m = copy.deepcopy(p); m[4]["event"]["post"]["committed"]["raw"] += 1; muts["m8_unit_committed"] = m
el = load("elect_multi-seg2")
m = copy.deepcopy(el); m[0]["event"]["post"]["vote_granted"] = []; muts["m9_vote_granted"] = m
m = copy.deepcopy(el); m[0]["event"]["post"]["leader_some"] = False; muts["m10_leader_some"] = m
fc = load("follower_commit_no_update")
m = copy.deepcopy(fc); m[0]["event"]["post"]["committed_mem_index"] = m[0]["event"]["post"]["effective_mem_index"]; m[0]["event"]["post"]["committed_configs"] = m[0]["event"]["post"]["effective_configs"]; muts["m11_follower_promotion"] = m
lf = load("leader_fast_commit")
m = copy.deepcopy(lf); m[0]["event"]["post"]["committed"] = m[0]["event"]["pre"]["committed"]; muts["m12_fast_commit"] = m
up = load("progress_upgrade")
idx = next(k for k, x in enumerate(up) if x["event"]["name"] == "ProgressUpgrade")
m = copy.deepcopy(up); m[idx]["event"]["post"]["committed"]["raw"] = 5 if m[idx]["event"]["post"]["committed"]["raw"] != 5 else 6; muts["m13_upgrade_committed"] = m
for k, v in muts.items(): save(k, v)
print(len(muts), "mutants")
