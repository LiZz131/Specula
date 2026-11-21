#!/usr/bin/env bash
set -euo pipefail

work_source="${SPECULA_WORK_SOURCE:-/work/work-source}"
patch_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/instrumentation.patch"

if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Instrumentation is already applied to $work_source"
    exit 0
fi

git -C "$work_source" apply --check "$patch_file"
git -C "$work_source" apply "$patch_file"
echo "Applied test-only instrumentation to $work_source"

