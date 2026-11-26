#!/usr/bin/env bash
# Reproduce MC-1 and CR-2 on the update revision through the public Raft API.
# Applies the test-only reproduction patch (router response-delay knob + test)
# to a detached worktree of the artifact tree and runs it in debug and release.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite="$(cd "$here/../.." && pwd)"
wt="${SPECULAR_REPRO_WORKTREE:-$suite/harness/repro-worktree}"
toolchain="${SPECULAR_RUST_TOOLCHAIN:-nightly-2026-03-01}"
[ -e "$wt/.git" ] || git -C "$suite/artifact" worktree add -q --detach "$wt" HEAD
git -C "$wt" apply --reverse --check "$here/specular-repro-all.patch" 2>/dev/null || git -C "$wt" apply "$here/specular-repro-all.patch"
cd "$wt"
echo "source: $(git rev-parse HEAD)"
RUSTUP_TOOLCHAIN="$toolchain" timeout 30m cargo test -p tests --test elect specular_repro -- --test-threads=1 --nocapture
RUSTUP_TOOLCHAIN="$toolchain" timeout 40m cargo test --release -p tests --test elect specular_repro -- --test-threads=1 --nocapture
