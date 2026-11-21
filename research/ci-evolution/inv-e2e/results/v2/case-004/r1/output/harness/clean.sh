#!/usr/bin/env bash
# Remove the Specula instrumentation from the artifact tree.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tree="${SPECULA_WORK_TREE:-$here/../artifact}"
cd "$tree"
git apply --reverse "$here/instrumentation.patch"
