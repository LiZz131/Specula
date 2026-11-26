#!/usr/bin/env bash
# MC-2: real leader discards NEWLEADER ACKs and cannot establish its epoch (Level 1 delay)
# Runs the JUnit reproduction on the updated tree (artifact 2efbdfc + test
# sources only, no instrumentation) and on the old tree (baseline 1414ebf) as a
# control.  Logs: spec/output/repro-ackorder-cluster-{new,old}.log and *-surefire-output.txt
set -u
here="$(cd "$(dirname "$0")" && pwd)"
timeout 1200s "$here/../repro.sh" ackorder-cluster "SpecularReproTest#testNewLeaderQuorumWithDelayedNewLeaderAck" both
