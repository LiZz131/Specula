#!/bin/bash
# Run run_coverage.py on all 21 final specs, two specs at a time, 16 single-worker TLC jobs each.
cd "$(dirname "$0")"
for a in v0 v1 v2; do for c in case-002 case-003 case-004 case-006 case-010 case-011 case-012; do echo "$a $c"; done; done |
  xargs -P 2 -L 1 sh -c 'python3 run_coverage.py "$0" "$1" --jobs 16 > "logs/$0-$1.log" 2>&1; echo "done $0 $1"'
