#!/usr/bin/env bash
# Apply the test-only trace instrumentation to a writable copy of the updated
# source. Default work copy: <suite>/work-source (a plain copy of artifact/).
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
patch_file="$suite_root/harness/instrumentation.patch"

if [ ! -d "$work_source" ]; then
    cp -a "$suite_root/artifact" "$work_source"
fi
if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Instrumentation is already applied to $work_source"
    exit 0
fi
git -C "$work_source" apply --check "$patch_file"
git -C "$work_source" apply "$patch_file"
echo "Applied test-only instrumentation to $work_source"
