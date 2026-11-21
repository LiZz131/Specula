#!/usr/bin/env bash
# GOPATH overlay for the pre-module tree (same pins as V0): protobuf v1.3.5,
# x/net v0.7.0, and the scheduler-only pkg/testutil shim needed only to compile
# node_test.go. Usage: gopath.sh <raft-tree>
set -euo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
TREE="$(readlink -f "$1")"
GP="$OUTPUT_ROOT/build/gopath"
MC="$OUTPUT_ROOT/build/gomodcache"
if [ ! -d "$MC/github.com/golang/protobuf@v1.3.5" ] || [ ! -d "$MC/golang.org/x/net@v0.7.0" ]; then
  mkdir -p "$OUTPUT_ROOT/build/modfetch"
  printf 'module speculafetch\n\ngo 1.20\n' > "$OUTPUT_ROOT/build/modfetch/go.mod"
  ( cd "$OUTPUT_ROOT/build/modfetch" && GOMODCACHE="$MC" GOFLAGS=-modcacherw \
      timeout 5m go mod download github.com/golang/protobuf@v1.3.5 golang.org/x/net@v0.7.0 )
fi
mkdir -p "$GP/src/github.com/golang" "$GP/src/golang.org/x" "$GP/src/github.com/coreos/etcd/pkg/testutil"
[ -d "$GP/src/github.com/golang/protobuf" ] || cp -r "$MC/github.com/golang/protobuf@v1.3.5" "$GP/src/github.com/golang/protobuf"
[ -d "$GP/src/golang.org/x/net" ] || cp -r "$MC/golang.org/x/net@v0.7.0" "$GP/src/golang.org/x/net"
chmod -R u+w "$GP/src"
cat > "$GP/src/github.com/coreos/etcd/pkg/testutil/testutil.go" <<'GO'
// Package testutil is a Specula build shim: the supplied raft subset imports
// it only for WaitSchedule in node_test.go. It is not part of the input tree.
package testutil

import "time"

// WaitSchedule briefly yields so goroutines started by the test can run.
func WaitSchedule() { time.Sleep(10 * time.Millisecond) }
GO
ln -sfn "$TREE" "$GP/src/github.com/coreos/etcd/raft"
echo "$GP"
