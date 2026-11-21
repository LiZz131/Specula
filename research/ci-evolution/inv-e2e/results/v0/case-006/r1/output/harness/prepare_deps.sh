#!/usr/bin/env bash
# Prepare the read-only GOPATH dependency overlay (outside the source tree).
# Pinned ordinary build dependencies of the pre-module source:
#   github.com/golang/protobuf v1.3.5, golang.org/x/net v0.7.0
# plus a scheduler-only shim for github.com/coreos/etcd/pkg/testutil, which
# the supplied subset imports only from node_test.go (WaitSchedule).
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
B="$OUTPUT_ROOT/build"
DEPS="$B/gopath/src"
if [ -f "$DEPS/github.com/golang/protobuf/proto/lib.go" ] && \
   [ -f "$DEPS/golang.org/x/net/context/context.go" ] && \
   [ -f "$DEPS/github.com/coreos/etcd/pkg/testutil/testutil.go" ]; then
    echo "dependency overlay present: $DEPS"; exit 0
fi
mkdir -p "$B/modtmp" "$DEPS/github.com/golang" "$DEPS/golang.org/x" \
         "$DEPS/github.com/coreos/etcd/pkg/testutil"
cat > "$B/modtmp/go.mod" <<'MOD'
module speculadeps
go 1.20
MOD
(cd "$B/modtmp" && timeout 5m env GOMODCACHE="$B/gomodcache" GOFLAGS=-modcacherw \
    go mod download github.com/golang/protobuf@v1.3.5 golang.org/x/net@v0.7.0)
rm -rf "$DEPS/github.com/golang/protobuf" "$DEPS/golang.org/x/net"
cp -r "$B/gomodcache/github.com/golang/protobuf@v1.3.5" "$DEPS/github.com/golang/protobuf"
cp -r "$B/gomodcache/golang.org/x/net@v0.7.0" "$DEPS/golang.org/x/net"
chmod -R u+w "$DEPS"
cat > "$DEPS/github.com/coreos/etcd/pkg/testutil/testutil.go" <<'GO'
// Package testutil is a build-overlay shim, outside the supplied source tree.
// The supplied raft subset imports it only from node_test.go for
// WaitSchedule; this shim provides a scheduler yield with no protocol effect.
package testutil

import "time"

// WaitSchedule briefly yields so other goroutines can be scheduled.
func WaitSchedule() { time.Sleep(10 * time.Millisecond) }
GO
echo "dependency overlay prepared: $DEPS"
