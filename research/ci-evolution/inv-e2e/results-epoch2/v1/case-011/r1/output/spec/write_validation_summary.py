#!/usr/bin/env python3
"""Write .specula-output/validation-summary.json for the incremental run."""
import json, os, re, glob
SPEC = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(SPEC)
camp = json.load(open(os.path.join(SPEC, 'output', 'campaign-summary.json')))
by = {r['run']: r for r in camp}
traces = sorted(os.path.basename(p)[:-7] for p in glob.glob(os.path.join(ROOT, 'traces', '*.ndjson')))
tv = open(os.path.join(SPEC, 'output', 'trace-validation-final.log')).read()
passed = re.findall(r'^PASS (\S+) \((\d+) events\)', tv, re.M)
def pick(*names):
    return {n: {k: by[n].get(k) for k in ('config', 'mode', 'verdict', 'violation', 'distinct', 'states_checked', 'traces', 'depth', 'queue', 'counterexample_states', 'log', 'notes') if by[n].get(k) is not None} for n in names if n in by}
summary = {
  "status": "LIMITED_COVERAGE",
  "disposition": "MODEL_CHANGE_REQUIRED",
  "source": {"old": "artifact 1adc857 (baseline)", "new": "artifact 3ab6cdd (update)", "instrumented_copy": "work-source = 3ab6cdd + harness/instrumentation.patch (test-only)"},
  "toolchain_used": "stable 1.100.0 (pinned nightly-2026-03-01 not installed)",
  "harness": {"reused_from": "/work/previous/.specula-output/harness", "rebase": "V0 patch failed only on openraft/src/engine/mod.rs context; trace module reused and extended",
              "command": "harness/run.sh", "observations": "harness/run-observations.sh -> spec/output/observations.log"},
  "trace_validation": {
     "status": "PASS (all fresh traces fully consumed)",
     "fresh_traces": len(traces), "passed": len(passed), "events_total": sum(int(e) for _, e in passed),
     "inventory": {n: int(e) for n, e in passed},
     "completion_property": "TraceConsumed (temporal, checked on the complete state space)",
     "final_log": "spec/output/trace-validation-final.log",
     "field_consumption": "spec/output/trace-field-consumption.log",
     "mutation_controls": "spec/output/trace-mutation-controls.log (9/9 rejected)",
     "archived_v0_traces": "traces/archive-v0 (superseded by fresh reruns; lack mandatory new fields)"},
  "model_checking": {
     "standard": pick('MC', 'MC-membership'),
     "update_full": pick('Update_full', 'Update_full_cont1', 'Update_full_cont2', 'Update_full_cont2-sim'),
     "concrete_focused": pick('Update_focused', 'Update_focused-sim', 'Update_focused_cont'),
     "open_focused": pick('Update_open', 'Update_open_cont', 'Update_open-evalerror'),
     "discharge": pick('Update_discharge'),
     "hunts": pick('hunt-leader-demote-bfs', 'hunt-leader-demote-cont', 'hunt-leader-demote-cont-sim', 'hunt-livelock-bfs', 'hunt-livelock-phased-bfs', 'hunt-livelock-cont-sim', 'hunt-livelock-directed-bfs', 'hunt-livelock-directed-sim'),
     "canaries": pick(*[r['run'] for r in camp if r['run'].startswith('canary-')]),
     "livelock_witness": {"closure": "spec/witness/livelock/closure_on.log (exhaustive, 1456 distinct, no live leader, votes frozen)",
                          "old_behaviour_control": "spec/witness/livelock/control_off.log (live leader reachable)"},
     "prior_v0_vacuity_check": "spec/output/prior-v0-vacuity-canary.log"},
  "findings": [{"id": "MC-1", "property": "NoPermanentPreVoteLivelock", "severity": "High"},
               {"id": "MC-2", "property": "PreVoteQuorumNeverDemotesLeader", "severity": "Medium"}],
  "cleanup": {"tlc_state_root": "/dev/shm/specula-e2e-case-011 (per-run directories removed)", "background_processes_remaining": False},
  "limitations": [
     "Finite three-node universe; bounded terms, log indices, messages, elections, operator triggers, membership changes, crashes, restarts and drops",
     "No full-model BFS exhausted its queue within the 30-minute budgets; simulation runs are random and non-exhaustive",
     "Livelock witness found under a pruning-only search monitor; liveness is checked as a safety witness plus closure, without fairness assumptions",
     "Engine-level harness: runtime tick, operator command and runtime correlation filter are model-checked but not traced",
     "Multi-node schedules of the findings were not replayed on the real runtime (Part 4 not executed); real-engine observations cover the per-node mechanisms",
     "TLC uses probabilistic fingerprints; collision estimates are in the logs"]}
json.dump(summary, open(os.path.join(ROOT, 'validation-summary.json'), 'w'), indent=1)
print('ok')
