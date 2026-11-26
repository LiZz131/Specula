import subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1]))
from agent import MAIN_TOOLS_MOUNT, bwrap_command
from run import RO, RW
ws = Path(sys.argv[1]); mt = sys.argv[2]
script = 'specular findings --work=/work/current/.specular-output lookup --query synthetic; specular findings --work=/work/current/.specular-output check --id T-1'
with tempfile.TemporaryDirectory() as home:
    cmd = bwrap_command(ws, RO + ["ci-run"], RW, [(mt, MAIN_TOOLS_MOUNT)], Path(home), ["bash", "-c", script], specular_env=True)
    r = subprocess.run(cmd, env={"PATH": "/usr/bin:/bin"}, text=True, capture_output=True); print(r.stdout[-2000:], r.stderr[-1000:], r.returncode)
