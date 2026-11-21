#!/usr/bin/env bash
# Apply the test-only Specula trace harness to a writable copy of the updated
# source. Rebased from the V0 patch: the V0 hunk for engine/mod.rs no longer
# applies (source drift: the update added handle_pre_vote_*_test and
# pre_elect_test modules), so the module is installed by copy + one-line
# registration instead of a context patch. The resulting diff is recorded in
# harness/instrumentation.patch.
set -euo pipefail

harness_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$harness_dir/../work-source}"
mod_rs="$work_source/openraft/src/engine/mod.rs"
dst="$work_source/openraft/src/engine/tests/specula_trace_test.rs"

cp "$harness_dir/src/specula_trace_test.rs" "$dst"
if ! grep -q 'mod specula_trace_test;' "$mod_rs"; then
    # register right after the existing `mod startup_test;` inside `mod tests`
    sed -i 's/^    mod startup_test;$/    mod startup_test;\n    mod specula_trace_test;/' "$mod_rs"
fi
grep -q 'mod specula_trace_test;' "$mod_rs"
(cd "$work_source" && git diff --stat && git diff -- openraft/src/engine/mod.rs > "$harness_dir/instrumentation.patch" \
    && git diff --no-index /dev/null openraft/src/engine/tests/specula_trace_test.rs >> "$harness_dir/instrumentation.patch" || true)
echo "Applied test-only instrumentation to $work_source"
