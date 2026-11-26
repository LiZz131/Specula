import subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1]))
from agent import MAIN_TOOLS_MOUNT, bwrap_command
from run import RO, RW
ws = Path(sys.argv[1]); mt = sys.argv[2]
script = r'''cd /work/current/tmp-tlc && ls /work/tools && /work/tools/start_background.sh -s Lasso.tla -c stuttering.cfg -o out.log -t 5 -m 4G -M 4G -w 2 2>&1 | tail -6
/work/tools/wait_for_pid.sh --pid-file out.log.pid --timeout 5m --log out.log 2>&1 | tail -3
grep -h "violated\|Finished\|Error" out.log | head -5'''
with tempfile.TemporaryDirectory() as home:
    cmd = bwrap_command(ws, RO + ["ci-run"], RW + [".stop-gate", ".tlc-tasks"], [(mt, MAIN_TOOLS_MOUNT)], Path(home), ["bash", "-c", script], specular_env=True)
    r = subprocess.run(cmd, env={"PATH": "/usr/bin:/bin"}, text=True, capture_output=True, timeout=600); print(r.stdout[-3000:], r.stderr[-1500:], r.returncode)
