"""Build a markdown table of TLC campaign outcomes from spec/output/mc-*.log."""
import re, glob, os, sys
R = "/work/current/.specula-output/spec/output"
# Reference revisions: rev-A before 2026-11-18T20:39:30Z (before the
# fast-forward-floor and SyncDiff/SyncSnap repairs), rev-B until
# 2026-11-18T21:52:06Z (before the pending-queue and sticky epoch-ack repairs),
# final afterwards (spec/output/FINAL_MODEL_SHA256).
FINAL_MODEL_FROM = "2026-11-18T21:52:06Z"
REV_B_FROM = "2026-11-18T20:39:30Z"
rows = []
for p in sorted(glob.glob(R + "/mc-*.log")):
    t = open(p, errors="replace").read()
    tag = os.path.basename(p)[3:-4]
    cmd = re.search(r"^# cmd: (.*)$", t, re.M); cmd = cmd.group(1) if cmd else ""
    cfg = re.search(r"-config (\S+)", cmd); cfg = cfg.group(1) if cfg else "?"
    mode = "sim" if "-simulate" in cmd else "BFS"
    mins = re.search(r"stopAfter=(\d+)", cmd); mins = int(mins.group(1)) // 60 if mins else None
    workers = re.search(r"-workers (\d+)", cmd); workers = workers.group(1) if workers else "?"
    viol = re.findall(r"(?:Invariant|Temporal property|Action property) (\w+) (?:is|was) violated", t)
    ds = re.findall(r"([\d,]+) distinct states found", t)
    gen = re.findall(r"([\d,]+) states generated|states checked[^\n]*|The number of states generated: (\d+)", t)
    simstates = re.findall(r"(\d+) states checked, (\d+) traces generated", t)
    depth = re.findall(r"depth of the complete state graph search is (\d+)", t)
    left = re.findall(r"([\d,]+) states left on queue", t)
    ex = re.search(r"^# exit: (\d+)", t, re.M); ex = ex.group(1) if ex else "killed/running"
    if viol:
        status = "VIOLATION " + ",".join(sorted(set(viol)))
    elif ex == "0" and mode == "BFS" and left and left[-1].replace(",", "") != "0":
        status = "no violation; LIMITED_COVERAGE (time budget, queue %s)" % left[-1]
    elif ex == "0" and mode == "BFS":
        status = "no violation; state space exhausted within constraint"
    elif ex == "0":
        status = "no violation; LIMITED_COVERAGE (simulation budget)"
    else:
        status = "exit %s" % ex
    size = (ds[-1] + " distinct") if ds and mode == "BFS" else ((simstates[-1][0] + " states / " + simstates[-1][1] + " traces") if simstates else "-")
    st = re.search(r"^# started: (\S+)", t, re.M); st = st.group(1) if st else ""
    model = "final" if st >= FINAL_MODEL_FROM else ("rev-B (provisional)" if st >= REV_B_FROM else "rev-A (provisional)")
    rows.append((tag, cfg, mode, str(mins), workers, size, depth[-1] if depth else "-", status, model))
print("| Run | Config | Mode | Budget (min) | Workers | Explored | Depth | Outcome | Model |")
print("|---|---|---|---|---|---|---|---|---|")
for r in rows:
    print("| " + " | ".join(r) + " |")
