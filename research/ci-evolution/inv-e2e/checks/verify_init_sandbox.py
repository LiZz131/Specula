import subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1]))
from agent import MAIN_TOOLS_MOUNT, bwrap_command
from run_init import RO, RW
ws = Path(sys.argv[1]); mt = sys.argv[2]
script = r'''
set -u
echo "== env"; env | grep -i -E "specul|^PATH" | sort
echo "== which"; command -v specular
echo "== help"; specular --help 2>&1 | head -5; echo "help rc=${PIPESTATUS[0]}"
echo "== ls /work"; ls -A /work
for p in source scope.md task.md final-schema.json input-manifest.json lib tools .agents/skills .claude/skills; do
  if touch /work/$p/.probe 2>/dev/null || { [ -f /work/$p ] && echo x >> /work/$p 2>/dev/null; }; then echo "WRITABLE(bad) $p"; rm -f /work/$p/.probe; else echo "ro ok $p"; fi
done
for p in work-source prior/.specular-output .cache/tmp; do
  if touch /work/$p/.probe 2>/dev/null; then echo "rw ok $p"; rm -f /work/$p/.probe; else echo "NOT WRITABLE(bad) $p"; fi
done
echo "== skills"; ls /work/.claude/skills
echo "== git source"; cd /work/source && git log --oneline --all && git remote | wc -l
echo "== git work-source status"; cd /work/work-source && git status --porcelain | wc -l
echo "== no upward"; ls /mydata 2>&1 | head -2; ls /users 2>&1 | head -2
echo "== java"; java -cp /work/lib/tla2tools.jar tla2sany.SANY -help 2>&1 | head -2
echo "== guard"; curl https://example.com 2>&1 | head -2
'''
with tempfile.TemporaryDirectory() as home:
    cmd = bwrap_command(ws, RO, RW, [(mt, MAIN_TOOLS_MOUNT), (str(ws / ".agents/skills"), "/work/.claude/skills")],
                        Path(home), ["bash", "-c", script], specular_env=True)
    r = subprocess.run(cmd, env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}, text=True, capture_output=True)
    print(r.stdout[-6000:]); print("STDERR:", r.stderr[-3000:]); print("exit", r.returncode)
