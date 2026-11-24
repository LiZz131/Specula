#!/usr/bin/env python3
"""Run one dismissal canary probe.

usage: run_probe.py ARM CASE ID MODULE BASECFG MODE [TIMEOUT]
  MODE = sim | bfs
The probe module probes/<arm>/<case>/Probe_<ID>.tla must already exist in the
output tree; it EXTENDS MODULE and defines NotCanary (state invariant) or
NotCanaryAct (action property, [][...]_vars form).  This script copies it into
the working copy of the spec (/mydata/bingzhuo/evidence-work/i4/<arm>/<case>/spec),
derives Probe_<ID>.cfg from BASECFG (INVARIANT/PROPERTY sections replaced),
runs TLC, and writes a trimmed log + result json next to the probe.
"""
import json, os, re, shutil, subprocess, sys, time, tempfile

OUT = "/users/bingzhuo/Specula/research/ci-evolution/inv-e2e/analysis/epoch-1/dismissals/probes"
WORK = "/mydata/bingzhuo/evidence-work/i4"
TLA = "/mydata/bingzhuo/src/Specula/lib/tla2tools.jar"
KEYS = ["SPECIFICATION", "INIT", "NEXT", "CONSTANTS", "CONSTANT", "INVARIANTS", "INVARIANT",
        "PROPERTIES", "PROPERTY", "CONSTRAINTS", "CONSTRAINT", "ACTION_CONSTRAINTS",
        "ACTION_CONSTRAINT", "VIEW", "SYMMETRY", "CHECK_DEADLOCK", "POSTCONDITION", "ALIAS"]
DROP = {"INVARIANTS", "INVARIANT", "PROPERTIES", "PROPERTY", "POSTCONDITION", "ALIAS"}


def derive_cfg(base, pid, action):
    out, keep = [], True
    for line in open(base):
        s = line.strip()
        m = re.match(r"([A-Z_]+)\b", s)
        if m and m.group(1) in KEYS:
            keep = m.group(1) not in DROP
        if keep:
            out.append(line.rstrip("\n"))
    if action:
        out.append("PROPERTY NotCanaryAct")
    else:
        out.append("INVARIANT NotCanary")
    return "\n".join(out) + "\n"


def main():
    arm, case, pid, module, basecfg, mode = sys.argv[1:7]
    to = int(sys.argv[7]) if len(sys.argv) > 7 else (300 if mode == "sim" else 1800)
    spec = f"{WORK}/{arm}/{case}/spec"
    odir = f"{OUT}/{arm}/{case}"
    probe = f"{odir}/Probe_{pid}.tla"
    src = open(probe).read()
    action = "NotCanaryAct" in src
    shutil.copy(probe, f"{spec}/Probe_{pid}.tla")
    cfgtxt = derive_cfg(f"{spec}/{basecfg}", pid, action)
    cfgtxt = f"\\* derived from {basecfg} (run's own cfg); invariants/properties replaced by the negated canary\n" + cfgtxt
    open(f"{odir}/Probe_{pid}.cfg", "w").write(cfgtxt)
    open(f"{spec}/Probe_{pid}.cfg", "w").write(cfgtxt)
    lib = f"/mydata/bingzhuo/inv-e2e/attempts/{arm}/{case}/r1/ws/lib/CommunityModules-deps.jar"
    meta = tempfile.mkdtemp(prefix=f"i4-{arm}-{case}-{pid}-", dir="/mydata/bingzhuo/evidence-work/i4/meta")
    if mode.startswith("sim"):
        jargs = ["-Xmx4g"]
        targs = ["-simulate", "-depth", "100", "-workers", "1"]
    else:
        jargs = ["-Xmx16g", "-XX:+UseParallelGC"]
        targs = ["-workers", "8"]
    cmd = ["timeout", str(to), "java", *jargs, "-cp", f"{TLA}:{lib}", "tlc2.TLC", "-deadlock",
           "-cleanup", "-metadir", meta, *targs, "-config", f"Probe_{pid}.cfg", f"Probe_{pid}.tla"]
    t0 = time.time()
    p = subprocess.run(cmd, cwd=spec, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
    dt = time.time() - t0
    shutil.rmtree(meta, ignore_errors=True)
    for f in os.listdir(spec):
        if "_TTrace_" in f:
            os.remove(os.path.join(spec, f))
    shutil.rmtree(f"{spec}/states", ignore_errors=True)
    log = p.stdout
    viol = re.search(r"(Invariant NotCanary is violated|Action property NotCanaryAct|Temporal properties were violated|Error: Action property)", log)
    err = re.search(r"(Error: |Exception|Parse Error|Semantic error|Unknown operator)", log)
    states = re.findall(r"^State (\d+): (<[^>]*>|.*)$", log, re.M)
    if viol:
        result = "reachable"
    elif p.returncode == 124:
        result = "not_reached_in_budget"
    elif "Model checking completed. No error has been found." in log or "No error has been found" in log:
        result = "exhausted_not_reached" if mode == "bfs" else "sim_finished_not_reached"
    elif err:
        result = "error"
    else:
        result = "unknown_rc%d" % p.returncode
    depth = len(states) if viol else None
    stats = [l for l in log.splitlines() if not l.startswith("State ") and re.search(r"(states generated|distinct states|depth of the complete|Finished in|traces generated|The number of states|mean length|Progress\(|Running|Starting|Error|error|violated|Exception|Parse|Semantic|line \d+, col)", l)]
    # trace: action-line per state plus the last state in full
    trace, last = [], []
    blocks = re.split(r"\n(?=State \d+: )", log)
    sb = [b for b in blocks if re.match(r"State \d+: ", b)]
    for b in sb:
        trace.append(b.splitlines()[0])
    if sb:
        last = []
        for l in sb[-1].splitlines():
            if re.match(r"(The number of states|Progress|Finished|[0-9]+ states generated|Error:)", l):
                break
            last.append(l)
    tail = ""
    if result == "error":
        tail = "\n".join(log.splitlines()[-60:])
    with open(f"{odir}/Probe_{pid}.{mode}.log", "w") as f:
        f.write("COMMAND: (cd %s && %s)\n" % (spec, " ".join(cmd)))
        f.write("rc=%d wall=%.1fs result=%s depth=%s\n" % (p.returncode, dt, result, depth))
        f.write("\n".join(stats[-40:]) + "\n")
        if trace:
            f.write("--- counterexample action sequence ---\n" + "\n".join(trace) + "\n")
            f.write("--- final state ---\n" + "\n".join(last[:200]) + "\n")
        if tail:
            f.write("--- tail ---\n" + tail + "\n")
    res = dict(arm=arm, case=case, id=pid, module=module, cfg=basecfg, mode=mode, result=result,
               depth=depth, seconds=round(dt, 1), rc=p.returncode)
    json.dump(res, open(f"{odir}/Probe_{pid}.{mode}.json", "w"))
    print(json.dumps(res))


if __name__ == "__main__":
    main()
