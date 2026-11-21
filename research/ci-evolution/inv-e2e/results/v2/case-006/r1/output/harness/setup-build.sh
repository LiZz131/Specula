#!/usr/bin/env bash
# Prepare the writable instrumented copy of the updated source and the
# GOPATH-style dependency overlay (ordinary build dependencies only).
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
B="$OUTPUT_ROOT/build"
ARTIFACT="${ARTIFACT:-$OUTPUT_ROOT/artifact}"
UPDATE_COMMIT="c780d355cfeae6ee6be52c50c1f0bd7d30c6657a"
BASELINE_COMMIT="7289d1c5e049933b90a9692bbf508714bee02fce"
GP="$B/gopath"; GPO="$B/gopath-old"

test "$(git -C "$ARTIFACT" rev-parse HEAD)" = "$UPDATE_COMMIT"
if [ ! -d "$B/work-source/.git" ]; then
    cp -a "$ARTIFACT" "$B/work-source"
fi
if [ ! -d "$B/old-work-source/.git" ]; then
    cp -a "$ARTIFACT" "$B/old-work-source"
    git -C "$B/old-work-source" checkout -q "$BASELINE_COMMIT"
fi
if [ ! -d "$GP/src/github.com/golang/protobuf" ]; then
    mkdir -p "$B/modfetch"
    printf 'module speculafetch\ngo 1.20\n' > "$B/modfetch/go.mod"
    (cd "$B/modfetch" && timeout 5m env GOMODCACHE="$B/gomodcache" GOFLAGS=-modcacherw \
        GOSUMDB=off go mod download github.com/golang/protobuf@v1.3.5 golang.org/x/net@v0.7.0)
    mkdir -p "$GP/src/github.com/golang" "$GP/src/golang.org/x"
    cp -r "$B/gomodcache/github.com/golang/protobuf@v1.3.5" "$GP/src/github.com/golang/protobuf"
    cp -r "$B/gomodcache/golang.org/x/net@v0.7.0" "$GP/src/golang.org/x/net"
fi
mkdir -p "$GP/src/github.com/coreos/etcd/pkg/testutil"
cp "$HARNESS_DIR/src/testutil_shim.go" "$GP/src/github.com/coreos/etcd/pkg/testutil/testutil.go"
ln -sfn "$B/work-source" "$GP/src/github.com/coreos/etcd/raft"
mkdir -p "$GPO/src/github.com/coreos/etcd" "$GPO/src/github.com" "$GPO/src/golang.org"
ln -sfn "$GP/src/github.com/golang" "$GPO/src/github.com/golang"
ln -sfn "$GP/src/golang.org/x" "$GPO/src/golang.org/x"
ln -sfn "$GP/src/github.com/coreos/etcd/pkg" "$GPO/src/github.com/coreos/etcd/pkg"
ln -sfn "$B/old-work-source" "$GPO/src/github.com/coreos/etcd/raft"
echo "build overlay ready: $GP (update) $GPO (baseline control)"
