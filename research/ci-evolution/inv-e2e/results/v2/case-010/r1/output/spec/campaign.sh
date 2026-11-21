#!/usr/bin/env bash
# Usage: campaign.sh <listfile> <parallelism>; each line: module cfg name minutes workers [simdepth]
cd /work/current/.specula-output/spec
grep -v '^#' "$1" | grep -v '^\s*$' | xargs -P "$2" -L 1 bash -c 'TLC_HEAP=${TLC_HEAP:-14g} ./run_tlc.sh "$0" "$1" "$2" "$3" "$4" "${5:-}"'
