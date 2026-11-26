#!/usr/bin/env bash
# Reproduction for MC-1 (run incr-4e410cd184be). Builds a clean copy of the
# UPDATED source (artifact HEAD), applies repro.patch (test-only: memstore
# save_vote latency knob + tests/tests/elect/t90_specular_pre_vote_repro.rs) and
# runs one test. Exit status 101 with "BUG REPRODUCED (MC-1)" = bug present;
# exit 0 = the corrected behaviour was observed.
# Usage: test_bug1_mc1_stale_timer_pre_vote.sh [--release]
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
suite="$(cd "$here/../.." && pwd)"
src="${SPECULAR_REPRO_SOURCE:-$suite/work/repro}"
if [ ! -d "$src/.git" ]; then
  mkdir -p "$src"; git -C "$suite/artifact" archive HEAD | tar -x -C "$src"
  git -C "$src" init -q; git -C "$src" add -A
  git -C "$src" -c user.name=specular -c user.email=specular@localhost commit -qm snapshot
fi
git -C "$src" apply --reverse --check "$here/repro.patch" 2>/dev/null || git -C "$src" apply "$here/repro.patch"
cd "$src"
timeout 30m cargo test ${1:-} -p tests --test elect "t90_specular_pre_vote_repro::specular_mc1_timer_pre_vote_round_preempts_new_leader" -- --exact --nocapture
