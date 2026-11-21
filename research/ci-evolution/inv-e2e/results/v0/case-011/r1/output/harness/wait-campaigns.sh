#!/usr/bin/env bash
# Block until no campaign runner is alive (polls the process table).
while ps -eo args | grep -E "harness/run-(campaigns|fixcheck)\.sh" | grep -vE "grep|wait-campaigns" >/dev/null; do sleep 30; done
date -u
