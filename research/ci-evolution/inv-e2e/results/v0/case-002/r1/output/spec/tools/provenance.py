#!/usr/bin/env python3
import json, hashlib, glob, os, subprocess
C='/work/current/.specula-output'
def sha(p):
    return hashlib.sha256(open(p,'rb').read()).hexdigest()
def git(*a):
    return subprocess.run(['git','-C',f'{C}/artifact',*a],capture_output=True,text=True).stdout.strip()
rel='zookeeper-server/src/main/java/org/apache/zookeeper/server'
m={
 'schema_version':1,'case_id':'case-002','purpose':'blind_source_derived_incremental_verification',
 'decision':'MODEL_CHANGE_REQUIRED (reported as MODEL_UPDATED)',
 'inputs':{
   'model_scope_md_sha256':sha('/work/model-scope.md'),'case_json_sha256':sha('/work/case.json'),
   'input_manifest_json_sha256':sha('/work/input-manifest.json'),
   'tla2tools_jar_sha256':sha('/work/lib/tla2tools.jar'),'community_modules_jar_sha256':sha('/work/lib/CommunityModules-deps.jar'),
   'previous_suite':'/work/previous/.specula-output (read-only)'},
 'source':{
   'artifact_head':git('rev-parse','HEAD'),'artifact_commits':git('log','--format=%H %s').splitlines(),
   'artifact_worktree_clean':git('status','--porcelain')=='',
   'old_changed_files':{f:sha(f'/work/old-source/{f}') for f in [f'{rel}/ZooKeeperServer.java',f'{rel}/quorum/Learner.java']},
   'new_changed_files':{f:sha(f'/work/new-source/{f}') for f in [f'{rel}/ZooKeeperServer.java',f'{rel}/quorum/Learner.java','zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java']},
   'history_or_external_research_used':False},
 'harness':{'run_command':'timeout 6000s /work/current/.specula-output/harness/run.sh',
   'patch':'harness/patches/instrumentation.patch','patch_sha256':sha(f'{C}/harness/patches/instrumentation.patch'),
   'patch_used_for_traces':'harness/patches/instrumentation.patch.used-for-traces','patch_used_for_traces_sha256':sha(f'{C}/harness/patches/instrumentation.patch.used-for-traces'),
   'results':'spec/output/harness/harness-results.ndjson','java':'OpenJDK 21 (/usr/lib/jvm/java-21-openjdk-amd64)'},
 'traces':[{'path':os.path.relpath(p,C),'records':sum(1 for _ in open(p)),'sha256':sha(p)} for p in sorted(glob.glob(f'{C}/traces/*.ndjson'))],
 'archived_v0_traces':[{'path':os.path.relpath(p,C),'sha256':sha(p),'disposition':'superseded'} for p in sorted(glob.glob(f'{C}/traces/archived-v0/*.ndjson'))],
 'spec_files':{os.path.relpath(p,C):sha(p) for p in sorted(glob.glob(f'{C}/spec/*.tla')+glob.glob(f'{C}/spec/*.cfg'))},
 'tlc_ledger':'spec/output/command-results.ndjson','mc_summary':'spec/output/mc-summary.md',
 'validation_summary':'spec/output/validation-summary.md',
 'reproduction':{'scripts':['repro/run-repro.sh','repro/run-repro-reelection.sh','repro/run-repro-capture.sh','repro/run-repro-npe-v2.sh'],'ledger':'repro/repro-results.ndjson'},
 'limits':['JDK 21 only (as V0).','TLC bounds: 3 servers, 1 txn, MaxEpoch 2-3, bounded crash/drop/snapshot; BFS runs budget-stopped with non-empty queues (LIMITED_COVERAGE).',
           'Deep U-LOSS/U-EPOCH paths found only with guidance constraints (restrictions of full MCNext).',
           '`specula` CLI (ci-result, findings registry) not installed: final reports generated manually.'],
}
json.dump(m,open(f'{C}/provenance-manifest.json','w'),indent=1)
print('ok', len(m['traces']))
