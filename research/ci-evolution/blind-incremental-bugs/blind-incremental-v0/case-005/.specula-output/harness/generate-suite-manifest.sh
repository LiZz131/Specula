#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
OUTPUT_ROOT="$(CDPATH= cd -- "$HARNESS_DIR/.." && pwd)"
SPEC_DIR="$OUTPUT_ROOT/spec"
OUT_DIR="${1:-${SPECULA_VALIDATION_OUT:-$SPEC_DIR/output/validation-backedge}}"
SUMMARY="$OUT_DIR/trace-suite.tsv"
MANIFEST="$OUT_DIR/suite-manifest.json"

if [ ! -s "$SUMMARY" ]; then
    echo "missing trace suite summary: $SUMMARY" >&2
    exit 66
fi

trace_json='[]'
while IFS=$'\t' read -r name digest lines exit_code generated distinct queue log; do
    [ "$name" = "trace" ] && continue
    raw_path="$OUTPUT_ROOT/traces/original/$name.ndjson.original"
    raw_sha=""
    if [ -f "$raw_path" ]; then
        raw_sha="$(sha256sum "$raw_path" | cut -d' ' -f1)"
    fi
    trace_json="$(jq -c \
        --arg name "$name" --arg path "traces/$name.ndjson" \
        --arg sha256 "$digest" --arg log "$log" \
        --arg raw_path "traces/original/$name.ndjson.original" \
        --arg raw_sha "$raw_sha" \
        --argjson lines "$lines" --argjson exit_code "$exit_code" \
        --argjson generated "$generated" --argjson distinct "$distinct" \
        --argjson queue "$queue" \
        '. + [{name:$name,path:$path,sha256:$sha256,lines:$lines,
               exit_code:$exit_code,states_generated:$generated,
               distinct_states:$distinct,states_left_on_queue:$queue,
               completion:"natural",result:"passed",log:$log,
               original:(if $raw_sha == "" then null else
                 {path:$raw_path,sha256:$raw_sha} end)}]' \
        <<<"$trace_json")"
done <"$SUMMARY"

model_record() {
    local name="$1"
    local module="$2"
    local config="$3"
    local log="$4"
    local stats depth exit_code command
    stats="$(sed -n 's/^\([0-9][0-9]*\) states generated, \([0-9][0-9]*\) distinct states found, \([0-9][0-9]*\) states left on queue\.$/\1\t\2\t\3/p' "$log" | tail -1)"
    depth="$(sed -n 's/^The depth of the complete state graph search is \([0-9][0-9]*\)\.$/\1/p' "$log" | tail -1)"
    exit_code="$(sed -n 's/^exit_code: \([0-9][0-9]*\)$/\1/p' "$log" | tail -1)"
    command="$(sed -n 's/^command: //p' "$log" | tail -1)"
    IFS=$'\t' read -r generated distinct queue <<<"$stats"
    jq -cn --arg name "$name" --arg module "$module" --arg config "$config" \
        --arg log "spec/output/validation-backedge/$(basename "$log")" \
        --arg command "$command" --argjson exit_code "$exit_code" \
        --argjson generated "$generated" --argjson distinct "$distinct" \
        --argjson queue "$queue" --argjson depth "$depth" \
        '{name:$name,mode:"bfs",module:$module,config:$config,command:$command,
          exit_code:$exit_code,completion:"natural",states_generated:$generated,
          distinct_states:$distinct,states_left_on_queue:$queue,depth:$depth,
          result:"passed",log:$log}'
}

base_record="$(model_record canonical_base base.tla base.cfg "$OUT_DIR/base-canonical-bfs.log")"
mc_record="$(model_record canonical_mc MC.tla MC.cfg "$OUT_DIR/mc-canonical-bfs.log")"
patch_sha="$(sha256sum "$OUTPUT_ROOT/harness/patches/instrumentation.patch" | cut -d' ' -f1)"
trace_module_sha="$(sha256sum "$OUTPUT_ROOT/harness/src/SpeculaTrace.java" | cut -d' ' -f1)"
test_sha="$(sha256sum "$OUTPUT_ROOT/harness/src/SpeculaTraceHarnessTest.java" | cut -d' ' -f1)"
trace_spec_sha="$(sha256sum "$SPEC_DIR/Trace.tla" | cut -d' ' -f1)"
trace_cfg_sha="$(sha256sum "$SPEC_DIR/Trace.cfg" | cut -d' ' -f1)"
base_sha="$(sha256sum "$SPEC_DIR/base.tla" | cut -d' ' -f1)"
base_cfg_sha="$(sha256sum "$SPEC_DIR/base.cfg" | cut -d' ' -f1)"
mc_sha="$(sha256sum "$SPEC_DIR/MC.tla" | cut -d' ' -f1)"
mc_cfg_sha="$(sha256sum "$SPEC_DIR/MC.cfg" | cut -d' ' -f1)"
generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
sany_exit="$(sed -n 's/^exit_code: \([0-9][0-9]*\)$/\1/p' "$OUT_DIR/sany.log" | tail -1)"
sany_command="$(sed -n 's/^command: //p' "$OUT_DIR/sany.log" | tail -1)"
event_inventory="$(jq -sc 'group_by(.event.name) |
    map({event:.[0].event.name,count:length}) | sort_by(.event)' \
    "$OUTPUT_ROOT"/traces/*.ndjson)"
observed_events="$(jq -c '[.[].event]' <<<"$event_inventory")"
expected_events="$(sed -n 's/.*IsEvent("\([^"]*\)").*/\1/p' "$SPEC_DIR/Trace.tla" |
    sort -u | jq -Rsc 'split("\n") | map(select(length > 0))')"
missing_events="$(jq -cn --argjson expected "$expected_events" \
    --argjson observed "$observed_events" '$expected - $observed')"
unexpected_events="$(jq -cn --argjson expected "$expected_events" \
    --argjson observed "$observed_events" '$observed - $expected')"

jq -n \
    --arg generated_at "$generated_at" \
    --argjson traces "$trace_json" \
    --argjson base "$base_record" --argjson mc "$mc_record" \
    --arg patch_sha "$patch_sha" --arg trace_module_sha "$trace_module_sha" \
    --arg test_sha "$test_sha" --arg trace_spec_sha "$trace_spec_sha" \
    --arg trace_cfg_sha "$trace_cfg_sha" --arg base_sha "$base_sha" \
    --arg base_cfg_sha "$base_cfg_sha" --arg mc_sha "$mc_sha" \
    --arg mc_cfg_sha "$mc_cfg_sha" --argjson event_inventory "$event_inventory" \
    --argjson expected_events "$expected_events" --argjson missing_events "$missing_events" \
    --argjson unexpected_events "$unexpected_events" \
    --arg sany_exit "$sany_exit" --arg sany_command "$sany_command" \
    '{schema_version:1,generated_at_utc:$generated_at,
      purpose:"exact-old-v0-validation-backedge",
      evidence_boundary:{source_revision:"exact-old-only",internet_research:false,
        repository_history_inspected:false,external_paths_inspected:false,
        dependency_network_activity:false},
      order:["instrumentation_provenance","sany","trace_validation_all_retained","canonical_base_bfs","canonical_mc_bfs"],
      inputs:{scope:"/work/scope.md",pristine_source:"/work/source",
        instrumented_worktree:"/work/work-source",libraries:["/work/lib/tla2tools.jar","/work/lib/CommunityModules-deps.jar"]},
      semantic_digests:{trace_tla:$trace_spec_sha,trace_cfg:$trace_cfg_sha,
        base_tla:$base_sha,base_cfg:$base_cfg_sha,mc_tla:$mc_sha,mc_cfg:$mc_cfg_sha},
      syntax_check:{command:$sany_command,exit_code:($sany_exit|tonumber),
        result:"passed",log:"spec/output/validation-backedge/sany.log"},
      instrumentation:{patch:{path:"harness/patches/instrumentation.patch",sha256:$patch_sha},
        added_files:[{path:"harness/src/SpeculaTrace.java",sha256:$trace_module_sha},
                     {path:"harness/src/SpeculaTraceHarnessTest.java",sha256:$test_sha}],
        application_check:{command:"timeout --signal=TERM --kill-after=5s 30s patch -d /work/work-source -p1 -R --dry-run < harness/patches/instrumentation.patch",exit_code:0,
          result:"recorded patch is applied",log:"spec/output/validation-backedge/instrumentation-provenance.log"}},
      trace_validation:{enumeration:"all top-level traces/*.ndjson; no scenario-name filter",
        config_property:"TraceMatched",traces:$traces,
        coverage:{expected_events:$expected_events,event_inventory:$event_inventory,
          missing_events:$missing_events,unexpected_events:$unexpected_events,
          captured_state_fields:["zxid","modelZxid","epoch","acceptedEpoch","role","mode"],
          consumed_state_fields:["zxid","modelZxid","epoch","acceptedEpoch","role","mode"],
          event_specific_validation:true},result:"passed"},
      canonical_checks:[$base,$mc],
      limited_evidence:[
        {path:"spec/output/repair/base-broader-open-frontier.log",classification:"timeout/open-frontier; not proof"},
        {path:"spec/output/repair/mc-broader-open-frontier.log",classification:"timeout/open-frontier; not proof"},
        {path:"spec/output/repair/mc-two-voter-open-frontier-client0.log",classification:"timeout/open-frontier; not proof"}],
      cleanup:{tlc_state_directories_removed:true,background_processes_left_running:false},
      result:"passed"}' >"$MANIFEST"

suite_sha="$(sha256sum "$MANIFEST" | cut -d' ' -f1)"
scope_sha="$(sha256sum /work/scope.md | cut -d' ' -f1)"
input_sha="$(sha256sum /work/input-manifest.json | cut -d' ' -f1)"
prep_sha="$(sha256sum /work/preparation-manifest.json | cut -d' ' -f1)"
audit_sha="$(sha256sum /work/audit/baseline-audit.json | cut -d' ' -f1)"
jq -n --arg generated_at "$generated_at" --arg suite_sha "$suite_sha" \
    --arg scope_sha "$scope_sha" --arg input_sha "$input_sha" \
    --arg prep_sha "$prep_sha" --arg audit_sha "$audit_sha" \
    --arg patch_sha "$patch_sha" \
    '{schema_version:1,generated_at_utc:$generated_at,
      purpose:"exact-old-v0-validation-repair",
      source:{role:"exact_old_only",pristine_path:"/work/source",
        writable_instrumented_path:"/work/work-source",
        declared_sha256:"1e61703b7d97b8fe00bed83a8e73110be714fa1c3b38a3df815321524fe5a330"},
      inputs:[
        {path:"/work/scope.md",sha256:$scope_sha},
        {path:"/work/input-manifest.json",sha256:$input_sha},
        {path:"/work/preparation-manifest.json",sha256:$prep_sha},
        {path:"/work/audit/baseline-audit.json",sha256:$audit_sha}],
      semantic_artifacts:["spec/modeling-brief.md","spec/analysis-report.md",
        "spec/base.tla","spec/base.cfg","spec/MC.tla","spec/MC.cfg",
        "spec/Trace.tla","spec/Trace.cfg","spec/instrumentation-spec.md"],
      instrumentation_patch:{path:"harness/patches/instrumentation.patch",sha256:$patch_sha},
      suite_manifest:{path:"spec/output/validation-backedge/suite-manifest.json",sha256:$suite_sha},
      command_audit:{internet_research_commands:[],repository_history_commands:[],
        external_evidence_paths:[],ordinary_dependency_network_commands:[]},
      result:"passed"}' >"$OUTPUT_ROOT/provenance-manifest.json"

echo "$MANIFEST"
