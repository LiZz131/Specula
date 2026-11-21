#!/usr/bin/env bash
# Run the reproduction/control tests on the updated tree (instrumented copy)
# and on the baseline tree. Uses only bounded `go test` invocations.
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
B="$OUTPUT_ROOT/build"
LOG="$OUTPUT_ROOT/spec/output/repro.log"
"$HARNESS_DIR/setup-build.sh" > /dev/null
: > "$LOG"
for side in update:gopath:work-source baseline:gopath-old:old-work-source; do
    name="${side%%:*}"; rest="${side#*:}"; gp="${rest%%:*}"; tree="${rest#*:}"
    cp "$HARNESS_DIR/src/specula_repro_test.go" "$B/$tree/specula_repro_test.go"
    echo "=== $name tree HEAD $(git -C "$B/$tree" rev-parse HEAD)" | tee -a "$LOG"
    (cd /tmp && timeout 10m env GO111MODULE=off GOPATH="$B/$gp" GOCACHE="$B/go-cache" \
        go test -vet=off github.com/coreos/etcd/raft -run '^TestSpeculaRepro' -count=1 -v 2>&1) \
        | grep -vE "^raft20|INFO:" | tee -a "$LOG"
    rm -f "$B/$tree/specula_repro_test.go"
done
