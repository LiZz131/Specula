import subprocess, sys, tempfile
from pathlib import Path
sys.path.insert(0, str(__import__("pathlib").Path(__file__).resolve().parents[1]))
from agent import MAIN_TOOLS_MOUNT, bwrap_command
from run import RO, RW
ws = Path(sys.argv[1]); mt = sys.argv[2]
script = 'cd /work/current/.specular-output/artifact && ls rust-toolchain* && cargo --version && rustc --version && RUSTUP_TOOLCHAIN=nightly-2025-12-31 rustc --version'
with tempfile.TemporaryDirectory() as home:
    cmd = bwrap_command(ws, RO + ["ci-run"], RW, [(mt, MAIN_TOOLS_MOUNT)], Path(home), ["bash", "-c", script], specular_env=True)
    r = subprocess.run(cmd, env={"PATH": "/usr/bin:/bin"}, text=True, capture_output=True); print(r.stdout, r.stderr[-1500:], r.returncode)
