#!/usr/bin/env bash
# Full collection: new-revision scenarios, old-revision control, reproduction tests.
OUTPUT=/work/current/.specula-output
cd "$OUTPUT"
harness/run.sh > spec/output/harness/run-new.out 2>&1; echo "run.sh rc=$?"
harness/run-old-control.sh > spec/output/harness/run-old-control.out 2>&1; echo "old-control rc=$?"
harness/repro/run-repro.sh new SpeculaTruncAbortReproTest trunc-abort > spec/output/repro/trunc-abort-new.out 2>&1; echo "repro-new rc=$?"
harness/repro/run-repro.sh old SpeculaTruncAbortReproTest trunc-abort > spec/output/repro/trunc-abort-old.out 2>&1; echo "repro-old rc=$?"
