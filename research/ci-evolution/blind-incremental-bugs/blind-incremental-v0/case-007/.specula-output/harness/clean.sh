#!/usr/bin/env bash
set -euo pipefail

find /work/prior/.specula-output/traces -maxdepth 1 -type f -name '*.ndjson' -delete
find /work/prior/.specula-output/spec/output -maxdepth 1 -type f -name 'harness-*.log' -delete
if [[ -d /dev/shm/specula-v0-case-007 ]]; then
    find /dev/shm/specula-v0-case-007 -mindepth 1 -delete
    rmdir /dev/shm/specula-v0-case-007
fi

