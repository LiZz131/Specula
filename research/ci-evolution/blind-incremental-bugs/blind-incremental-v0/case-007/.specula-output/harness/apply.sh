#!/usr/bin/env bash
set -euo pipefail

work=/work/work-source
patch=/work/prior/.specula-output/harness/patches/instrumentation.patch

if rg -q '^mod tla_trace;$' "$work/openraft/src/lib.rs"; then
    exit 0
fi

git -C "$work" apply --check "$patch"
git -C "$work" apply "$patch"

