#!/usr/bin/env bash
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_tree="${SPECULA_WORK_SOURCE:-/work/work-source}"
patch_file="$out_dir/harness/patches/instrumentation.patch"

if git -C "$work_tree" apply --check "$patch_file" >/dev/null 2>&1; then
    git -C "$work_tree" apply "$patch_file"
elif git -C "$work_tree" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "instrumentation already applied: $work_tree"
else
    echo "instrumentation patch neither applies nor is already present: $work_tree" >&2
    exit 1
fi
