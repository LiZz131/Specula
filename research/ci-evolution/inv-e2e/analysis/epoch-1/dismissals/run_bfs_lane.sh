#!/bin/bash
# usage: run_bfs_lane.sh QUEUEFILE  -- each line: ARM CASE ID MODULE CFG ; lines are claimed atomically
D=$(cd "$(dirname "$0")" && pwd)
Q=$1
while true; do
  line=$(flock "$Q.lock" bash -c "head -1 '$Q'; sed -i '1d' '$Q'")
  [ -z "$line" ] && break
  set -- $line
  python3 "$D/run_probe.py" "$1" "$2" "$3" "$4" "$5" bfs 1800
done
