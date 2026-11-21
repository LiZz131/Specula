#!/usr/bin/env python3
"""Generate and run one-state (or two-state) TLC evaluations for spec/invariant-evidence.json.

Each evidence id gets spec/evidence/<id>/<id>.tla, <id>.cfg and tlc.log. The
modules EXTEND the actual V1 modules (base or Update) and instantiate the V0
definitions as `Old == INSTANCE OldBase` (OldBase.tla = previous suite's
base.tla with only the MODULE line renamed). Truth values are printed by TLC
(PrintT) or come from TLC's own invariant/property verdict.
"""
import json
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
TRACES = HERE.parent.parent / "traces"
CP = "/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"

BASE_VARS = ["currentTerm", "voteFor", "voteCommitted", "role", "voteGranted", "lastLog", "logTerm",
             "committed", "matchedIndex", "matchedTerm", "committedConfig", "effectiveConfig",
             "committedMembershipIndex", "committedMembershipTerm", "effectiveMembershipIndex",
             "effectiveMembershipTerm", "messages", "crashed", "witnessIndex", "witnessNodes",
             "witnessConfig", "witnessTerm", "leaderState", "progressConfig", "logConfig"]
MC_COUNTERS = ["electionActions", "clientAppends", "membershipChanges", "crashes", "losses"]


def tset(xs):
    return "{" + ", ".join(xs) + "}"


def tfun(servers, f):
    return "(" + " @@ ".join(f"{s} :> {f(s)}" for s in servers) + ")"


def cfg_lit(groups, idmap):
    return tset([tset([idmap[x] for x in g]) for g in groups])


def default_state(servers, max_index):
    init_cfg = "{" + tset(servers) + "}"
    return {
        "currentTerm": {s: "0" for s in servers},
        "voteFor": {s: s for s in servers},
        "voteCommitted": {s: "FALSE" for s in servers},
        "role": {s: '"follower"' for s in servers},
        "voteGranted": {s: "{}" for s in servers},
        "lastLog": {s: "-1" for s in servers},
        "logTerm": {s: ["0"] * (max_index + 1) for s in servers},
        "committed": {s: "-1" for s in servers},
        "matchedIndex": {s: {t: "-1" for t in servers} for s in servers},
        "matchedTerm": {s: {t: "0" for t in servers} for s in servers},
        "committedConfig": {s: init_cfg for s in servers},
        "effectiveConfig": {s: init_cfg for s in servers},
        "committedMembershipIndex": {s: "-1" for s in servers},
        "committedMembershipTerm": {s: "0" for s in servers},
        "effectiveMembershipIndex": {s: "-1" for s in servers},
        "effectiveMembershipTerm": {s: "0" for s in servers},
        "messages": "{}",
        "crashed": "{}",
        "witnessIndex": {s: "-1" for s in servers},
        "witnessNodes": {s: "{}" for s in servers},
        "witnessConfig": {s: init_cfg for s in servers},
        "witnessTerm": {s: "0" for s in servers},
        "leaderState": {s: "FALSE" for s in servers},
        "progressConfig": {s: init_cfg for s in servers},
        "logConfig": {s: ["{}"] * (max_index + 1) for s in servers},
    }


def render_var(name, val, servers):
    if not isinstance(val, dict):
        return val
    if name in ("logTerm", "logConfig"):
        return tfun(servers, lambda s: "<<" + ", ".join(val[s]) + ">>" if False else
                    "[k \\in 0..MaxIndex |-> " + "CASE " + " [] ".join(
                        f"k = {k} -> {v}" for k, v in enumerate(val[s])) + "]")
    if name in ("matchedIndex", "matchedTerm"):
        return tfun(servers, lambda s: tfun(servers, lambda t: val[s][t]))
    return tfun(servers, lambda s: val[s])


def from_snapshot(snap, nid, servers, idmap, max_index):
    st = default_state(servers, max_index)
    n = idmap[nid]
    init_cfg = "{" + tset(servers) + "}"
    st["currentTerm"][n] = str(snap["term"])
    st["voteFor"][n] = idmap[snap["vote_node"]]
    st["voteCommitted"][n] = "TRUE" if snap["vote_committed"] else "FALSE"
    st["role"][n] = '"%s"' % snap["role"]
    st["voteGranted"][n] = tset([idmap[x] for x in snap.get("vote_granted", [])])
    st["lastLog"][n] = str(snap["last_log"])
    logs = ["0"] * (max_index + 1)
    for k, t in enumerate(snap["logs"]):
        logs[k] = str(t)
    st["logTerm"][n] = logs
    st["committed"][n] = str(snap["committed"])
    for p in snap.get("progress", []):
        st["matchedIndex"][n][idmap[p["id"]]] = str(p["index"])
        st["matchedTerm"][n][idmap[p["id"]]] = str(p["term"])
    st["committedConfig"][n] = cfg_lit(snap["committed_configs"], idmap) if snap["committed_configs"] else init_cfg
    st["effectiveConfig"][n] = cfg_lit(snap["effective_configs"], idmap) if snap["effective_configs"] else init_cfg
    st["committedMembershipIndex"][n] = str(snap["committed_mem_index"])
    st["committedMembershipTerm"][n] = str(snap["committed_mem_term"])
    st["effectiveMembershipIndex"][n] = str(snap["effective_mem_index"])
    st["effectiveMembershipTerm"][n] = str(snap["effective_mem_term"])
    st["leaderState"][n] = "TRUE" if snap.get("has_leader") else "FALSE"
    # same placement rule as Trace.tla InitFromEngineSnapshot
    lc = ["{}"] * (max_index + 1)
    if 0 <= snap["committed_mem_index"] <= max_index:
        lc[snap["committed_mem_index"]] = st["committedConfig"][n]
    if 0 <= snap["effective_mem_index"] <= max_index:
        lc[snap["effective_mem_index"]] = st["effectiveConfig"][n]
    st["logConfig"][n] = lc
    if snap.get("has_leader"):
        st["progressConfig"][n] = cfg_lit(snap["progress_configs"], idmap)
    return st


def assign(st, servers, primed=False):
    p = "'" if primed else ""
    return "\n".join(f"    /\\ {v}{p} = {render_var(v, st[v], servers)}" for v in BASE_VARS)


def write_and_run(eid, template, servers, st, report_exprs, consts, extra_cfg="", st2=None, prop=None):
    d = HERE / eid
    d.mkdir(exist_ok=True)
    ext = "Update" if template == "update" else "base"
    counters = ""
    if template == "update":
        counters = "\n".join(f"    /\\ {c} = 0" for c in MC_COUNTERS)
        frame = "mcVars"
    else:
        frame = "vars"
    if st2 is None:
        nxt = f"SNext == UNCHANGED {frame}"
    else:
        nxt = "SNext ==\n" + assign(st2, servers, primed=True) + (
            "\n" + "\n".join(f"    /\\ {c}' = 0" for c in MC_COUNTERS) if template == "update" else "")
    # one short PrintT per label so that TLC prints each tuple on one line
    groups, cur = [], []
    for e in report_exprs:
        if e.startswith('"') and cur:
            groups.append(cur); cur = []
        cur.append(e)
    if cur:
        groups.append(cur)
    rep = " /\\ ".join(f'PrintT(<<"{eid}", ' + ", ".join(g) + ">>)" for g in groups)
    mod = f"""---- MODULE {eid} ----
\\* Evidence state for spec/invariant-evidence.json (generated by evidence/gen.py).
EXTENDS {ext}
Old == INSTANCE OldBase
SInit ==
{assign(st, servers)}
{counters}
{nxt}
Report == {rep}
====
"""
    (d / f"{eid}.tla").write_text(mod)
    cfg = "INIT SInit\nNEXT SNext\nCHECK_DEADLOCK FALSE\nCONSTANTS\n" + "\n".join(f"    {k} {v}" for k, v in consts) + "\n"
    cfg += "INVARIANT Report\n" + extra_cfg
    if prop:
        cfg += f"PROPERTY {prop}\n"
    (d / f"{eid}.cfg").write_text(cfg)
    for f in ["OldBase.tla"]:
        pass
    env = dict(os.environ)
    meta = f"/dev/shm/specula-e2e-case-012/evidence-{eid}"
    cmd = ["java", "-Xmx2g", "-cp", CP, "tlc2.TLC", "-config", f"{eid}.cfg", "-workers", "1",
           "-metadir", meta, "-cleanup", "-noGenerateSpecTE", f"{eid}.tla"]
    # modules are resolved from the evidence dir: symlink the suite modules
    for m in ["base.tla", "MC.tla", "Update.tla"]:
        link = d / m
        if not link.exists():
            link.symlink_to(HERE.parent / m)
    old = d / "OldBase.tla"
    if not old.exists():
        old.symlink_to(HERE / "OldBase.tla")
    res = subprocess.run(cmd, cwd=d, capture_output=True, text=True, timeout=600)
    log = "# cmd: " + " ".join(cmd) + f" (cwd {d})\n" + res.stdout + res.stderr + f"\n# exit={res.returncode}\n"
    (d / "tlc.log").write_text(log)
    subprocess.run(["rm", "-rf", meta])
    printed = [l for l in res.stdout.splitlines() if l.startswith("<<\"" + eid)]
    printed = [" | ".join(printed)] if printed else []
    verdict = "violated" if ("is violated" in res.stdout or "was violated" in res.stdout) else (
        "ok" if "No error has been found" in res.stdout else "error")
    return printed[0] if printed else None, verdict, res.returncode


MC_CONSTS = [("n1", "= n1"), ("n2", "= n2"), ("n3", "= n3"), ("Server", "<- MCServer"),
             ("AllowedConfigs", "<- MCAllowedConfigs"), ("MaxElectionActions", "= 0"),
             ("MaxClientAppends", "= 0"), ("MaxMembershipChanges", "= 0"), ("MaxCrashes", "= 0"),
             ("MaxLosses", "= 0")]


def mc_consts(max_term, max_index):
    return MC_CONSTS + [("MaxTerm", f"= {max_term}"), ("MaxIndex", f"= {max_index}")]


def base_consts(server_lit, max_term, max_index):
    return [("Server", f"= {server_lit}"), ("MaxTerm", f"= {max_term}"), ("MaxIndex", f"= {max_index}"),
            ("AllowedConfigs", "<- BaseAllowedConfigs")]


def load_event(trace, k):
    lines = (TRACES / f"{trace}.ndjson").read_text().splitlines()
    return json.loads(lines[k])["event"]


KEEP_REPORT = ['"TypeOK"', "Old!TypeOK", "TypeOK",
               '"EffectiveIsLastLogMembership"', "EffectiveIsLastLogMembership",
               '"CommitWithinLocalLog"', "Old!CommitWithinLocalLog", "CommitWithinLocalLog",
               '"MembershipOrder"', "Old!MembershipOrder", "MembershipOrder",
               '"OneOutstandingMembership"', "Old!OneOutstandingMembership", "OneOutstandingMembership",
               '"ActiveLeaderHasCommittedVote"', "Old!ActiveLeaderHasCommittedVote", "ActiveLeaderHasCommittedVote",
               '"ElectionSafety"', "Old!ElectionSafety", "ElectionSafety",
               '"CommittedLogAgreement"', "Old!CommittedLogAgreement", "CommittedLogAgreement"]

UPD_REPORT = ['"CommitWitnessSound"', "Old!CommitWitnessSound", "CommitWitnessSound_new",
              '"LeaderProgressConfigCurrent"', "LeaderProgressConfigCurrent"]


def main():
    results = {}
    which = set(sys.argv[1:])

    def run(eid, *a, **kw):
        if which and eid not in which:
            return
        results[eid] = write_and_run(eid, *a, **kw)
        print(eid, results[eid])

    s3 = ["n1", "n2", "n3"]
    id3 = {"1": "n1", "2": "n2", "3": "n3"}

    # ---- keep evidence from fresh V1 traces (template base, string ids) ----
    lc_names = [json.loads(l)["event"]["name"] for l in (TRACES / "leader_lifecycle.ndjson").read_text().splitlines()]
    ids_lc = {"0": '"0"', "1": '"1"', "2": '"2"', "3": '"3"'}
    srv_lc = ['"0"', '"1"', '"2"', '"3"']
    # K1: lifecycle post-state after the UpdateProgress that commits the joint entry (index 4)
    k1 = [k for k, n in enumerate(lc_names) if n == "UpdateProgress"
          and load_event("leader_lifecycle", k)["post"]["committed"] == 4
          and load_event("leader_lifecycle", k)["pre"]["committed"] == 3][0]
    ev = load_event("leader_lifecycle", k1)
    run("K1", "base", srv_lc, from_snapshot(ev["post"], ev["nid"], srv_lc, ids_lc, 6), KEEP_REPORT,
        base_consts(tset(srv_lc), 4, 6))
    # K2: lifecycle post-state after the uniform LeaderAppend (effective 5 > committed 4)
    k2 = [k for k, n in enumerate(lc_names) if n == "LeaderAppend"
          and load_event("leader_lifecycle", k)["post"]["effective_mem_index"] == 5][0]
    ev = load_event("leader_lifecycle", k2)
    run("K2", "base", srv_lc, from_snapshot(ev["post"], ev["nid"], srv_lc, ids_lc, 6), KEEP_REPORT,
        base_consts(tset(srv_lc), 4, 6))
    # K3: fast_commit_upto_membership post-state (commit 4, committed mem 3, effective 5)
    ids5 = {str(i): f'"{i}"' for i in range(5)}
    srv5 = [f'"{i}"' for i in range(5)]
    ev = load_event("leader_fast_commit_upto_membership", 0)
    run("K3", "base", srv5, from_snapshot(ev["post"], ev["nid"], srv5, ids5, 7), KEEP_REPORT,
        base_consts(tset(srv5), 4, 7))
    # K4: follower_commit_no_advance post-state (effective 3 <= committed 3, committed mem 1)
    ev = load_event("follower_commit_no_advance", 0)
    run("K4", "base", srv5, from_snapshot(ev["post"], ev["nid"], srv5, ids5, 7), KEEP_REPORT,
        base_consts(tset(srv5), 4, 7))

    # ---- update-property evidence (template update, MC server ids) ----
    # E2c: lifecycle post-state after uniform LeaderAppend: progress quorum set upgraded == effective
    ev = load_event("leader_lifecycle", k2)
    st = from_snapshot(ev["post"], ev["nid"], s3, id3, 6)
    run("E2c", "update", s3, st, UPD_REPORT, mc_consts(4, 6))
    # E2: constructed separating state for LeaderProgressConfigCurrent: same, but the
    # effective membership changed to {n1,n2,n3} without upgrading leader progress
    st2 = json.loads(json.dumps(st))
    st2["effectiveConfig"]["n1"] = "{{n1, n2, n3}}"
    run("E2", "update", s3, st2, UPD_REPORT, mc_consts(4, 6))

    # E4: EffectiveIsLastLogMembership separating state: E2c (log holds membership entries
    # at 4 (joint) and 5 ({1,2})) but the effective membership points at the older entry 4.
    st4 = json.loads(json.dumps(st))
    st4["effectiveMembershipIndex"]["n1"] = st4["committedMembershipIndex"]["n1"]
    st4["effectiveConfig"]["n1"] = st4["committedConfig"]["n1"]
    run("E4", "update", s3, st4, ['"EffectiveIsLastLogMembership"', "EffectiveIsLastLogMembership"], mc_consts(4, 6))
    run("E4c", "update", s3, st, ['"EffectiveIsLastLogMembership"', "EffectiveIsLastLogMembership"], mc_consts(4, 6))

    # E1 (constructed first judgment; upgraded to mc in E1mc): n1 re-elected in term 2 with a
    # term-1 witness at index 0 supported by {n1,n2}; leader progress recreated (rows Nil).
    e1 = default_state(s3, 2)
    e1["currentTerm"] = {"n1": "2", "n2": "1", "n3": "1"}
    e1["voteFor"] = {"n1": "n1", "n2": "n1", "n3": "n1"}
    e1["voteCommitted"] = {"n1": "FALSE", "n2": "FALSE", "n3": "TRUE"}
    e1["role"] = {"n1": '"candidate"', "n2": '"follower"', "n3": '"follower"'}
    e1["voteGranted"]["n1"] = "{n1}"
    e1["lastLog"] = {"n1": "0", "n2": "0", "n3": "-1"}
    e1["logTerm"] = {"n1": ["1", "0", "0"], "n2": ["1", "0", "0"], "n3": ["0", "0", "0"]}
    e1["committed"] = {"n1": "0", "n2": "-1", "n3": "-1"}
    e1["witnessIndex"]["n1"] = "0"
    e1["witnessNodes"]["n1"] = "{n1, n2}"
    e1["witnessTerm"]["n1"] = "1"
    e1["leaderState"]["n1"] = "TRUE"
    run("E1", "update", s3, e1, UPD_REPORT, mc_consts(2, 2))
    # E1c: weakening control: same as E1 but supporter n2 lost the entry -> must be rejected
    e1c = json.loads(json.dumps(e1))
    e1c["lastLog"]["n2"] = "-1"
    e1c["logTerm"]["n2"] = ["0", "0", "0"]
    run("E1c", "update", s3, e1c, UPD_REPORT, mc_consts(2, 2))
    # E1s: strengthening separating state: same leadership (term 1 leader, live matched rows
    # reach the witness, so the V0 property accepts) but supporter n2's log lacks the entry.
    e1s = default_state(s3, 2)
    e1s["currentTerm"] = {"n1": "1", "n2": "1", "n3": "0"}
    e1s["voteFor"] = {"n1": "n1", "n2": "n1", "n3": "n3"}
    e1s["voteCommitted"] = {"n1": "TRUE", "n2": "TRUE", "n3": "FALSE"}
    e1s["role"] = {"n1": '"leader"', "n2": '"follower"', "n3": '"follower"'}
    e1s["voteGranted"]["n1"] = "{n1, n2}"
    e1s["lastLog"] = {"n1": "0", "n2": "-1", "n3": "-1"}
    e1s["logTerm"] = {"n1": ["1", "0", "0"], "n2": ["0", "0", "0"], "n3": ["0", "0", "0"]}
    e1s["committed"] = {"n1": "0", "n2": "-1", "n3": "-1"}
    e1s["matchedIndex"]["n1"] = {"n1": "0", "n2": "0", "n3": "-1"}
    e1s["matchedTerm"]["n1"] = {"n1": "1", "n2": "1", "n3": "0"}
    e1s["witnessIndex"]["n1"] = "0"
    e1s["witnessNodes"]["n1"] = "{n1, n2}"
    e1s["witnessTerm"]["n1"] = "1"
    e1s["leaderState"]["n1"] = "TRUE"
    run("E1s", "update", s3, e1s, UPD_REPORT, mc_consts(2, 2))
    # E1sc: strengthening control: E1s with n2 holding the entry (legal) -> accepted
    e1sc = json.loads(json.dumps(e1s))
    e1sc["lastLog"]["n2"] = "0"
    e1sc["logTerm"]["n2"] = ["1", "0", "0"]
    run("E1sc", "update", s3, e1sc, UPD_REPORT, mc_consts(2, 2))

    # E3 (ProgressMonotonic, action): constructed decrease within one leadership -> violated
    e3a = json.loads(json.dumps(e1sc))
    e3b = json.loads(json.dumps(e3a))
    e3b["matchedIndex"]["n1"]["n2"] = "-1"
    e3b["matchedTerm"]["n1"]["n2"] = "0"
    run("E3", "update", s3, e3a, ['"ProgressMonotonicStep evaluated by PROPERTY"'], mc_consts(2, 2),
        st2=e3b, prop="ProgressMonotonic")
    # E3c: control: trace transition (lifecycle UpdateProgress that commits index 3) -> holds
    k3 = [k for k, n in enumerate(lc_names) if n == "UpdateProgress"
          and load_event("leader_lifecycle", k)["post"]["committed"] == 3][0]
    ev = load_event("leader_lifecycle", k3)
    run("E3c", "update", s3, from_snapshot(ev["pre"], ev["nid"], s3, id3, 6),
        ['"ProgressMonotonicStep evaluated by PROPERTY"'], mc_consts(4, 6),
        st2=from_snapshot(ev["post"], ev["nid"], s3, id3, 6), prop="ProgressMonotonic")

    out = HERE / "results.json"
    prev = json.loads(out.read_text()) if out.exists() else {}
    prev.update({k: {"printed": v[0], "verdict": v[1], "rc": v[2]} for k, v in results.items()})
    out.write_text(json.dumps(prev, indent=1))


def tla_of(v, servers):
    if isinstance(v, bool):
        return "TRUE" if v else "FALSE"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return v if v in servers else '"%s"' % v
    if isinstance(v, list):
        return tset([tla_of(x, servers) for x in v])
    if isinstance(v, dict):
        ks = list(v.keys())
        if ks and all(k in servers for k in ks):
            return "(" + " @@ ".join(f"{k} :> {tla_of(v[k], servers)}" for k in ks) + ")"
        if ks and all(k.lstrip("-").isdigit() for k in ks):
            return "(" + " @@ ".join(f"{k} :> {tla_of(v[k], servers)}" for k in ks) + ")"
        return "[" + ", ".join(f"{k} |-> {tla_of(v[k], servers)}" for k in ks) + "]"
    raise ValueError(v)


def from_tlc_json(path, servers, index=-1):
    t = json.loads(pathlib.Path(path).read_text())
    stj = t["counterexample"]["state"][index][1]
    st = {k: tla_of(stj[k], servers) for k in BASE_VARS}
    return st


def main_mc():
    s3 = ["n1", "n2", "n3"]
    out_dir = HERE.parent / "output"
    res = {}
    # E1mc: final state of the U-S2 canary counterexample (re-elected candidate with older witness)
    st = from_tlc_json(out_dir / "upd-mc-reach_u2_reelection.trace.json", s3)
    res["E1mc"] = write_and_run("E1mc", "update", s3, st, UPD_REPORT + KEEP_REPORT, mc_consts(3, 1))
    # K5: two simultaneous leaders (ElectionSafety records nonempty)
    st = from_tlc_json(out_dir / "upd-mc-reach_ev_TwoLeaders.trace.json", s3)
    res["K5"] = write_and_run("K5", "update", s3, st, UPD_REPORT + KEEP_REPORT, mc_consts(3, 1))
    # K6: two nodes with commits, one with a witness (CommittedLogAgreement records nonempty)
    st = from_tlc_json(out_dir / "upd-mc-reach_ev_TwoCommitted.trace.json", s3)
    res["K6"] = write_and_run("K6", "update", s3, st, UPD_REPORT + KEEP_REPORT, mc_consts(3, 1))
    for k, v in res.items():
        print(k, v)
    out = HERE / "results.json"
    prev = json.loads(out.read_text()) if out.exists() else {}
    prev.update({k: {"printed": v[0], "verdict": v[1], "rc": v[2]} for k, v in res.items()})
    out.write_text(json.dumps(prev, indent=1))


if __name__ == "__main__":
    if sys.argv[1:2] == ["--mc"]:
        main_mc()
    else:
        main()
