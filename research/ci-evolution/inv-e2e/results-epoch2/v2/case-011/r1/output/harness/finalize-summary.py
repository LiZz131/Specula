#!/usr/bin/env python3
"""Regenerate model-checking-summary, update validation-summary.json and the bug report's campaign table."""
import json, os, re, subprocess
root = os.path.dirname(os.path.abspath(__file__)) + "/.."
subprocess.run(["python3", "-I", root + "/harness/summarize-mc.py"], check=True, stdout=subprocess.DEVNULL)
rows = json.load(open(root + "/spec/model-checking-summary.json"))
traces = sorted(f[:-7] for f in os.listdir(root + "/traces") if f.endswith(".ndjson"))
final = open(root + "/spec/output/trace-validation-final.log").read()
vs = {
 "status": "LIMITED_COVERAGE",
 "run": "incremental (Pre-Vote update), case-011",
 "decision": "MODEL_CHANGE_REQUIRED",
 "source": {"baseline": "1adc857f05fc8632eca18a7ce636f9c489dd5038", "update": "3ab6cddc34a5bf127747434bb41e20a1b9ef7769"},
 "toolchain_used": "stable rustc 1.100.0 (pinned nightly-2026-03-01 unavailable)",
 "baseline_tests_new_source": {"openraft_library": "486 passed", "elect": "8 passed", "membership": "44 passed", "life_cycle": "14 passed"},
 "harness": {"rebased": True, "method": "copy-and-patch (V0 git patch no longer applies)", "command": "bash harness/run.sh"},
 "trace_validation": {"fresh_traces": len(traces), "passed_final": final.count("PASS"), "log": "spec/output/trace-validation-final.log",
                      "completion_property": "TraceConsumed", "field_mutants_rejected": "20/20",
                      "archived_v0_traces": "superseded by fresh regenerations (missing mandatory update fields)"},
 "model_checking": [{k: r[k] for k in ("label", "cfg", "mode", "status", "violations", "coverage", "log")} for r in rows],
 "findings": {"MC-1": "REPRODUCED", "MC-2": "REPRODUCED", "CR-PRE-1": "REPRODUCED (pre-existing, both revisions)",
              "D-3": "REPRODUCED (documentation)", "D-2": "NEEDS MORE INFO (unresolved requirement)"},
 "cleanup": {"tlc_state_dirs_removed_after_each_run": True},
 "limitations": [
  "3 nodes, MaxTerm 2 (3 in traces), MaxLogIndex 4, bounded elections/pre-vote starts/membership changes/crash/drop/messages",
  "BFS runs stopped by their 30-minute budget are LIMITED_COVERAGE (non-empty queue), not exhaustive",
  "time (timeouts, leases, RPC ttl, round rate limit) abstracted; message delivery across a restart is an over-approximation",
  "engine-level traces; runtime command execution between events replayed by the harness",
  "no liveness property claimed"]}
json.dump(vs, open(root + "/validation-summary.json", "w"), indent=1)
br = open(root + "/spec/bug-report.md").read()
tbl = ["| Run | Config | Mode | Outcome | Violations | Coverage |", "|---|---|---|---|---|---|"]
for r in rows:
    tbl.append("| %s | %s | %s | %s | %s | %s |" % (r["label"], r["cfg"], r["mode"], r["status"], ", ".join(r["violations"]) or "—", r["coverage"]))
start = br.index("## Not reproduced / not found")
br = br[:start] + "## Not reproduced / not found (all campaigns; generated from spec/output/mc-*.log)\n\n" + "\n".join(tbl) + "\n\nCanary violations are expected reachability witnesses. Runs without violations are budget-limited unless the queue is 0. Archived superseded/discarded logs (`*.superseded*`, `*.stopped*`, `*.discarded*`) are excluded; see `spec/changelog.md`.\n"
open(root + "/spec/bug-report.md", "w").write(br)
print("ok", len(rows), "runs")
