#!/usr/bin/env bash
# Create (if needed) a writable copy of the frozen updated source and apply the
# test-only Specular instrumentation patch. The artifact tree itself is never
# modified.
set -euo pipefail

suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact="${SPECULAR_ARTIFACT:-$suite_root/artifact}"
work_source="${SPECULAR_WORK_SOURCE:-$suite_root/work-source}"
patch_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/instrumentation.patch"

if [ ! -d "$work_source/openraft" ]; then
    mkdir -p "$work_source"
    tar -C "$artifact" --exclude=.git -cf - . | tar -C "$work_source" -xf -
fi

cd "$work_source"
if patch -p1 -R --dry-run -s -f < "$patch_file" >/dev/null 2>&1; then
    echo "Instrumentation is already applied to $work_source"
    exit 0
fi
patch -p1 --dry-run -s -f < "$patch_file"
patch -p1 -s -f < "$patch_file"
echo "Applied test-only instrumentation to $work_source"
