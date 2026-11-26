#!/usr/bin/env bash
# MC-3: COMMIT after NEWLEADER for a buffered proposal -> NPE (legitimate wire sequence from a test-side leader, Level 0)
# Runs the JUnit reproduction on the updated tree (artifact 2efbdfc + test
# sources only, no instrumentation) and on the old tree (baseline 1414ebf) as a
# control.  Logs: spec/output/repro-npe-fixture-{new,old}.log and *-surefire-output.txt
set -u
here="$(cd "$(dirname "$0")" && pwd)"
timeout 1200s "$here/../repro.sh" npe-fixture "SpecularUpdateScenariosTest#testCommitAfterNewLeaderForPreNewLeaderProposal" both
