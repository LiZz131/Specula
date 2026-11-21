#!/usr/bin/env bash
# One-command fresh trace collection on the updated implementation.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
B="$OUTPUT_ROOT/build"
TARGET_TREE="${TARGET_TREE:-$B/work-source}"
GOPATH_ROOT="$B/gopath"
GO_CACHE="$B/go-cache"
LOG_PATH="$OUTPUT_ROOT/spec/output/harness-run.log"
TRACES="$OUTPUT_ROOT/traces"

"$HARNESS_DIR/setup-build.sh"
TARGET_TREE="$TARGET_TREE" "$HARNESS_DIR/apply.sh"
test "$(readlink -f "$GOPATH_ROOT/src/github.com/coreos/etcd/raft")" = "$(readlink -f "$TARGET_TREE")"
mkdir -p "$TRACES" "$GO_CACHE" "$(dirname "$LOG_PATH")"
: > "$LOG_PATH"
echo "source HEAD $(git -C "$TARGET_TREE" rev-parse HEAD) + harness/patches/instrumentation.patch" | tee -a "$LOG_PATH"

# scenario test name -> trace file
SCENARIOS="TestSpeculaTraceQuorumRead:quorum_read
TestSpeculaTraceQuorumLoss:quorum_loss
TestSpeculaTraceReadReuse:read_reuse
TestSpeculaTraceForwardedRead:forwarded_read
TestSpeculaTraceStepDownWithPending:stepdown_pending
TestSpeculaTraceStaleAckReuse:stale_ack_reuse"

for pair in $SCENARIOS; do
    test_name="${pair%%:*}"; trace="${pair##*:}"
    out="$TRACES/$trace.ndjson"
    rm -f "$out"
    (cd /tmp && timeout 10m env GO111MODULE=off GOPATH="$GOPATH_ROOT" GOCACHE="$GO_CACHE" \
        SPECULA_TRACE_PATH="$out" \
        go test -vet=off github.com/coreos/etcd/raft -run "^${test_name}\$" -count=1 -v) 2>&1 \
        | tee -a "$LOG_PATH"
    test -s "$out"
    echo "trace_records=$(wc -l < "$out") trace=$out sha256=$(sha256sum "$out" | cut -d' ' -f1)" | tee -a "$LOG_PATH"
done
