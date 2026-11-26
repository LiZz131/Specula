#!/usr/bin/env bash
# Reproduce MC-1 on the updated implementation via integration tests.
# Usage: run-repro.sh [N_RUNS] [TEST_FILTER]
#  - level 1: public API only (router post-hook delays response delivery)
#  - level 3: timer path; requires the memstore SaveVote delay hook
#    (harness/repro/memstore-savevote-block.patch, test storage only).
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_source="${SPECULAR_WORK_SOURCE:-$suite_root/work-source}"
n="${1:-3}"; filter="${2:-specular_mc1}"
"$suite_root/harness/apply-instrumentation.sh" >/dev/null
cd "$work_source"
if ! patch -p1 -R --dry-run -s -f < "$suite_root/harness/repro/memstore-savevote-block.patch" >/dev/null 2>&1; then
  patch -p1 -s -f < "$suite_root/harness/repro/memstore-savevote-block.patch"
fi
cp "$suite_root/harness/repro/t13_specular_mc1_prevote_reelect.rs" tests/tests/elect/
grep -q t13_specular_mc1_prevote_reelect tests/tests/elect/main.rs \
  || echo "mod t13_specular_mc1_prevote_reelect;" >> tests/tests/elect/main.rs
for k in $(seq 1 "$n"); do
  echo "=== run $k $(date -u +%FT%TZ) filter=$filter"
  RUSTUP_TOOLCHAIN=nightly-2026-03-01 timeout 5m cargo test -p tests --test elect "$filter" -- --nocapture --test-threads=1 2>&1 \
     | grep -E "specular|SPECULAR|panicked|test result|FAILED|^test |assert"
  echo "=== exit ${PIPESTATUS[0]}"
done
# Level-1-only variant (no memstore hook needed), e.g. for controls on other
# revisions that have the Pre-Vote API:
#   cp harness/repro/t13_specular_mc1_level1_only.rs <tree>/tests/tests/elect/t13_specular_mc1_prevote_reelect.rs
#   echo 'mod t13_specular_mc1_prevote_reelect;' >> <tree>/tests/tests/elect/main.rs
#   cargo test -p tests --test elect specular_mc1 -- --nocapture --test-threads=1
