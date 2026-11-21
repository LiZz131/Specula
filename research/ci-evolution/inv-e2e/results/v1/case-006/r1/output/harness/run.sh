#!/usr/bin/env bash
# Rebased (V1) one-command harness: export+instrument the target revision,
# build in the GOPATH overlay, run every scenario, write fresh NDJSON traces.
#   TARGET_REV (default update commit); TRACE_DIR (default ../traces);
#   LOG_PATH (default ../spec/output/harness-run.log)
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
TRACE_DIR="${TRACE_DIR:-$OUTPUT_ROOT/traces}"
LOG_PATH="${LOG_PATH:-$OUTPUT_ROOT/spec/output/harness-run.log}"
GO_CACHE="$OUTPUT_ROOT/build/go-cache"
mkdir -p "$TRACE_DIR" "$GO_CACHE" "$(dirname "$LOG_PATH")"
: > "$LOG_PATH"

APPLY_OUT="$("$HARNESS_DIR/apply.sh")"
echo "$APPLY_OUT" | tee -a "$LOG_PATH"
TREE="${APPLY_OUT##*tree=}"; TREE="${TREE%% *}"
GOPATH_ROOT="$("$HARNESS_DIR/gopath.sh" "$TREE")"
echo "gopath=$GOPATH_ROOT go=$(go version)" | tee -a "$LOG_PATH"

gotest() {
  timeout 10m env GO111MODULE=off GOPATH="$GOPATH_ROOT" GOCACHE="$GO_CACHE" GOFLAGS= \
    go test -vet=off github.com/coreos/etcd/raft -count=1 -v "$@"
}

# name:test pairs; prior scenarios first, update scenarios after.
SCENARIOS="quorum_read:TestSpeculaTraceQuorumRead quorum_loss:TestSpeculaTraceQuorumLoss read_reuse:TestSpeculaTraceReadReuse stale_read:TestSpeculaTraceStaleRead read_stepdown:TestSpeculaTraceReadStepDown"
for pair in $SCENARIOS; do
  name="${pair%%:*}"; test="${pair##*:}"
  out="$TRACE_DIR/$name.ndjson"
  rm -f "$out"
  echo "=== scenario $name ($test) -> $out" | tee -a "$LOG_PATH"
  SPECULA_TRACE_PATH="$out" gotest -run "^${test}\$" 2>&1 | tee -a "$LOG_PATH"
  test -s "$out"
  echo "trace_records=$(wc -l < "$out") sha256=$(sha256sum "$out" | cut -d' ' -f1) trace=$out" | tee -a "$LOG_PATH"
done
