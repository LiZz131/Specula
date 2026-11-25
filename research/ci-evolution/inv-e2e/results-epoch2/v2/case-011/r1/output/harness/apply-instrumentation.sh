#!/usr/bin/env bash
# Copy-and-patch rebase of the V0 test-only instrumentation onto the updated
# tree. The V0 git patch (instrumentation.patch, kept for provenance) no
# longer applies: openraft/src/engine/mod.rs gained `mod pre_elect_test;`
# between the patch's context lines (spec/output/harness-rebase-check.log).
set -euo pipefail
harness_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$harness_dir/work/source-new}"
mod_rs="$work_source/openraft/src/engine/mod.rs"
cp "$harness_dir/src/specula_trace_test.rs" "$work_source/openraft/src/engine/tests/specula_trace_test.rs"
if ! grep -q '^    mod specula_trace_test;' "$mod_rs"; then
    # Insert into the #[cfg(test)] `mod tests { ... }` list, after startup_test.
    sed -i 's/^    mod startup_test;$/    mod startup_test;\n    mod specula_trace_test;/' "$mod_rs"
fi
grep -q '^    mod specula_trace_test;' "$mod_rs"
( cd "$work_source" && git diff --no-index /dev/null openraft/src/engine/tests/specula_trace_test.rs > /dev/null 2>&1 || true )
echo "Applied test-only instrumentation to $work_source"
