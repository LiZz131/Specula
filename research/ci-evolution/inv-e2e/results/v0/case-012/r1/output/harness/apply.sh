#!/usr/bin/env bash
# Rebased from the V0 prior: the work tree is an isolated copy of the updated
# source (never the immutable artifact itself).
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_tree="${SPECULA_SOURCE:-$out_dir/artifact}"
work_tree="${SPECULA_WORK_SOURCE:-$out_dir/work-source}"
patch_file="$out_dir/harness/patches/instrumentation.patch"

if [ ! -d "$work_tree" ]; then
    cp -a "$source_tree" "$work_tree"
fi

if git -C "$work_tree" apply --check "$patch_file" >/dev/null 2>&1; then
    git -C "$work_tree" apply "$patch_file"
    echo "instrumentation applied: $work_tree"
elif git -C "$work_tree" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "instrumentation already applied: $work_tree"
else
    echo "instrumentation patch neither applies nor is already present: $work_tree" >&2
    exit 1
fi
