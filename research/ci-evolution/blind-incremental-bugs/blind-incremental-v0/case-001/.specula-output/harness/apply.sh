#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work_source=${SPECULA_WORK_SOURCE:-/work/work-source}
patch_file="$script_dir/patches/instrumentation.patch"

test -d "$work_source/.git"
test -s "$patch_file"

if git -C "$work_source" apply --reverse --check "$patch_file" 2>/dev/null; then
    echo "Specula instrumentation is already applied to $work_source"
elif git -C "$work_source" apply --check "$patch_file"; then
    git -C "$work_source" apply "$patch_file"
    echo "Applied Specula instrumentation to $work_source"
else
    echo "Instrumentation patch does not match $work_source" >&2
    exit 1
fi
