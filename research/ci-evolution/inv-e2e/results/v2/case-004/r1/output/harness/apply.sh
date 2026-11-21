#!/usr/bin/env bash
# Apply the Specula instrumentation patch to the artifact tree (idempotent).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tree="${SPECULA_WORK_TREE:-$here/../artifact}"
patch="$here/instrumentation.patch"
cd "$tree"
if git apply --reverse --check "$patch" 2>/dev/null; then
    echo "instrumentation already applied"
else
    git apply "$patch"
    echo "instrumentation applied"
fi
