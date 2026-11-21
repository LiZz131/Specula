#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_source="${1:-$(cd "$script_dir/.." && pwd)/artifact}"
patch_file="$script_dir/patches/instrumentation.patch"

if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Specula instrumentation is already applied to $work_source"
elif git -C "$work_source" apply --check "$patch_file"; then
    git -C "$work_source" apply "$patch_file"
    echo "Applied Specula instrumentation to $work_source"
else
    echo "Instrumentation patch neither applies nor reverses cleanly: $patch_file" >&2
    exit 1
fi

