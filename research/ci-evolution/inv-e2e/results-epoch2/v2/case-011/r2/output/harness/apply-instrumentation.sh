#!/usr/bin/env bash
# Apply the test-only Specular instrumentation to a clean writable copy of the
# updated source. Default copy: .specular-output/work/source (created from the
# artifact HEAD with `git archive`, then `git init` for patch bookkeeping).
set -euo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULAR_WORK_SOURCE:-$suite_root/work/source}"
artifact="${SPECULAR_ARTIFACT:-$suite_root/artifact}"
patch_file="$suite_root/harness/instrumentation.patch"

if [ ! -d "$work_source/.git" ]; then
    mkdir -p "$work_source"
    git -C "$artifact" archive HEAD | tar -x -C "$work_source"
    git -C "$work_source" init -q
    git -C "$work_source" add -A
    git -C "$work_source" -c user.name=specular -c user.email=specular@localhost \
        commit -qm "updated source snapshot ($(git -C "$artifact" rev-parse --short HEAD))"
fi

if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Instrumentation is already applied to $work_source"
    exit 0
fi
git -C "$work_source" apply --check "$patch_file"
git -C "$work_source" apply "$patch_file"
echo "Applied test-only instrumentation to $work_source"
