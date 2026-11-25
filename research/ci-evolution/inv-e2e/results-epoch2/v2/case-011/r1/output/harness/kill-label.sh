#!/usr/bin/env bash
# Kill TLC java processes whose -metadir ends with mc-<label> (exact), by PID.
label="$1"
for pid in $(pgrep java); do
  if tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | grep -q -- "-metadir /dev/shm/specula-e2e-case-011/mc-$label "; then
    echo "killing $pid"; kill "$pid"
  fi
done
