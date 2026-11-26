#!/usr/bin/env bash
# MC-1: NEWLEADER-quorum-committed DIFF txn lost after follower crash (Level 1 timing + crash emulation)
# Runs the JUnit reproduction on the updated tree (artifact 2efbdfc + test
# sources only, no instrumentation) and on the old tree (baseline 1414ebf) as a
# control.  Logs: spec/output/repro-durability-cluster-{new,old}.log and *-surefire-output.txt
set -u
here="$(cd "$(dirname "$0")" && pwd)"
timeout 1200s "$here/../repro.sh" durability-cluster "SpecularReproTest#testServedTxnSurvivesFollowerCrashAfterNewLeaderAck" both
