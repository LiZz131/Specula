#!/usr/bin/env bash
# Apply the test-only Specular instrumentation to a writable copy of the
# current source (never to the frozen artifact/ tree).
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULAR_WORK_SOURCE:-$suite_root/work-source}"
patch_file="$suite_root/harness/instrumentation.patch"

if [ ! -d "$work_source/.git" ]; then
    cp -a "$suite_root/artifact" "$work_source"
fi

if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Instrumentation is already applied to $work_source"
    exit 0
fi

git -C "$work_source" apply --check "$patch_file"
git -C "$work_source" apply "$patch_file"
echo "Applied test-only instrumentation to $work_source ($(git -C "$work_source" rev-parse HEAD))"
