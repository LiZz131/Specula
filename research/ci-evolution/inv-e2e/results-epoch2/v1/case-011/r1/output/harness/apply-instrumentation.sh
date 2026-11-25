#!/usr/bin/env bash
# Apply the rebased test-only instrumentation to a clean writable copy of the
# updated source (default: .specula-output/work-source, a copy of artifact/ at
# commit 3ab6cdd "update"). The immutable artifact/ tree itself is untouched.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_source="${SPECULA_WORK_SOURCE:-$suite_root/work-source}"
patch_file="${SPECULA_PATCH:-$suite_root/harness/instrumentation.patch}"

if [ ! -d "$work_source/.git" ]; then
    cp -a "$suite_root/artifact" "$work_source"
fi

if git -C "$work_source" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    echo "Instrumentation is already applied to $work_source"
    exit 0
fi

git -C "$work_source" apply --check "$patch_file"
git -C "$work_source" apply "$patch_file"
echo "Applied test-only instrumentation to $work_source ($(git -C "$work_source" rev-parse --short HEAD))"
