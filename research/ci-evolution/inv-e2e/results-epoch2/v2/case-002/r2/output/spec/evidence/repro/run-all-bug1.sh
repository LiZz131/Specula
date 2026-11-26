#!/usr/bin/env bash
# Full MC-1 reproduction/control matrix (sequential; each run has its own 900 s timeout).
cd /work/current/.specular-output/repro
./test_bug1_newleader_ack_before_fsync.sh new 3 hold15s ""
./test_bug1_newleader_ack_before_fsync.sh new 1 control-noimage "-Drepro.restoreImages=false"
./test_bug1_newleader_ack_before_fsync.sh new 3 natural-nohold "-Drepro.fsyncHoldMs=0"
./test_bug1_newleader_ack_before_fsync.sh old 2 hold15s ""
./test_bug1_newleader_ack_before_fsync.sh old 1 control-noimage "-Drepro.restoreImages=false"
