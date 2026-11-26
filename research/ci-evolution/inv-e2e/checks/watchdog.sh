#!/usr/bin/env bash
# One watchdog tick: sleep, then report pilot/round progress.
W=${W:?set W to the experiment WORK dir}; LOG=${LOG:?set LOG to the round log}
sleep ${SLEEP:-1800}
echo "== $(date '+%F %T')"; tail -4 "$LOG"
A=$(ls -t $W/attempts/*/*/r*/log/activity.jsonl 2>/dev/null | head -1)
if [ -n "$A" ]; then
  echo "activity: $A size=$(stat -c %s "$A") age_min=$(( ($(date +%s) - $(stat -c %Y "$A")) / 60 ))"
  python3 - "$A" <<'PY'
import json, sys, re, collections
calls = collections.Counter(); spec = []; errs = []; names = {}; usage = {}
for line in open(sys.argv[1], errors="replace"):
    try: ev = json.loads(line)
    except Exception: continue
    if ev.get("type") == "assistant":
        m = ev["message"]
        if m.get("id") and isinstance(m.get("usage"), dict): usage[m["id"]] = m["usage"]
        for b in m.get("content") or []:
            if b.get("type") == "tool_use":
                names[b["id"]] = b["name"]; calls[b["name"]] += 1
                c = (b.get("input") or {}).get("command", "")
                if isinstance(c, str) and re.search(r"(?:^|[;&|(]\s*|\s)specular\s|specula-output|SPECULA_|(?<![\w.])specula\b", c): spec.append((b["id"], c[:160]))
    elif ev.get("type") == "user" and isinstance(ev.get("message", {}).get("content"), list):
        for b in ev["message"]["content"]:
            if b.get("type") == "tool_result" and b.get("is_error") and names.get(b.get("tool_use_id"), "").startswith("mcp__"):
                errs.append(json.dumps(b.get("content"))[:200])
mcp = {k: v for k, v in calls.items() if k.startswith("mcp__")}
out = sum(u.get("output_tokens", 0) for u in usage.values())
print(f"api_msgs={len(usage)} out_tokens={out} tools={sum(calls.values())} mcp={mcp}")
print(f"specular-related commands: {len(spec)}"); [print("  ", c) for _, c in spec[-4:]]
print(f"mcp errors: {len(errs)}"); [print("  ", e) for e in errs[-3:]]
PY
fi
echo "bwrap=$(pgrep -c bwrap) tlc=$(pgrep -c -f "^[^ ]*java .*tlc2")"
python3 -c "import json,time;d=json.load(open('/users/bingzhuo/.claude/.credentials.json'))['claudeAiOauth'];print('credential_h_left=%.2f'%((d['expiresAt']/1000-time.time())/3600))"
# Subscription quota of the saved accounts (claude-accounts skill); a window >= 90% means switch accounts.
command -v ca >/dev/null && ca usage 2>&1 | sed -n '1,6p'
