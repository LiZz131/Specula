#!/usr/bin/env bash
# Rebased from the V0 prior: prepares the instrumented work tree for the
# UPDATED source.  If the work tree does not exist it is created as a copy of
# the writable updated artifact tree (two synthetic commits, HEAD = update).
set -euo pipefail

out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_tree="${SPECULA_WORK_SOURCE:-$out_dir/work/instrumented}"
artifact="${SPECULA_ARTIFACT:-$out_dir/artifact}"
patch_file="$out_dir/harness/patches/instrumentation.patch"

if [ ! -d "$work_tree/.git" ]; then
    mkdir -p "$(dirname "$work_tree")"
    cp -a "$artifact" "$work_tree"
    git -C "$work_tree" reset -q --hard HEAD
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
echo "source HEAD: $(git -C "$work_tree" rev-parse HEAD) ($(git -C "$work_tree" log -1 --format=%s))"
