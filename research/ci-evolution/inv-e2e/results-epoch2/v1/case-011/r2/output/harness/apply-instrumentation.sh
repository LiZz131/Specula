#!/usr/bin/env bash
# Apply the test-only Specular instrumentation to a writable checkout of the
# update revision. Default: a detached git worktree of the artifact tree, so the
# artifact itself stays at the clean `update` commit.
set -euo pipefail

harness_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact="${SPECULAR_ARTIFACT:-$harness_dir/../artifact}"
work_source="${SPECULAR_WORK_SOURCE:-$harness_dir/work-source}"
patch_file="$harness_dir/instrumentation.patch"

if [ ! -e "$work_source/.git" ]; then
    git -C "$artifact" worktree add -q --detach "$work_source" HEAD
fi

if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Instrumentation is already applied to $work_source"
    exit 0
fi

git -C "$work_source" apply --check "$patch_file"
git -C "$work_source" apply "$patch_file"
echo "Applied test-only instrumentation to $work_source ($(git -C "$work_source" rev-parse HEAD))"
