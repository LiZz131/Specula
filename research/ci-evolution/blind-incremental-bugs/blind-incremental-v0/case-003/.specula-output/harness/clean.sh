#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work_source="${1:-/work/work-source}"
patch_file="$script_dir/patches/instrumentation.patch"

if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    git -C "$work_source" apply --reverse "$patch_file"
    echo "Removed Specula instrumentation from $work_source"
elif git -C "$work_source" apply --check "$patch_file" >/dev/null 2>&1; then
    echo "Specula instrumentation is already absent from $work_source"
else
    echo "Working tree does not match either side of the instrumentation patch" >&2
    exit 1
fi

