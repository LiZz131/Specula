#!/usr/bin/env bash
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
TARGET_TREE="${TARGET_TREE:-/work/work-source}"
TRACE_PATH="${SPECULA_TRACE_PATH:-$OUTPUT_ROOT/traces/quorum_read.ndjson}"
QUORUM_TRACE_PATH="$OUTPUT_ROOT/traces/quorum_loss.ndjson"
GOPATH_ROOT="$OUTPUT_ROOT/build/gopath"
GO_CACHE="$OUTPUT_ROOT/build/go-cache"
LOG_PATH="$OUTPUT_ROOT/spec/output/harness-run.log"

TARGET_TREE="$TARGET_TREE" "$HARNESS_DIR/apply.sh"
test "$(readlink -f "$GOPATH_ROOT/src/github.com/coreos/etcd/raft")" = \
     "$(readlink -f "$TARGET_TREE")"
mkdir -p "$(dirname "$TRACE_PATH")" "$GO_CACHE" "$(dirname "$LOG_PATH")"

set -o pipefail
timeout 10m env \
    GO111MODULE=off \
    GOPATH="$GOPATH_ROOT" \
    GOCACHE="$GO_CACHE" \
    SPECULA_TRACE_PATH="$TRACE_PATH" \
    go test -vet=off github.com/coreos/etcd/raft \
      -run '^TestSpeculaTraceQuorumRead$' -count=1 -v 2>&1 | tee "$LOG_PATH"

test -s "$TRACE_PATH"
echo "trace_records=$(wc -l < "$TRACE_PATH") trace=$TRACE_PATH"

timeout 10m env \
    GO111MODULE=off \
    GOPATH="$GOPATH_ROOT" \
    GOCACHE="$GO_CACHE" \
    SPECULA_TRACE_PATH="$QUORUM_TRACE_PATH" \
    go test -vet=off github.com/coreos/etcd/raft \
      -run '^TestSpeculaTraceQuorumLoss$' -count=1 -v 2>&1 | tee -a "$LOG_PATH"

test -s "$QUORUM_TRACE_PATH"
echo "trace_records=$(wc -l < "$QUORUM_TRACE_PATH") trace=$QUORUM_TRACE_PATH"
