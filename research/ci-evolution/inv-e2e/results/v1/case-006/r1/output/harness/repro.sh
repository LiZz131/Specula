#!/usr/bin/env bash
# MC-1 reproduction on a PRISTINE export of a revision (no instrumentation):
# copies only harness/repro/specula_repro_readindex_test.go into the tree.
#   TARGET_REV=<rev> repro.sh <log>      exit status = go test status
set -uo pipefail
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
LOG="${1:?log path}"
ARTIFACT="${ARTIFACT:-$OUTPUT_ROOT/artifact}"
GO_CACHE="$OUTPUT_ROOT/build/go-cache"
REV="$(git -C "$ARTIFACT" rev-parse "${TARGET_REV:-c780d355cfeae6ee6be52c50c1f0bd7d30c6657a}^{commit}")" || exit 2
TREE="$OUTPUT_ROOT/build/repro-pristine-${REV:0:12}"
rm -rf "${TREE:?}"; mkdir -p "$TREE"
git -C "$ARTIFACT" archive "$REV" | tar -x -C "$TREE" || exit 2
cp "$HARNESS_DIR/repro/specula_repro_readindex_test.go" "$TREE/"
GOPATH_ROOT="$("$HARNESS_DIR/gopath.sh" "$TREE")" || exit 2
{ echo "rev=$REV tree=$TREE (pristine + repro test only)"; echo "go=$(go version)";
  echo "cmd: go test -vet=off github.com/coreos/etcd/raft -count=3 -v -run '^(TestSpeculaReproStaleReadAfterContextReuse|TestRaftFreesReadOnlyMem)\$'"; } > "$LOG"
timeout 10m env GO111MODULE=off GOPATH="$GOPATH_ROOT" GOCACHE="$GO_CACHE" GOFLAGS= \
  go test -vet=off github.com/coreos/etcd/raft -count=3 -v \
  -run '^(TestSpeculaReproStaleReadAfterContextReuse|TestRaftFreesReadOnlyMem)$' >> "$LOG" 2>&1
rc=$?
echo "exit=$rc" >> "$LOG"
exit $rc
