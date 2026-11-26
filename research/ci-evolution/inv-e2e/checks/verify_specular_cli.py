import subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1]))
from agent import MAIN_TOOLS_MOUNT, bwrap_command
from run import RO, RW
ws = Path(sys.argv[1]); mt = sys.argv[2]
script = r'''
set -u
echo "== env"; env | grep -i specul | sort
echo "== which"; command -v specular
echo "== help"; specular --help 2>&1 | head -8
echo "== findings lookup"; specular findings --work=/work/current/.specular-output lookup; echo "rc=$?"
echo "== ci-result (one finding)"; echo "repro: synthetic sandbox check" > /work/current/.specular-output/spec/confirmation-T-1.md
cat > /work/current/.specular-output/spec/final-result.json <<J
{"version": 1, "run_id": "$(python3 -c 'import json;print(json.load(open("/work/current/.specular-output/persistent-findings-context.json"))["run_id"])')",
 "summary": "sandbox check", "validation_limits": [], "findings": [{"id":"T-1","title":"synthetic check","status":"REPRODUCED","source":"code-review","cause":"c","trigger":"t","consequence":"x","evidence":["spec/confirmation-T-1.md"],"persistence":{"premises":["p"],"dependencies":[{"root":"source","path":"Cargo.toml"}]}}]}
J
specular ci-result --work=/work/current/.specular-output; echo "rc=$?"
ls /work/current/.specular-output | grep -E "ci-report|ci-verdict|confirmed-bugs|bug-severity"
echo "== old name"; specula --help 2>&1 | head -2
'''
with tempfile.TemporaryDirectory() as home:
    cmd = bwrap_command(ws, RO + ["ci-run"], RW, [(mt, MAIN_TOOLS_MOUNT)], Path(home), ["bash", "-c", script], specular_env=True)
    r = subprocess.run(cmd, env={"PATH": "/usr/bin:/bin", "LANG": "C.UTF-8"}, text=True, capture_output=True)
    print(r.stdout[-6000:]); print("STDERR:", r.stderr[-3000:]); print("exit", r.returncode)
