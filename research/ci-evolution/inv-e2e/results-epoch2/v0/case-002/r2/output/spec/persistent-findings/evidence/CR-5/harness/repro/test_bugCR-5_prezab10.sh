#!/usr/bin/env bash
# CR-5 (D-4): pre-Zab1.0 leader sync no longer starts the learner server (Level 0 fixture)
# Runs the JUnit reproduction on the updated tree (artifact 2efbdfc + test
# sources only, no instrumentation) and on the old tree (baseline 1414ebf) as a
# control.  Logs: spec/output/repro-prezab10-fixture-{new,old}.log and *-surefire-output.txt
set -u
here="$(cd "$(dirname "$0")" && pwd)"
timeout 1200s "$here/../repro.sh" prezab10-fixture "SpecularUpdateScenariosTest#testPreZab10LeaderSync" both
