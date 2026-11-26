#!/usr/bin/env bash
# MC-3: follower rejoining an established leader under write load -> NPE (real cluster, Level 0)
# Runs the JUnit reproduction on the updated tree (artifact 2efbdfc + test
# sources only, no instrumentation) and on the old tree (baseline 1414ebf) as a
# control.  Logs: spec/output/repro-npe-cluster-{new,old}.log and *-surefire-output.txt
set -u
here="$(cd "$(dirname "$0")" && pwd)"
timeout 1200s "$here/../repro.sh" npe-cluster "SpecularReproTest#testFollowerRejoinsEstablishedLeaderUnderLoad" both
