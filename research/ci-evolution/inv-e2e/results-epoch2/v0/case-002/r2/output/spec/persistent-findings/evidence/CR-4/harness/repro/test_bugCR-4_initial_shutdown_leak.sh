#!/usr/bin/env bash
# CR-4 (D-5): learner failing between NEWLEADER and UPTODATE leaks its request processors (Level 0 fixture)
# Runs the JUnit reproduction on the updated tree (artifact 2efbdfc + test
# sources only, no instrumentation) and on the old tree (baseline 1414ebf) as a
# control.  Logs: spec/output/repro-leak-fixture-{new,old}.log and *-surefire-output.txt
set -u
here="$(cd "$(dirname "$0")" && pwd)"
timeout 1200s "$here/../repro.sh" leak-fixture "SpecularUpdateScenariosTest#testShutdownAfterFailureBetweenNewLeaderAndUpToDate" both
