import json, sys, glob, collections, re
for f in sorted(glob.glob(sys.argv[1] if len(sys.argv) > 1 else "/mydata/bingzhuo/inv-e2e-epoch2/attempts/*/*/r*/log/activity.jsonl")):
    names = {}; errs = collections.Counter(); samples = {}; calls = collections.Counter()
    for line in open(f, errors="replace"):
        try: ev = json.loads(line)
        except: continue
        if ev.get("type") == "assistant":
            for b in ev["message"].get("content", []) or []:
                if b.get("type") == "tool_use":
                    names[b["id"]] = b["name"]; calls[b["name"]] += 1
        elif ev.get("type") == "user":
            c = ev.get("message", {}).get("content")
            if isinstance(c, list):
                for b in c:
                    if b.get("type") == "tool_result":
                        n = names.get(b.get("tool_use_id"), "?")
                        txt = json.dumps(b.get("content"))[:400]
                        bad = b.get("is_error") or (n.startswith("mcp__") and re.search(r'"(error|Error)|Traceback|not found|failed', txt))
                        if bad:
                            errs[n] += 1; samples.setdefault(n, txt)
    print("==", f.split("attempts/")[1].split("/log")[0])
    print("  mcp calls:", {k: v for k, v in calls.items() if k.startswith("mcp__")})
    for n, k in errs.most_common():
        if n.startswith("mcp__"): print("  ERR", n, k, "|", samples[n][:300])
