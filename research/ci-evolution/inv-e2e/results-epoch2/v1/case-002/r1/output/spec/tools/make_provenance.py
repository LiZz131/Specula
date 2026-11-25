#!/usr/bin/env python3
import json, hashlib, os, glob, subprocess
OUT='/work/current/.specula-output'
def sha(p): return hashlib.sha256(open(p,'rb').read()).hexdigest()
def git(*a): return subprocess.run(['git','-C',OUT+'/artifact',*a],capture_output=True,text=True).stdout.strip()
prior=json.load(open('/work/previous/.specula-output/provenance-manifest.json'))
inv=json.load(open(OUT+'/spec/output/incremental/trace-inventory.json')) if os.path.exists(OUT+'/spec/output/incremental/trace-inventory.json') else []
m={
 "schema_version":1,"case_id":"case-002","run":"V1 incremental (source revision update)",
 "purpose":"blind_source_derived_incremental_verification",
 "history_or_external_behavioral_research_used":False,
 "inputs":{
   "old_source":{p.replace('/work/',''):sha(p) for p in glob.glob('/work/old-source/**/*.java',recursive=True)},
   "new_source":{p.replace('/work/',''):sha(p) for p in glob.glob('/work/new-source/**/*.java',recursive=True)},
   "artifact":{"path":"artifact","commits":git('log','--format=%H %s').splitlines(),"status_clean":git('status','--porcelain')==''},
   "previous_suite":{"path":"/work/previous/.specula-output","base.tla":sha('/work/previous/.specula-output/spec/base.tla'),"Trace.tla":sha('/work/previous/.specula-output/spec/Trace.tla'),"instrumentation.patch":sha('/work/previous/.specula-output/harness/patches/instrumentation.patch')},
   "case.json":sha('/work/case.json'),"model-scope.md":sha('/work/model-scope.md'),"input-manifest.json":sha('/work/input-manifest.json'),"final-schema.json":sha('/work/final-schema.json'),
   "tla2tools.jar":sha('/work/lib/tla2tools.jar'),"CommunityModules-deps.jar":sha('/work/lib/CommunityModules-deps.jar')},
 "environment":{"jdk":"OpenJDK 11 (/usr/lib/jvm/java-11-openjdk-amd64) for build/tests; JDK 21 for TLC","maven_repo":"/work/.cache/m2 (Maven Central, ordinary build dependencies only)","tlc_states":"/dev/shm/specula-e2e-case-002/<run-id> (removed after each run)"},
 "harness":{"patch":"harness/patches/instrumentation.patch","patch_sha256":sha(OUT+'/harness/patches/instrumentation.patch'),
   "rebase":"V0 patch applied to commit update; only the BroadcastReady hunk (zk.startup -> zk.startServing) needed re-anchoring",
   "patch_dry_run_log":"spec/output/incremental/harness/patch-dry-run.log","run_command":"timeout 7200s harness/run.sh (SKIP_PREPARE=1, SCENARIOS=... optional)",
   "old_control_tree":"harness/old-control-source (git archive of commit baseline + harness-only tests, no instrumentation)"},
 "spec":{f:sha(OUT+'/spec/'+f) for f in ['base.tla','MC.tla','Update.tla','UpdateProps.tla','Trace.tla','TraceUpdateEvidence.tla','HuntU1.tla','MCFiltered.tla','UpdateFiltered.tla','MC.cfg','base.cfg','Trace.cfg']},
 "commands":{"trace_validation_gate":"spec/run-incremental-validation.sh","campaign":"spec/run-incremental-campaign.sh","followups":"spec/run-incremental-followups.sh","single_run":"spec/run-tlc.sh ID MODULE CFG TIMEOUT [TLC args]","ledger":"spec/output/incremental/runs/ledger.ndjson"},
 "limits":["TLC runs bounded by -Dtlc2.TLC.stopAfter (600-1800 s) plus an outer timeout; finite constants (3 servers, 1 txn, epochs 2-3, crash 1-2, drop 0-1, snapshot 0-1); no run exhausted its state space except where a violation stopped it","Trace model is an observation-projection validator inherited from V0 (it does not replay base actions); V1 events are validated by explicit post-state predicates","Fault-injected U1 reproduction traces are reproduction evidence only"],
 "traces":[{k:e[k] for k in ('path','sha256','records','group')} for e in inv],
 "v0_prior":prior,
}
json.dump(m,open(OUT+'/provenance-manifest.json','w'),indent=1)
print("ok")
