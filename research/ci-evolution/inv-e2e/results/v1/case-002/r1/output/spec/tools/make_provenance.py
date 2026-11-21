"""Collect provenance: inputs, source identity, harness, traces, TLC runs."""
import hashlib, json, os, re, subprocess, glob
R = "/work/current/.specula-output"
def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()
def git(*a):
    return subprocess.run(["git", "-C", R + "/artifact", *a], capture_output=True, text=True).stdout.strip()
traces = []
for p in sorted(glob.glob(R + "/traces/*.ndjson")):
    lines = open(p).read().splitlines()
    ev = [l for l in lines if '"tag":"trace"' in l]
    names = {}
    for l in ev:
        n = json.loads(l)["event"]["name"]; names[n] = names.get(n, 0) + 1
    traces.append({"path": os.path.relpath(p, R), "events": len(ev), "sha256": sha(p), "event_counts": names})
runs = []
for p in sorted(glob.glob(R + "/spec/output/mc-*.log")) + sorted(glob.glob(R + "/spec/output/trace-*.log")):
    t = open(p, errors="replace").read()
    cmd = re.search(r"^# cmd: (.*)$", t, re.M)
    ex = re.search(r"^# exit: (\d+)", t, re.M)
    viol = re.findall(r"(Invariant \w+ is violated|Temporal property \w+ was violated|Action property \w+ is violated)", t)
    st = re.findall(r"([\d,]+) distinct states found", t)
    depth = re.findall(r"depth of the complete state graph search is (\d+)", t)
    left = re.findall(r"([\d,]+) states left on queue", t)
    runs.append({"log": os.path.relpath(p, R), "command": cmd.group(1) if cmd else None,
                 "exit": int(ex.group(1)) if ex else None, "violations": sorted(set(viol)),
                 "distinct_states": st[-1] if st else None, "depth": depth[-1] if depth else None,
                 "queue_left": left[-1] if left else None,
                 "completed_without_error": "No error has been found" in t})
inputs = {}
for p in ["/work/case.json", "/work/model-scope.md", "/work/input-manifest.json", "/work/final-schema.json",
          "/work/lib/tla2tools.jar", "/work/lib/CommunityModules-deps.jar"]:
    inputs[p] = sha(p)
for root in ["/work/old-source", "/work/new-source"]:
    for p in sorted(glob.glob(root + "/**/*.java", recursive=True)):
        inputs[p] = sha(p)
man = {
  "schema_version": 1, "case_id": "case-002", "purpose": "incremental_update_verification",
  "decision": "MODEL_CHANGE_REQUIRED",
  "source": {"artifact": R + "/artifact", "baseline_commit": git("rev-parse", "HEAD~1"),
             "update_commit": git("rev-parse", "HEAD"), "update_subject": git("log", "-1", "--format=%s"),
             "instrumented_worktree_diff_stat": git("diff", "--stat").splitlines()[-1:] ,
             "old_control_worktree": R + "/old-control (baseline + DIFFSyncConsistencyTest + repro test)",
             "history_or_external_research_used": False},
  "prior_suite": "/work/previous/.specula-output (immutable; archived copies in spec/output/prior-v0)",
  "inputs_sha256": inputs,
  "harness": {"run": "harness/run.sh", "patch": "harness/patches/instrumentation.patch",
              "patch_sha256": sha(R + "/harness/patches/instrumentation.patch"),
              "repro_test": "harness/repro/SpeculaInitialStateFailureReproTest.java",
              "old_control": "harness/repro/run-old-control.sh",
              "java": "/usr/lib/jvm/java-21-openjdk-amd64 (JDK 21; same environment limitation as V0)"},
  "traces": traces,
  "archived_v0_traces": "traces/archived-v0 (superseded: pre-update NEWLEADER ordering and V0 event schema)",
  "superseded_run1_traces": "traces/superseded-run1 (probe-ordering defects fixed before run 2)",
  "negative_controls": "traces/negative-controls (all rejected)",
  "tlc_runs": runs,
  "tlc_states_dir": "/dev/shm/specula-e2e-case-002 (removed after each run)",
}
json.dump(man, open(R + "/provenance-manifest.json", "w"), indent=2)
print("traces", len(traces), "runs", len(runs))
