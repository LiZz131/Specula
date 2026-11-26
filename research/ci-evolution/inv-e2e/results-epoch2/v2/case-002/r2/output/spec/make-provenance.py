#!/usr/bin/env python3
"""Regenerate ../provenance-manifest.json for the incremental run (reads logs)."""
import json, hashlib, glob, os
os.chdir('/work/current/.specular-output')
def sha(p): return hashlib.sha256(open(p,'rb').read()).hexdigest()
camp = [json.loads(l) for l in open('spec/output/mc/campaigns.ndjson')]
tv = [json.loads(l) for l in open('spec/output/trace-validation/command-results.ndjson')]
final_tv = [d for d in tv if d['round'] == 'r8']
m = {
 "schema_version": 1, "case_id": "case-002", "run_id": "incr-bb5d64a185fa",
 "purpose": "blind_incremental_update_verification",
 "source": {"artifact": "artifact/ (git, commits baseline 1414ebf -> update 2efbdfc, unmodified)",
            "old_commit": "1414ebfb1d16fd81abc38550a96950d919ecf805", "new_commit": "2efbdfc3754df193bce05b9792297c813377cdaf",
            "changed_files": {p: sha('/work/'+p) for p in [
              "old-source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java",
              "old-source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java",
              "new-source/zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java",
              "new-source/zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java",
              "new-source/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java"]},
            "history_or_external_behavioral_research_used": False},
 "previous_suite": "/work/previous/.specular-output (read-only)",
 "inputs": {p: sha('/work/'+p) for p in ["model-scope.md","case.json","input-manifest.json","final-schema.json","lib/tla2tools.jar","lib/CommunityModules-deps.jar"]},
 "decision": "MODEL_CHANGE_REQUIRED",
 "harness": {"run": "harness/run.sh", "patch": "harness/patches/instrumentation.patch", "patch_sha256": sha('harness/patches/instrumentation.patch'),
             "work_source": "harness/work-source (patched copy of artifact)", "build_log": "spec/output/build-instrumented.log",
             "run_logs": ["spec/output/harness-run-2.log", "spec/output/harness-summary.log"],
             "environment": "OpenJDK 21.0.13, Maven 3.6.3, deps from Maven Central into /work/.cache/m2"},
 "traces": [{"path": p, "records": sum(1 for _ in open(p)), "sha256": sha(p),
             "final_validation": next((d['log'] for d in final_tv if d['trace'] == p), None),
             "passed": next((d['no_error'] == 1 for d in final_tv if d['trace'] == p), False)} for p in sorted(glob.glob('traces/*.ndjson'))],
 "archived_traces": sorted(glob.glob('traces/archived-v0/*.ndjson')),
 "trace_validation_rounds": "spec/output/trace-validation/command-results.ndjson",
 "model_checking_campaigns": camp,
 "reproductions": {"MC-1": "repro/test_bug1_newleader_ack_before_fsync.sh (repro/logs/bug1-summary.log)",
                   "CR-2": "repro/test_bug2_learner_initial_state_leak.sh (repro/logs/bug2-summary.log)",
                   "CR-3": "repro/test_bug3_proposal_ack_before_newleader_ack.sh (repro/logs/bug3-summary.log)"},
 "limits": "TLC runs are bounded (30 min, finite constants); runs that stopped on the time budget are LIMITED_COVERAGE, not proofs."
}
json.dump(m, open('provenance-manifest.json','w'), indent=1)
print("ok", len(camp), "campaigns")
