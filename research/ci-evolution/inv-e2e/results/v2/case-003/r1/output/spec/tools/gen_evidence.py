#!/usr/bin/env python3
"""Generate divergence-evidence TLC evaluation modules (spec/evidence/<id>/).
Each module fixes one state, instantiates the updated reference (base + UpdateProps)
and, where an old counterpart exists, the V0 reference (OldBase), and prints both
truth values via ASSUME PrintT.  Static one-state evaluation; no exploration."""
import json, os
SPEC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
TR = os.path.join(SPEC, "..", "traces")

def tla(v):
    if isinstance(v, bool): return "TRUE" if v else "FALSE"
    if isinstance(v, int): return str(v)
    if isinstance(v, str): return '"' + v + '"'
    if isinstance(v, list): return "<<" + ", ".join(tla(x) for x in v) + ">>"
    if isinstance(v, set): return "{" + ", ".join(sorted(tla(x) for x in v)) + "}"
    if isinstance(v, dict): return "[" + ", ".join(f"{k} |-> {tla(x)}" for k, x in v.items()) + "]"
    raise TypeError(v)

NOUPD = {"present": False, "rest": "none", "abciPresent": False, "abci": 0}
def event(trace, name, nth=0):
    evs = [json.loads(l) for l in open(os.path.join(TR, trace + ".ndjson"))]
    k = [i for i, e in enumerate(evs) if e["event"]["name"] == name][nth]
    return k + 1, evs[k]["event"]["state"]

def new_state(s):
    st = {k: s[k] for k in ["blockStoreHeight", "appHeight", "stateStoreHeight", "stateHeight",
          "activeParam", "persistedParam", "lastParamChange", "persistedLastParamChange",
          "responseHeight", "responseParam", "phase", "replayMutatesState", "pendingBlockHeight",
          "pendingParam"]}
    st["updatePresent"] = s["pendingParam"]["present"]
    st["validationOutcome"] = s["validationOutcome"]; st["rejectRule"] = s["rejectRule"]
    st["veHist"] = s["veHist"]; st["coverage"] = set()
    return st

def pstr(p): return f"P_{p['rest'][:8]}_ve{p['ve']}"
def apply_upd(p, u):
    if not u["present"]: return p
    return {"rest": u["rest"], "ve": u["abci"] if u["abciPresent"] else p["ve"]}
def old_state(st):
    """Map an updated-representation state onto V0's symbolic identities."""
    pre = st["persistedParam"]
    o = {k: st[k] for k in ["blockStoreHeight", "appHeight", "stateStoreHeight", "stateHeight",
         "lastParamChange", "persistedLastParamChange", "responseHeight", "phase",
         "replayMutatesState", "pendingBlockHeight", "updatePresent", "validationOutcome", "coverage"]}
    o["activeParam"] = pstr(st["activeParam"]); o["persistedParam"] = pstr(pre)
    o["pendingParam"] = pstr(apply_upd(pre, st["pendingParam"])) if st["pendingParam"]["present"] else "NoParam"
    o["responseParam"] = pstr(apply_upd(pre, st["responseParam"])) if st["responseParam"]["present"] else "NoParam"
    return o

def params_of(st):
    ps = {st["activeParam"]["rest"], st["persistedParam"]["rest"]}
    for u in (st["pendingParam"], st["responseParam"]):
        if u["present"]: ps.add(u["rest"])
    return ps

NEWVARS = ["blockStoreHeight", "appHeight", "stateStoreHeight", "stateHeight", "activeParam",
           "persistedParam", "lastParamChange", "persistedLastParamChange", "responseHeight",
           "responseParam", "phase", "replayMutatesState", "pendingBlockHeight", "pendingParam",
           "updatePresent", "validationOutcome", "rejectRule", "veHist", "coverage"]
OLDVARS = [v for v in NEWVARS if v not in ("rejectRule", "veHist")]

def write(eid, prop, st, old_prop=None, old_valid=None, valid_rest=None, extra_new=()):
    d = os.path.join(SPEC, "evidence", eid); os.makedirs(d, exist_ok=True)
    rest = params_of(st) | {"rBad"}
    valid_rest = valid_rest if valid_rest is not None else params_of(st)
    ves = {-1, 0} | {st["activeParam"]["ve"], st["persistedParam"]["ve"]} | set(st["veHist"]) \
          | {u["abci"] for u in (st["pendingParam"], st["responseParam"])}
    lines = [f"---- MODULE E{eid} ----", "EXTENDS TLC, Integers, Sequences, FiniteSets",
             f"S == {tla(st)}"]
    sub = ", ".join(f"{v} <- S.{v}" for v in NEWVARS)
    lines.append(f"New == INSTANCE UpdateProps WITH MaxHeight <- 100, Rest <- {tla(rest)}, "
                 f"ValidRest <- {tla(valid_rest)}, VEValues <- {tla(ves)}, "
                 f"InitialParams <- {{S.persistedParam}}, NoRest <- \"none\", {sub}")
    out = [f'"{eid}"', f'"New!{prop}"', f"New!{prop}"] + [x for e in extra_new for x in (f'"New!{e}"', f"New!{e}")]
    if old_prop:
        o = old_state(st)
        params = {o["activeParam"], o["persistedParam"]} | ({o["pendingParam"]} - {"NoParam"}) | ({o["responseParam"]} - {"NoParam"})
        lines.append(f"O == {tla(o)}")
        osub = ", ".join(f"{v} <- O.{v}" for v in OLDVARS)
        lines.append(f"Old == INSTANCE OldBase WITH MaxHeight <- 100, Params <- {tla(params)}, "
                     f"ValidParams <- {tla(old_valid(o, params))}, InitialParam <- O.persistedParam, "
                     f"NoParam <- \"NoParam\", {osub}")
        out += [f'"Old!{old_prop}"', f"Old!{old_prop}"]
    lines.append(f"ASSUME PrintT(<<{', '.join(out)}>>)")
    lines += ["VARIABLE dummy", "Init == dummy = 0", "Next == UNCHANGED dummy", "===="]
    open(os.path.join(d, f"E{eid}.tla"), "w").write("\n".join(lines) + "\n")
    open(os.path.join(d, f"E{eid}.cfg"), "w").write("INIT Init\nNEXT Next\n")

# --- states -----------------------------------------------------------------
L = {}
def T(eid, trace, ev, nth=0):
    k, s = event(trace, ev, nth); L[eid] = f"trace:{trace}.ndjson event {k} ({ev})"; return new_state(s)

all_but_pending = lambda o, P: P - ({o["pendingParam"]} if o["pendingParam"] != o["persistedParam"] else set())
all_params = lambda o, P: P

# E1: ParameterUpdateReflected weakening -- accepted 0 -> 2 at h=1 (old tree rejects: observe-old O1).
s = T("E1", "ve_enable_future", "UpdateStateAccepted")
write("E1", "ParameterUpdateReflected", s, "ParameterUpdateReflected", all_but_pending)
# E1c: control -- same state with the update not installed (active ve stays 0).
c = json.loads(json.dumps(s, default=list)); c["coverage"] = set(); c["activeParam"] = dict(s["activeParam"], ve=0)
write("E1c", "ParameterUpdateReflected", c); L["E1c"] = "constructed: E1 with activeParam.ve 2 -> 0"
# E2: ParameterUpdateReflected strengthening moved to AcceptedVEUpdateRespectsRules -- accepted disable after enable.
k, s0 = event("ve_disable_after_enable", "UpdateStateRejected"); d = new_state(s0)
d.update(phase="updated", stateHeight=1, activeParam=dict(d["activeParam"], ve=0), lastParamChange=2,
         validationOutcome="accepted", rejectRule="none")
write("E2", "AcceptedVEUpdateRespectsRules", d, "ParameterUpdateReflected", all_but_pending,
      extra_new=("ParameterUpdateReflected",))
L["E2"] = f"constructed from trace:ve_disable_after_enable.ndjson event {k}: the rejected 1 -> 0 at h=1 shown as accepted"
# E2c: control -- accepted cancel of a not-yet-reached height (trace).
s = T("E2c", "ve_cancel_scheduled", "UpdateStateAccepted"); write("E2c", "AcceptedVEUpdateRespectsRules", s)
# E3: keep RejectedUpdateDoesNotInstall on the changed rejection (trace).
s = T("E3", "ve_unchanged_after_enable", "UpdateStateRejected")
write("E3", "RejectedUpdateDoesNotInstall", s, "RejectedUpdateDoesNotInstall", all_but_pending,
      extra_new=("UnchangedVEUpdateNotRejected", "PermittedVEUpdateNotRejected"))
# E4: keep SuccessfulApplyAdvancesExactlyOne on the changed acceptance (trace).
s = T("E4", "ve_enable_future", "UpdateStateAccepted")
write("E4", "SuccessfulApplyAdvancesExactlyOne", s, "SuccessfulApplyAdvancesExactlyOne", all_params)
# E5: keep NormalPhaseIsSynchronized after mock replay re-validated an enable-height update (trace).
s = T("E5", "replay_mock_ve_update", "HandshakeComplete")
write("E5", "NormalPhaseIsSynchronized", s, "NormalPhaseIsSynchronized", all_params,
      extra_new=("VEHistoryStable", "RecoveryNormalOnlySupported"))
# E6: TypeOK representation change (trace state, both representations).
s = T("E6", "replay_real_ve_update", "UpdateStateAccepted")
write("E6", "TypeOK", s, "TypeOK", all_params)
# E7: VEHistoryStable add -- block 1 stored with enable height 0, current params say height 1 is enabled.
s = T("E7c", "ve_enable_future", "SaveState", 2); write("E7c", "VEHistoryStable", s,
      extra_new=("VEEnableMonotone", "StartupLastCommitConsistent"))
b = T("E7", "ve_enable_future", "SaveState", 0)
b.update(activeParam=dict(b["activeParam"], ve=1), persistedParam=dict(b["persistedParam"], ve=1))
L["E7"] += " with activeParam.ve/persistedParam.ve 2 -> 1 (a retroactive enable at the stored height)"
write("E7", "VEHistoryStable", b, extra_new=("StartupLastCommitConsistent",))
# E8: VEEnableMonotone add -- stored height 1 enabled, height 2 not.
m = T("E8", "ve_enable_future", "SaveState", 1); m["veHist"] = [1, 0]
L["E8"] += " with veHist <<0,2>> -> <<1,0>>"
write("E8", "VEEnableMonotone", m)
# E9: PermittedVEUpdateNotRejected add -- the V0 behavior: 0 -> 2 at h=1 rejected (observe-old O1).
r = T("E9", "ve_enable_future", "SaveFinalizeBlockResponse")
r.update(phase="rejected", validationOutcome="rejected", rejectRule="r8")
L["E9"] += " turned into a rejection (V0 behavior; spec/output/observe-old.log O1)"
write("E9", "PermittedVEUpdateNotRejected", r, extra_new=("UnchangedVEUpdateNotRejected",))
# E9c: control -- rejection of a forbidden disable after enable (trace).
s = T("E9c", "ve_disable_after_enable", "UpdateStateRejected")
write("E9c", "PermittedVEUpdateNotRejected", s, extra_new=("UnchangedVEUpdateNotRejected",))
# E10: UnchangedVEUpdateNotRejected add -- trace of the updated implementation rejecting an unchanged height.
s = T("E10", "replay_real_ve_unchanged_rejected", "UpdateStateRejected")
write("E10", "UnchangedVEUpdateNotRejected", s, extra_new=("PermittedVEUpdateNotRejected", "RejectedUpdateDoesNotInstall"))
# E10c: control -- unchanged height re-sent before it is reached is accepted (trace ve_cancel? use row-9 identity-free): rejected modify after enable
s = T("E10c", "ve_modify_after_enable", "UpdateStateRejected")
write("E10c", "UnchangedVEUpdateNotRejected", s)
json.dump(L, open(os.path.join(SPEC, "evidence", "state-sources.json"), "w"), indent=1)
print("generated", len(L))
