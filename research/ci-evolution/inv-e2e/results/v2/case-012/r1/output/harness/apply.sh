#!/usr/bin/env bash
# V1: apply the rebased instrumentation patch to the updated source work tree.
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_tree="${SPECULA_WORK_SOURCE:-$out_dir/work-source}"
patch_file="$out_dir/harness/patches/instrumentation.patch"

if [ ! -d "$work_tree/.git" ]; then
    # Fresh work tree: copy the updated artifact tree (commit `update`).
    cp -a "$out_dir/artifact" "$work_tree"
fi

if git -C "$work_tree" apply --check "$patch_file" >/dev/null 2>&1; then
    git -C "$work_tree" apply "$patch_file"
elif git -C "$work_tree" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "instrumentation already applied: $work_tree"
else
    echo "instrumentation patch neither applies nor is already present: $work_tree" >&2
    exit 1
fi
echo "work tree HEAD: $(git -C "$work_tree" rev-parse HEAD) ($(git -C "$work_tree" log -1 --format=%s))"
