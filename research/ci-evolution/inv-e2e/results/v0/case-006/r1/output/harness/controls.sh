#!/usr/bin/env bash
# Old/new controls for the update probes (harness/src/specula_update_probe_test.go),
# the S6b stale-read reachability test (harness/src/specula_s6_stale_read_test.go;
# expected: FAIL on update = stale ReadState observed, PASS on baseline)
# and for the updated upstream test TestRaftFreesReadOnlyMem. Uninstrumented
# copies of each neutral commit are materialized from the artifact repository.
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
B="$OUTPUT_ROOT/build"; LOG="$OUTPUT_ROOT/spec/output/controls.log"
"$HARNESS_DIR/prepare_deps.sh" >/dev/null
DEPS="$B/gopath/src"; : > "$LOG"
for rev in update:c780d355cfeae6ee6be52c50c1f0bd7d30c6657a baseline:7289d1c5e049933b90a9692bbf508714bee02fce; do
    name="${rev%%:*}"; sha="${rev##*:}"; W="$B/worktrees/probe-$name"; G="$B/gopath-probe-$name"
    rm -rf "$W" "$G"; mkdir -p "$W" "$G/src/github.com/coreos/etcd"
    git -C "$OUTPUT_ROOT/artifact" archive "$sha" | tar -x -C "$W"
    cp "$HARNESS_DIR/src/specula_update_probe_test.go" "$HARNESS_DIR/src/specula_s6_stale_read_test.go" "$W/"
    ln -sfn "$DEPS/golang.org" "$G/src/golang.org"; ln -sfn "$DEPS/github.com/golang" "$G/src/github.com/golang"
    ln -sfn "$DEPS/github.com/coreos/etcd/pkg" "$G/src/github.com/coreos/etcd/pkg"; ln -sfn "$W" "$G/src/github.com/coreos/etcd/raft"
    echo "=== $name $sha" | tee -a "$LOG"
    timeout 10m env GO111MODULE=off GOPATH="$G" GOCACHE="$B/go-cache" go test -vet=off \
        github.com/coreos/etcd/raft -run '^TestSpecula(Probe|S6)' -count=1 -v 2>&1 | grep -E "specula_update_probe|specula_s6|^(--- |ok|FAIL|panic)" | tee -a "$LOG"
done
# Updated upstream test on the baseline source (expected to fail: stale entry).
W="$B/worktrees/baseline-newtest"; G="$B/gopath-ctl-baseline-newtest"; rm -rf "$W" "$G"; mkdir -p "$W" "$G/src/github.com/coreos/etcd"
git -C "$OUTPUT_ROOT/artifact" archive 7289d1c5e049933b90a9692bbf508714bee02fce | tar -x -C "$W"
git -C "$OUTPUT_ROOT/artifact" show c780d355cfeae6ee6be52c50c1f0bd7d30c6657a:raft_test.go > "$W/raft_test.go"
ln -sfn "$DEPS/golang.org" "$G/src/golang.org"; ln -sfn "$DEPS/github.com/golang" "$G/src/github.com/golang"
ln -sfn "$DEPS/github.com/coreos/etcd/pkg" "$G/src/github.com/coreos/etcd/pkg"; ln -sfn "$W" "$G/src/github.com/coreos/etcd/raft"
echo "=== baseline source + updated raft_test.go: TestRaftFreesReadOnlyMem" | tee -a "$LOG"
timeout 10m env GO111MODULE=off GOPATH="$G" GOCACHE="$B/go-cache" go test -vet=off \
    github.com/coreos/etcd/raft -run '^TestRaftFreesReadOnlyMem$' -count=1 -v 2>&1 | grep -E "raft_test.go|^(--- |ok|FAIL)" | tee -a "$LOG"
