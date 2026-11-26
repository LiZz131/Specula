import re,os,glob
runs=[
("Standard convergence (reference props)","MC.tla","MC.cfg","mc-standard-bfs","BFS"),
("Standard convergence follow-up","MC.tla","MC.cfg","mc-standard-sim","simulation depth 150"),
("1 Full update check (all update props, full MCNext)","Update.tla","Update-full.cfg","update-full-bfs","BFS"),
("1 Full update check follow-up","Update.tla","Update-full.cfg","update-full-sim","simulation depth 150"),
("1 Full MCNext hunt U2","Update.tla","Update-hunt-ackorder.cfg","update-hunt-ackorder-sim","simulation depth 120"),
("1 Full MCNext hunt U3","Update.tla","Update-hunt-npe.cfg","update-hunt-npe-sim","simulation depth 120"),
("1 Full MCNext hunt U4","Update.tla","Update-hunt-split.cfg","update-hunt-split-sim","simulation depth 120"),
("1 Full MCNext hunt U1 (stopped after U1 established elsewhere)","Update.tla","Update-hunt-durability.cfg","update-hunt-durability-sim","simulation depth 120"),
("1 Full MCNext hunt CommittedAgreement (stopped, replaced by seeded)","Update.tla","Update-hunt-agreement.cfg","update-hunt-agreement-sim","simulation depth 120"),
("1 Full MCNext from seeded states, U1","Update.tla","Update-seeded-durability.cfg","update-seeded-durability-bfs","BFS"),
("1 Full MCNext from seeded states, CommittedAgreement","Update.tla","Update-seeded-agreement.cfg","update-seeded-agreement-sim","simulation depth 60"),
("2 Concrete focused (all props)","Update.tla","Update-focused.cfg","update-focused-bfs","BFS"),
("2 Concrete focused U1","Update.tla","Update-focused-durability.cfg","update-focused-durability-bfs","BFS"),
("2 Concrete focused U3","Update.tla","Update-focused-npe.cfg","update-focused-npe-bfs","BFS"),
("2 Concrete focused U4","Update.tla","Update-focused-split.cfg","update-focused-split-bfs","BFS"),
("2 Concrete focused reference props","Update.tla","Update-focused-reference.cfg","update-focused-reference-bfs","BFS"),
("3 Open focused (all props)","Update.tla","Update-open.cfg","update-open-bfs","BFS"),
("3 Open focused U4 + reference","Update.tla","Update-open-split.cfg","update-open-split-bfs","BFS"),
("3 Discharge r1 (rely frame bug)","Update.tla","Update-discharge.cfg","update-discharge-bfs-r1-frame-mismatch","BFS"),
("3 Discharge (fixed rely)","Update.tla","Update-discharge.cfg","update-discharge-bfs","BFS"),
]
out=["| Campaign | Spec / cfg | Mode | Outcome | Coverage (last report) | Log |","|---|---|---|---|---|---|"]
for name,mod,cfg,log,mode in runs:
    p=f"output/{log}.log"
    if not os.path.exists(p): out.append(f"| {name} | {mod} / {cfg} | {mode} | NOT RUN | | |"); continue
    t=open(p).read()
    v=re.findall(r"^Error: (Invariant \w+ is violated|Action property \w+ is violated|Temporal property \w+ was violated)",t,re.M)
    ex=re.findall(r"# exit: (\d+)",t)
    prog=re.findall(r"^Progress.*$",t,re.M)
    fin=re.findall(r"^([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue",t,re.M)
    depth=re.findall(r"The depth of the complete state graph search is (\d+)",t)
    states=len(re.findall(r"^State \d+:",t,re.M))
    if v: outcome=f"VIOLATION: {v[0]} ({states} states)"
    elif ex and ex[0]=="124": outcome="no violation; 30-min budget reached (LIMITED_COVERAGE)"
    elif ex and ex[0]=="0": outcome="no violation; completed"
    elif ex and ex[0]=="143": outcome="no violation; stopped early (see name)"
    elif not ex: outcome="RUNNING"
    else: outcome=f"exit {ex[0]}"
    cov=(prog[-1][:150] if prog else "")
    if fin: cov=f"{fin[-1][1]} distinct, {fin[-1][2]} queued"+(f", depth {depth[-1]}" if depth else "")
    out.append(f"| {name} | {mod} / {cfg} | {mode} | {outcome} | {cov} | `spec/{p}` |")
can=open("output/canary-summary.log").read().strip().splitlines() if os.path.exists("output/canary-summary.log") else []
print("\n".join(out))
print("\nReachability canaries (Update.tla, MCSpec full MCNext; a violation is the witness):\n")
print("| Canary | Result |\n|---|---|")
for c in can:
    parts=c.split()
    print(f"| {parts[0]} | {' '.join(parts[1:3])} (`spec/output/canary-{parts[0]}.log`) |")
