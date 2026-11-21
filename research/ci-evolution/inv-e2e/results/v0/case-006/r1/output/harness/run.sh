#!/usr/bin/env bash
# One command: prepare deps, apply instrumentation to the updated revision,
# build, run every retained scenario, and write fresh NDJSON traces.
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
REV="${REV:-c780d355cfeae6ee6be52c50c1f0bd7d30c6657a}"
TARGET_TREE="$OUTPUT_ROOT/build/worktrees/instr-$REV"
GOPATH_ROOT="$OUTPUT_ROOT/build/gopath-instr-$REV"
GO_CACHE="$OUTPUT_ROOT/build/go-cache"
TRACE_DIR="$OUTPUT_ROOT/traces"
LOG_PATH="$OUTPUT_ROOT/spec/output/harness-run.log"

"$HARNESS_DIR/prepare_deps.sh"
REV="$REV" TARGET_TREE="$TARGET_TREE" "$HARNESS_DIR/apply.sh"
DEPS="$OUTPUT_ROOT/build/gopath/src"
rm -rf "$GOPATH_ROOT"; mkdir -p "$GOPATH_ROOT/src/github.com/coreos/etcd"
ln -sfn "$DEPS/golang.org" "$GOPATH_ROOT/src/golang.org"
ln -sfn "$DEPS/github.com/golang" "$GOPATH_ROOT/src/github.com/golang"
ln -sfn "$DEPS/github.com/coreos/etcd/pkg" "$GOPATH_ROOT/src/github.com/coreos/etcd/pkg"
ln -sfn "$TARGET_TREE" "$GOPATH_ROOT/src/github.com/coreos/etcd/raft"
mkdir -p "$TRACE_DIR" "$GO_CACHE" "$(dirname "$LOG_PATH")"
: > "$LOG_PATH"
echo "source_rev=$REV target=$TARGET_TREE go=$(go version)" | tee -a "$LOG_PATH"

# scenario-name:test-name
SCENARIOS="quorum_read:TestSpeculaTraceQuorumRead
quorum_loss:TestSpeculaTraceQuorumLoss
read_reuse:TestSpeculaTraceReadReuse
forwarded_read:TestSpeculaTraceForwardedRead
delayed_ack:TestSpeculaTraceDelayedAck
step_down_reads:TestSpeculaTraceStepDownClearsReads
higher_term_reads:TestSpeculaTraceHigherTermClearsReads
stale_read_reuse:TestSpeculaTraceStaleReadReuse"
for entry in $SCENARIOS; do
    name="${entry%%:*}"; test_name="${entry##*:}"
    trace="$TRACE_DIR/$name.ndjson"; rm -f "$trace"
    echo "=== scenario $name ($test_name)" | tee -a "$LOG_PATH"
    timeout 10m env GO111MODULE=off GOPATH="$GOPATH_ROOT" GOCACHE="$GO_CACHE" \
        SPECULA_TRACE_PATH="$trace" \
        go test -vet=off github.com/coreos/etcd/raft \
        -run "^${test_name}\$" -count=1 -v 2>&1 | tee -a "$LOG_PATH"
    test -s "$trace"
    echo "trace_records=$(wc -l < "$trace") sha256=$(sha256sum "$trace" | cut -d' ' -f1) trace=$trace" | tee -a "$LOG_PATH"
done
